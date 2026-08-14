#!/usr/bin/env python3
"""Fully detach a child process so it survives the launching shell."""
import os
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: detach.py <program> [args...]", file=sys.stderr)
        return 1

    pid = os.fork()
    if pid > 0:
        return 0

    os.setsid()
    pid = os.fork()
    if pid > 0:
        os._exit(0)

    os.execvp(sys.argv[1], sys.argv[1:])
    return 127


if __name__ == "__main__":
    sys.exit(main())
