#!/usr/bin/env python3
"""One authenticated SSH session owns one controller. SSH control plane and session-authenticated UDP input."""
import atexit
import base64
import hashlib
import hmac
import socket
import fcntl
import json
import math
import os
from pathlib import Path
import select
import signal
import sys
import time

sys.path.insert(0, str(Path(__file__).parent / 'vendor'))
BUTTONS = frozenset('A B X Y L R ZL ZR PLUS MINUS HOME CAPTURE L_STICK_PRESS R_STICK_PRESS DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT'.split())
STALE_SECONDS = 0.35
MAX_LINE = 4096


def decode_input(line):
    data = json.loads(line)
    if not isinstance(data, dict) or data.get('type') != 'input':
        raise ValueError('Expected input')
    buttons = data.get('buttons', [])
    if not isinstance(buttons, list) or len(buttons) > len(BUTTONS) or any(not isinstance(b, str) or b not in BUTTONS for b in buttons):
        raise ValueError('Invalid buttons')
    axes = []
    for name in ('lx', 'ly', 'rx', 'ry'):
        value = data.get(name, 0)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not -1 <= value <= 1:
            raise ValueError('Invalid axis')
        axes.append(round(value * 100))
    return buttons, axes


def decode_datagram(data, key, last_sequence):
    if not 41 <= len(data) <= 2048:
        raise ValueError('Invalid datagram length')
    message, signature = data[:-32], data[-32:]
    if not hmac.compare_digest(hmac.new(key, message, hashlib.sha256).digest(), signature):
        raise ValueError('Invalid datagram authentication')
    sequence = int.from_bytes(message[:8], 'big')
    if sequence <= last_sequence:
        raise ValueError('Old datagram')
    return sequence, decode_input(message[8:])


def packet_for(nx, decoded=None):
    packet = nx.create_input_packet()
    if decoded is not None:
        buttons, axes = decoded
        for button in buttons:
            if button in ('L_STICK_PRESS', 'R_STICK_PRESS'):
                packet[button.replace('_PRESS', '')]['PRESSED'] = True
            else:
                packet[button] = True
        for name, x, y in [('L_STICK', axes[0], axes[1]), ('R_STICK', axes[2], axes[3])]:
            packet[name]['X_VALUE'] = x
            packet[name]['Y_VALUE'] = y
    return packet


def emit(**message):
    print(json.dumps(message), flush=True)


def main():
    import nxbt
    # Separate lock inode survives disconnects; close-on-exec isn't enough for fork.
    lock = open('/run/videogamefilter-controller.lock', 'w')
    deadline = time.monotonic() + 20
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.monotonic() >= deadline:
                emit(type='error', message='이전 연결이 아직 사용 중입니다. 잠시 후 다시 연결하세요.')
                lock.close()
                return 1
            emit(type='status', state='waiting')
            time.sleep(0.5)
    nx = None
    index = None
    controller_state = None
    udp = None
    def stop(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    # Signals during startup also have a finite cleanup path.
    def startup_timeout(signum, frame):
        raise TimeoutError('파이 컨트롤러 초기화 시간이 초과됐습니다.')
    signal.signal(signal.SIGALRM, startup_timeout)
    signal.alarm(45)
    try:
        emit(type='status', state='starting', wake=False)
        nx = nxbt.Nxbt(disable_logging=True)
        state_path = Path('/var/lib/videogamefilter-controller/console')
        reconnect = None
        if '--pair' not in sys.argv and state_path.exists():
            import re
            address = state_path.read_text().strip()
            if re.fullmatch(r'(?:[0-9A-F]{2}:){5}[0-9A-F]{2}', address):
                reconnect = address
        index = nx.create_controller(nxbt.PRO_CONTROLLER, reconnect_address=reconnect)
        signal.alarm(0)
        # Cache the nested manager proxy once. Re-fetching nx.state[index]
        # for every input creates/refcounts a proxy (~50 ms on Zero W).
        controller_state = nx.state[index]
        # Manager children inherit signals; SIGTERM is fixed in the vendored NXBT.
        last_input = time.monotonic()
        last_status = 0
        packet = packet_for(nx)
        previous_packet = None
        fd = sys.stdin.fileno()
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.bind(('0.0.0.0', 0))
        udp.setblocking(False)
        session_key = os.urandom(32)
        last_sequence = 0
        emit(type='transport', version=1, port=udp.getsockname()[1], key=base64.b64encode(session_key).decode('ascii'))
        while True:
            now = time.monotonic()
            ready, _, _ = select.select([fd, udp], [], [], 0.01)
            if fd in ready:
                # SSH is only lifecycle control. EOF releases inputs immediately.
                if not os.read(fd, 1024):
                    break
            if udp in ready:
                # Bound work per iteration; keep only the newest authenticated state.
                for _ in range(64):
                    try:
                        data = udp.recv(2049)
                    except BlockingIOError:
                        break
                    try:
                        sequence, decoded = decode_datagram(data, session_key, last_sequence)
                    except (ValueError, UnicodeError):
                        continue
                    last_sequence = sequence
                    packet = packet_for(nx, decoded)
                    last_input = time.monotonic()
            now = time.monotonic()
            if now - last_input > STALE_SECONDS:
                packet = packet_for(nx)
            # NXBT holds the shared direct_input until replaced. Avoid expensive
            # multiprocessing serialization when an unchanged heartbeat arrives.
            if packet != previous_packet:
                controller_state["direct_input"] = packet
                previous_packet = packet
            if now - last_status >= 0.5:
                # One IPC request instead of one request per dictionary field.
                state = controller_state.copy()
                status = state['state']
                emit(type='status', state=status, wake=False)
                last_status = now
                if status == 'crashed':
                    emit(type='error', message='스위치 연결 실패. 스위치를 켜고 다시 연결하거나 새로 페어링하세요.')
                    return 1
                address = state.get('last_connection')
                if status == 'connected' and address:
                    state_path.parent.mkdir(parents=True, exist_ok=True)
                    if not state_path.exists() or state_path.read_text() != address:
                        state_path.write_text(address)
            if now - last_input > 10:
                emit(type='error', message='UDP 입력이 도착하지 않습니다. 파이 주소와 네트워크를 확인하세요.')
                break
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    except Exception as error:
        emit(type='error', message=str(error)[:300])
        return 1
    finally:
        signal.alarm(0)
        if udp is not None:
            udp.close()
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        if nx is not None:
            if controller_state is not None:
                try:
                    controller_state["direct_input"] = packet_for(nx)
                    time.sleep(0.05)
                except Exception:
                    pass
            atexit.unregister(nx._on_exit)
            nx._on_exit()
        else:
            # Constructor failure may have installed the temporary BlueZ override.
            nxbt.bluez.toggle_clean_bluez(False)
        lock.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
