#!/usr/bin/env python3
"""Allocate repeatable release identifiers from GitHub's immutable run number.

No remote writes and no credentials are needed. Rerunning a workflow retains its
run number; run_attempt is deliberately not an input. Keep this workflow's
identity when editing it so its monotonically increasing counter is retained.
"""

import argparse
import json
import re
from pathlib import Path

PLAY_MAX_VERSION_CODE = 2_100_000_000
BUILD_OFFSET = 10_000
MAX_ABI_OFFSET = 4_000


def release_plan(pubspec: str, run_number: str) -> dict[str, str | int]:
    if not re.fullmatch(r"[1-9][0-9]*", run_number):
        raise ValueError("run-number must be a positive decimal integer")
    run = int(run_number)
    build = BUILD_OFFSET + run
    if build + MAX_ABI_OFFSET > PLAY_MAX_VERSION_CODE:
        raise ValueError("Android versionCode including ABI offset exceeds Play limit")
    versions = re.findall(r"^version:\s*([^\s#]+)\s*(?:#.*)?$", pubspec, re.MULTILINE)
    if len(versions) != 1:
        raise ValueError("pubspec must contain exactly one unquoted version field")
    match = re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\+(0|[1-9][0-9]*))?", versions[0])
    if not match:
        raise ValueError("pubspec version must be stable numeric major.minor.patch[+build]")
    version = f"{match[1]}.{match[2]}.{run}"
    return {"version": version, "build_number": build, "tag": f"v{version}"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    parser.add_argument("--run-number", required=True)
    parser.add_argument("--format", choices=("json", "env"), default="json")
    args = parser.parse_args()
    try:
        plan = release_plan(args.pubspec.read_text(encoding="utf-8"), args.run_number)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if args.format == "env":
        for key, value in plan.items():
            print(f"{key}={value}")
    else:
        print(json.dumps(plan, sort_keys=True))


if __name__ == "__main__":
    main()
