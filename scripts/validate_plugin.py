#!/usr/bin/env python3

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import urlparse


IDENTIFIER_PATTERN = re.compile(r"^[a-z0-9]+(?:\.[a-z0-9]+)+$")
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate Bob Wordbook plugin metadata")
    parser.add_argument("--expected-version")
    parser.add_argument("--artifact", type=Path)
    args = parser.parse_args()

    info = load_json(Path("src/info.json"))
    appcast = load_json(Path("appcast.json"))

    required = {"identifier", "version", "category", "name", "summary", "author", "minBobVersion"}
    missing = sorted(required - info.keys())
    if missing:
        raise SystemExit(f"src/info.json is missing fields: {', '.join(missing)}")
    if not IDENTIFIER_PATTERN.fullmatch(info["identifier"]):
        raise SystemExit("identifier must contain lowercase letters, digits, and dot-separated components")
    if not VERSION_PATTERN.fullmatch(info["version"]):
        raise SystemExit("version must use semantic x.y.z form")
    if args.expected_version and info["version"] != args.expected_version:
        raise SystemExit(f"plugin version {info['version']} does not match expected version {args.expected_version}")
    if info["category"] != "translate":
        raise SystemExit("category must be translate")
    if appcast.get("identifier") != info["identifier"]:
        raise SystemExit("appcast identifier must match plugin identifier")

    versions = appcast.get("versions")
    if not isinstance(versions, list):
        raise SystemExit("appcast versions must be an array")
    listed_versions = [item.get("version") for item in versions]
    if len(listed_versions) != len(set(listed_versions)):
        raise SystemExit("appcast versions must be unique")

    option_ids = [option.get("identifier") for option in info.get("options", [])]
    if len(option_ids) != len(set(option_ids)):
        raise SystemExit("plugin option identifiers must be unique")
    required_option_ids = {"apiKey", "model", "systemPrompt", "outputPath"}
    missing_option_ids = sorted(required_option_ids - set(option_ids))
    if missing_option_ids:
        raise SystemExit(f"plugin is missing options: {', '.join(missing_option_ids)}")

    if args.artifact:
        validate_artifact(args.artifact, info, versions)

    print(f"Validated plugin {info['identifier']} v{info['version']}")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"cannot read {path}: {error}") from error


def validate_artifact(artifact: Path, info: dict, versions: list[dict]) -> None:
    if not artifact.is_file():
        raise SystemExit(f"artifact does not exist: {artifact}")

    appcast_version = next((item for item in versions if item.get("version") == info["version"]), None)
    if appcast_version is None:
        raise SystemExit(f"appcast does not contain plugin version {info['version']}")

    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    if appcast_version.get("sha256") != digest:
        raise SystemExit(f"appcast SHA256 does not match {artifact}")

    artifact_name = Path(urlparse(appcast_version.get("url", "")).path).name
    if artifact_name != artifact.name:
        raise SystemExit(f"appcast URL filename {artifact_name!r} does not match {artifact.name!r}")


if __name__ == "__main__":
    main()
