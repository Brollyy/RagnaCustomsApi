from __future__ import annotations

import argparse
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
MOD_NAME = "RagnaCustomsApi"
MOD_ID = "ragnacustoms-api"
SOURCE_MOD = ROOT / "Mods" / MOD_NAME
from version import VERSION
ARCHIVE_DATE = (1980, 1, 1, 0, 0, 0)


def manifest() -> dict:
    return {
        "schemaVersion": 1,
        "id": MOD_ID,
        "name": MOD_NAME,
        "version": VERSION,
        "author": "Brollyy",
        "game": "ragnarock",
        "description": "Reusable async client for the configured RagnaCustoms leaderboard API.",
        "requires": {
            "manager": ">=0.2.0",
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
        manifest_info = zipfile.ZipInfo("manifest.json", date_time=ARCHIVE_DATE)
        manifest_info.compress_type = zipfile.ZIP_DEFLATED
        manifest_info.external_attr = 0o100644 << 16
        archive.writestr(manifest_info, json.dumps(manifest(), indent=2, sort_keys=True) + "\n")
        for path in sorted(SOURCE_MOD.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(SOURCE_MOD).as_posix(), date_time=ARCHIVE_DATE)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())


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
