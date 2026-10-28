#!/usr/bin/env python3
"""Architecture/type validation that never executes a release asset."""
from pathlib import Path
import sys


def verify(path, arch):
    with Path(path).open('rb') as stream:
        header = stream.read(20)
    if (len(header) != 20 or header[:6] != b'\x7fELF\x02\x01' or
            header[8:11] != b'AI\x02' or
            int.from_bytes(header[18:20], 'little') != {'x64': 62, 'arm64': 183}[arch]):
        raise ValueError('Expected a type-2 AppImage for ' + arch)


if __name__ == '__main__':
    verify(*sys.argv[1:])
