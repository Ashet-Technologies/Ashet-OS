#!/usr/bin/env python3

import hashlib
import pathlib
import subprocess
import sys


digest = hashlib.sha256()
entries: set[str] = set()

git_files = subprocess.run(
    ["git", "ls-files", "-z"],
    check=True,
    capture_output=True,
).stdout.split(b"\0")

manifest_paths = sorted(
    pathlib.Path(raw.decode("utf-8"))
    for raw in git_files
    if raw and (raw == b"build.zig.zon" or raw.endswith(b"/build.zig.zon"))
)

for path in manifest_paths:
    print(path.as_posix(), file=sys.stderr)

for path in manifest_paths:
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("//"):
            continue

        for key in (".url", ".hash"):
            prefix = f"{key} ="
            if not stripped.startswith(prefix):
                continue

            _, value = stripped.split("=", 1)
            value = value.strip()

            assert value.startswith('"'), f"{path}: malformed {key} entry: {line!r}"
            assert value.endswith('",'), f"{path}: malformed {key} entry: {line!r}"

            entries.add(f"{key}={value}")

for entry in sorted(entries):
    digest.update(f"{entry}\n".encode("utf-8"))

print(f"key={digest.hexdigest()}")
