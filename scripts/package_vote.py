from __future__ import annotations

import argparse
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
MOD_NAME = "RagnaCustomsVote"
SOURCE_MOD = ROOT / "Mods" / MOD_NAME


def manifest() -> dict:
    return {
        "schemaVersion": 1,
        "id": "ragnacustoms-vote",
        "name": MOD_NAME,
        "version": "0.1.0",
        "author": "RagnaCustoms voting contributors",
        "game": "ragnarock",
        "description": "Flat and PC VR Results-screen voting controls for custom songs.",
        "requires": {"manager": ">=1.1.0"},
        "dependencies": {"ragnacustoms-api": ">=0.2.0"},
        "conflicts": [],
        "files": [{"type": "ue4ss-lua", "source": "Scripts/", "modFolder": MOD_NAME}],
        "affects": [],
        "hooks": [],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Package RagnaCustomsVote as a managed .rmod archive.")
    parser.add_argument("--output", default="dist/RagnaCustomsVote.rmod")
    args = parser.parse_args()
    output = Path(args.output)
    if not output.is_absolute():
        output = ROOT / output
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest(), indent=2) + "\n")
        for path in sorted((SOURCE_MOD / "Scripts").rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(SOURCE_MOD))
    print(f"Packaged {MOD_NAME} to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
