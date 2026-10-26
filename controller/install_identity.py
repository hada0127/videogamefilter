"""Install a newly provisioned identity; preserve tokens for an identical identity."""
import json
import os
from pathlib import Path
import shutil
import uuid


def install_identity(source, target):
    source, target = Path(source), Path(target)
    incoming = json.loads((source / 'device.json').read_text())
    uuid.UUID(incoming['id'])
    existing = target / 'device.json'
    if existing.exists() and json.loads(existing.read_text())['id'] == incoming['id']:
        return False
    target.mkdir(parents=True, exist_ok=True, mode=0o700)
    target.chmod(0o700)
    for name in ('server.key', 'server.crt', 'device.json'):
        destination = target / name
        temporary = target / (name + '.new')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'wb') as stream: stream.write((source / name).read_bytes())
        os.replace(temporary, destination)
    return True


if __name__ == '__main__':
    import sys
    install_identity(sys.argv[1], sys.argv[2])
