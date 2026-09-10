from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from version import VERSION


ROOT = Path(__file__).resolve().parents[1]
MOD_NAME = "RagnaCustomsApi"
MOD_ID = "ragnacustoms-api"
SOURCE_MOD = ROOT / "Mods" / MOD_NAME
EXPECTED_FILES = (
    "Scripts/main.lua",
    "Scripts/ragnacustoms_api.lua",
)
INSTALLED_FILES = {
    "Scripts/main.lua": "scripts/main.lua",
    "Scripts/ragnacustoms_api.lua": "scripts/ragnacustoms_api.lua",
}


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def file_hash(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def win64_dir(game_dir: Path) -> Path:
    return game_dir / "Ragnarock" / "Binaries" / "Win64"


def deployed_mod_dir(game_dir: Path) -> Path:
    win64 = win64_dir(game_dir)
    manager = win64 / "ue4ss" / "Mods" / MOD_NAME
    if manager.exists():
        return manager
    return win64 / "Mods" / MOD_NAME


def legacy_mod_dir(game_dir: Path) -> Path:
    return win64_dir(game_dir) / "Mods" / MOD_NAME


def source_hashes() -> dict[str, str]:
    hashes = {}
    for relative in EXPECTED_FILES:
        path = SOURCE_MOD / relative
        if not path.exists():
            raise AssertionError(f"missing source file: {path}")
        hashes[relative] = file_hash(path)
    return hashes


def package_hashes(package_path: Path) -> dict[str, str]:
    if not package_path.exists():
        raise AssertionError(f"missing package: {package_path}")
    with zipfile.ZipFile(package_path) as archive:
        names = set(archive.namelist())
        expected_names = {"manifest.json", *EXPECTED_FILES}
        extra = names - expected_names
        missing = expected_names - names
        if missing or extra:
            raise AssertionError(f"package layout mismatch: missing={sorted(missing)} extra={sorted(extra)}")
        manifest = json.loads(archive.read("manifest.json"))
        if manifest.get("schemaVersion") != 1:
            raise AssertionError("manifest schemaVersion must be 1")
        if manifest.get("id") != MOD_ID:
            raise AssertionError(f"manifest id must be {MOD_ID}")
        if manifest.get("name") != MOD_NAME:
            raise AssertionError(f"manifest name must be {MOD_NAME}")
        if manifest.get("game") != "ragnarock":
            raise AssertionError("manifest game must be ragnarock")
        files = manifest.get("files")
        expected_files_manifest = [{"type": "ue4ss-lua", "source": "Scripts/", "modFolder": MOD_NAME}]
        if files != expected_files_manifest:
            raise AssertionError(f"unexpected manifest files: {files}")
        if manifest.get("version") != VERSION:
            raise AssertionError(f"manifest version must be {VERSION}")
        if manifest.get("requires") != {"manager": ">=0.2.0"}:
            raise AssertionError("manifest must require the dependency-aware manager")
        return {
            relative: sha256_bytes(archive.read(relative))
            for relative in EXPECTED_FILES
        }


def installed_hashes(game_dir: Path) -> dict[str, str]:
    mod_dir = deployed_mod_dir(game_dir)
    hashes = {}
    for source_relative, installed_relative in INSTALLED_FILES.items():
        path = mod_dir / source_relative
        if not path.exists():
            path = mod_dir / installed_relative
        if not path.exists():
            raise AssertionError(f"missing installed file: {path}")
        hashes[source_relative] = file_hash(path)
    return hashes


def legacy_hashes(game_dir: Path) -> dict[str, str]:
    mod_dir = legacy_mod_dir(game_dir)
    hashes = {}
    for relative in EXPECTED_FILES:
        path = mod_dir / relative
        if not path.exists():
            raise AssertionError(f"missing legacy installed file: {path}")
        hashes[relative] = file_hash(path)
    return hashes


def assert_hashes_match(label: str, expected: dict[str, str], actual: dict[str, str]) -> None:
    for relative, expected_hash in expected.items():
        actual_hash = actual.get(relative)
        if actual_hash != expected_hash:
            raise AssertionError(
                f"{label} hash mismatch for {relative}: expected {expected_hash}, got {actual_hash}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify RagnaCustomsApi source/package/install integrity.")
    parser.add_argument(
        "--package",
        default=f"dist/{MOD_NAME}.rmod",
        help="Package .rmod to verify. Defaults to dist/RagnaCustomsApi.rmod.",
    )
    parser.add_argument(
        "--game-dir",
        default=None,
        help="Optional Ragnarock game directory. When set, verifies installed mod files match source.",
    )
    args = parser.parse_args()

    package_path = Path(args.package)
    if not package_path.is_absolute():
        package_path = ROOT / package_path

    source = source_hashes()
    packaged = package_hashes(package_path)
    assert_hashes_match("package", source, packaged)
    print("package: ok")

    if args.game_dir:
        game_dir = Path(args.game_dir).expanduser()
        installed = installed_hashes(game_dir)
        assert_hashes_match("installed copy", source, installed)
        print("installed_copy: ok")
        legacy = legacy_hashes(game_dir)
        assert_hashes_match("legacy installed copy", source, legacy)
        print("legacy_installed_copy: ok")

    for relative, digest in source.items():
        print(f"{relative}: {digest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
