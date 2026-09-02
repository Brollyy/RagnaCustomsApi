from __future__ import annotations

import argparse
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
MOD_NAME = "RagnaCustomsApi"
MOD_ID = "ragnacustoms-api"
SOURCE_MOD = ROOT / "Mods" / MOD_NAME
VERSION = "0.2.0"


def manifest() -> dict:
    return {
        "schemaVersion": 1,
        "id": MOD_ID,
        "name": MOD_NAME,
        "version": VERSION,
        "author": "RagnaCustomsApi contributors",
        "game": "ragnarock",
        "description": "Reusable async client for the configured RagnaCustoms leaderboard API.",
        "requires": {
            "manager": ">=1.1.0",
        },
        "dependencies": {},
        "conflicts": [],
        "files": [
            {"type": "ue4ss-lua", "source": "Scripts/", "modFolder": MOD_NAME},
        ],
        "affects": [],
        "hooks": [],
    }


def package_mod(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", json.dumps(manifest(), indent=2) + "\n")
        for path in sorted(SOURCE_MOD.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(SOURCE_MOD))


def main() -> int:
    parser = argparse.ArgumentParser(description="Package RagnaCustomsApi as a RagnaModManager .rmod archive.")
    parser.add_argument(
        "--output",
        default=f"dist/{MOD_NAME}.rmod",
        help="Output .rmod path. Defaults to dist/RagnaCustomsApi.rmod.",
    )
    args = parser.parse_args()

    output = Path(args.output)
    if not output.is_absolute():
        output = ROOT / output

    package_mod(output)
    print(f"Packaged {MOD_NAME} to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
