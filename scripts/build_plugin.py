#!/usr/bin/env python3

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile, ZipInfo


PLUGIN_FILES = ("info.json", "main.js")
FIXED_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a deterministic Bob plugin archive")
    parser.add_argument("--source", type=Path, default=Path("src"))
    parser.add_argument("--output-dir", type=Path, default=Path("dist"))
    args = parser.parse_args()

    info = json.loads((args.source / "info.json").read_text(encoding="utf-8"))
    version = info["version"]
    output = args.output_dir / f"bob-wordbook-v{version}.bobplugin"
    args.output_dir.mkdir(parents=True, exist_ok=True)

    with ZipFile(output, "w", compression=ZIP_STORED) as archive:
        for filename in PLUGIN_FILES:
            entry = ZipInfo(filename, FIXED_TIMESTAMP)
            entry.compress_type = ZIP_STORED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, (args.source / filename).read_bytes())

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f"Built: {output.resolve()}")
    print(f"SHA256: {digest}")


if __name__ == "__main__":
    main()
