#!/usr/bin/env python3
"""Pinned-TLS enrollment/control service. Game input stays on authenticated UDP."""
import hashlib
import hmac
import json
import os
from pathlib import Path
import signal
import select
import socket
import ssl
import subprocess
import threading
import time

ROOT = Path('/var/lib/videogamefilter-controller')
APP = Path('/opt/videogamefilter-controller')
PORT = 24872


def pin_hash(device_id, pin):
    return hashlib.sha256((device_id + ':' + pin).encode()).hexdigest()


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


class Registry:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.data = json.loads(path.read_text())
        self.failures = []

    def save(self):
        temporary = self.path.with_suffix('.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(self.data, f)
            f.flush(); os.fsync(f.fileno())
        os.replace(temporary, self.path)

    def authenticate(self, request):
        client = request.get('client', '')
        if not isinstance(client, str) or not 16 <= len(client) <= 64 or not all(c.isalnum() or c == '-' for c in client):
            raise ValueError('Invalid client')
        with self.lock:
            stored = self.data.get('client')
            token = request.get('token')
            if isinstance(token, str) and stored and stored['id'] == client and hmac.compare_digest(stored['hash'], token_hash(token)):
                if not self.data.get('paired'):
                    self.data['paired'] = True; self.data.pop('pin_hash', None); self.save()
                return None
            now = time.monotonic()
            self.failures = [t for t in self.failures if now - t < 60]
            if len(self.failures) >= 5:
                raise ValueError('등록 시도가 많습니다. 1분 후 다시 시도하세요.')
            pin = request.get('pin')
            valid = (not self.data.get('paired') and isinstance(pin, str) and
                     len(pin) == 6 and pin.isascii() and pin.isdigit() and
                     (not stored or stored['id'] == client) and
                     hmac.compare_digest(self.data.get('pin_hash', ''), pin_hash(self.data['id'], pin)))
            if not valid:
                self.failures.append(now)
                raise ValueError('파이 등록 정보가 일치하지 않습니다. SD 준비 때 생성한 등록 정보를 확인하세요.')
            # Repeat enrollment for the same client yields the same token if a
            # response/confirmation was lost. PIN expires after durable receipt.
            token = hmac.new(bytes.fromhex(self.data['secret']), client.encode(), hashlib.sha256).hexdigest()
            self.data['client'] = {'id': client, 'hash': token_hash(token)}
            self.save()
            return token

    def confirm(self, client):
        with self.lock:
            if self.data.get('client', {}).get('id') != client:
                raise ValueError('Invalid enrollment confirmation')
            self.data['paired'] = True; self.data.pop('pin_hash', None); self.save()


def read_json(connection):
    buffer = bytearray()
    deadline = time.monotonic() + 10
    while len(buffer) <= 4096:
        if time.monotonic() > deadline: raise TimeoutError("Registration timeout")
        byte = connection.recv(1)
        if not byte:
            raise EOFError
        if byte == b'\n':
            result = json.loads(buffer)
            if not isinstance(result, dict):
                raise ValueError('Expected object')
            return result
        buffer.extend(byte)
    raise ValueError('Message too long')


def serve():
    registry = Registry(ROOT / 'device.json')
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(ROOT / 'server.crt', ROOT / 'server.key')
    owner = threading.Lock()
    slots = threading.BoundedSemaphore(4)
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('0.0.0.0', PORT)); listener.listen(4)

    def client(raw):
        connection = None; process = None; owned = False
        send_lock = threading.Lock()
        def send(message):
            data = json.dumps(message).encode() + b'\n'
            with send_lock:
                connection.sendall(data)
        try:
            raw.settimeout(10)
            connection = context.wrap_socket(raw, server_side=True)
            request = read_json(connection)
            if request.get('type') != 'authenticate':
                raise ValueError('Authentication required')
            issued_token = registry.authenticate(request)
            if issued_token:
                send({'type': 'enrolled', 'token': issued_token})
                if read_json(connection).get('type') != 'confirm':
                    raise ValueError('Enrollment not confirmed')
                registry.confirm(request['client'])
            owned = owner.acquire(blocking=False)
            if not owned:
                send({'type': 'error', 'message': '다른 연결이 정리 중입니다. 잠시 후 자동으로 다시 연결합니다.'})
                return
            command = ['/usr/bin/python3', '-u', str(APP / 'bridge.py')]
            if request.get('pair') is True:
                command.append('--pair')
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, start_new_session=True)
            connection.settimeout(2)
            # A single thread owns SSL reads/writes; no concurrent OpenSSL use.
            while True:
                ready, _, _ = select.select([connection, process.stdout], [], [], 1)
                if connection in ready or connection.pending():
                    try:
                        if not connection.recv(1024): break
                    except socket.timeout:
                        continue
                if process.stdout in ready:
                    data = os.read(process.stdout.fileno(), 65536)
                    if not data: break
                    connection.sendall(data)
                elif process.poll() is not None:
                    break
        except (OSError, ValueError, EOFError, RecursionError) as error:
            if connection:
                try: send({'type': 'error', 'message': str(error)[:250]})
                except OSError: pass
        finally:
            if process:
                try: process.stdin.close()
                except OSError: pass
                try: process.wait(timeout=12)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    try: process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL); process.wait()
                # Any orphaned descendants still own only this session's group.
                try: os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                process.stdout.close()
            if connection:
                try: connection.shutdown(socket.SHUT_RDWR)
                except OSError: pass
                connection.close()
            else: raw.close()
            if owned: owner.release()
            slots.release()

    while True:
        raw, _ = listener.accept()
        if not slots.acquire(blocking=False): raw.close(); continue
        threading.Thread(target=client, args=(raw,), daemon=True).start()


if __name__ == '__main__':
    serve()
