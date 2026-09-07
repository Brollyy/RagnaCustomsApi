from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


MOD_NAME = "RagnaCustomsApi"
UE4SS_MARKERS = ("UE4SS.dll", "UE4SS-settings.ini", "dwmapi.dll")
EXPECTED_FILES = (
    "Scripts/main.lua",
    "Scripts/ragnacustoms_api.lua",
)
INSTALLED_FILES = {
    "Scripts/main.lua": "scripts/main.lua",
    "Scripts/ragnacustoms_api.lua": "scripts/ragnacustoms_api.lua",
}


def win64_dir(game_dir: Path) -> Path:
    return game_dir / "Ragnarock" / "Binaries" / "Win64"


def manager_mods_dir(win64: Path) -> Path:
    return win64 / "ue4ss" / "Mods"


def legacy_mods_dir(win64: Path) -> Path:
    return win64 / "Mods"


def select_mods_dir(win64: Path) -> Path:
    # RagnaModManager gives the root/proxy-loaded layout precedence when both
    # UE4SS.dll locations exist. Keep this verifier aligned with that runtime
    # selection instead of inspecting a dormant second Mods tree.
    if (win64 / "UE4SS.dll").exists():
        return legacy_mods_dir(win64)
    manager = manager_mods_dir(win64)
    if (manager / MOD_NAME).exists() or (manager / "mods.txt").exists():
        return manager
    return legacy_mods_dir(win64)


def mods_txt_enabled(mods_txt: Path) -> bool:
    if not mods_txt.exists():
        return False
    for line in mods_txt.read_text(errors="ignore").splitlines():
        if line.strip() == f"{MOD_NAME} : 1":
            return True
    return False


def file_hash(path: Path) -> str | None:
    if not path.exists():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_mod_dir(source_root: Path) -> Path:
    return source_root / "Mods" / MOD_NAME


def installed_copy_current(source_root: Path, mod_dir: Path) -> tuple[bool, list[str]]:
    mismatches = []
    source = source_mod_dir(source_root)
    for relative, installed_relative in INSTALLED_FILES.items():
        source_hash = file_hash(source / relative)
        installed_hash = file_hash(mod_dir / relative)
        if installed_hash is None:
            installed_hash = file_hash(mod_dir / installed_relative)
        if source_hash != installed_hash:
            mismatches.append(relative)
    return not mismatches, mismatches


def legacy_copy_current(source_root: Path, win64: Path) -> tuple[bool, list[str]]:
    return installed_copy_current(source_root, legacy_mods_dir(win64) / MOD_NAME)


def main() -> int:
    parser = argparse.ArgumentParser(description="Check RagnaCustomsApi UE4SS install state.")
    parser.add_argument("--game-dir", required=True, help="Path to the Ragnarock game directory.")
    parser.add_argument(
        "--source-root",
        default=None,
        help="Optional repository root. When set, verifies installed files match current source.",
    )
    args = parser.parse_args()

    root = Path(args.game_dir).expanduser()
    win64 = win64_dir(root)
    mods = select_mods_dir(win64)
    mod_dir = mods / MOD_NAME
    legacy_mod_dir = legacy_mods_dir(win64) / MOD_NAME
    main_lua = mod_dir / "Scripts" / "main.lua"
    api_lua = mod_dir / "Scripts" / "ragnacustoms_api.lua"
    lower_main_lua = mod_dir / "scripts" / "main.lua"
    lower_api_lua = mod_dir / "scripts" / "ragnacustoms_api.lua"
    mods_txt = mods / "mods.txt"
    legacy_mods_txt = legacy_mods_dir(win64) / "mods.txt"

    markers = [name for name in UE4SS_MARKERS if (win64 / name).exists()]
    markers.extend(f"ue4ss/{name}" for name in UE4SS_MARKERS if (win64 / "ue4ss" / name).exists())
    checks = {
        "win64_dir": win64.exists(),
        "ue4ss_present": bool(markers),
        # RagnaModManager supports both UE4SS layouts; this key is retained
        # for compatibility with existing diagnostics and means the selected
        # path is a supported manager deployment target.
        "manager_mods_layout": mods in (manager_mods_dir(win64), legacy_mods_dir(win64)),
        "mods_txt": mods_txt.exists(),
        "mod_enabled": mods_txt_enabled(mods_txt),
        "main_lua": main_lua.exists(),
        "api_lua": api_lua.exists(),
        "lowercase_main_lua": lower_main_lua.exists(),
        "lowercase_api_lua": lower_api_lua.exists(),
        "legacy_mods_txt": legacy_mods_txt.exists(),
        "legacy_mod_enabled": mods_txt_enabled(legacy_mods_txt),
        "legacy_main_lua": (legacy_mod_dir / "Scripts" / "main.lua").exists(),
        "legacy_api_lua": (legacy_mod_dir / "Scripts" / "ragnacustoms_api.lua").exists(),
    }
    if args.source_root:
        current, mismatches = installed_copy_current(Path(args.source_root).expanduser(), mod_dir)
        checks["installed_current"] = current
        legacy_current, legacy_mismatches = legacy_copy_current(Path(args.source_root).expanduser(), win64)
        checks["legacy_installed_current"] = legacy_current

    for key, value in checks.items():
        print(f"{key}: {'yes' if value else 'no'}")
    print(f"mods_dir: {mods}")
    print(f"active_layout: {'legacy-exe-folder' if mods == legacy_mods_dir(win64) else 'modern-ue4ss-subfolder'}")
    if markers:
        print(f"ue4ss_markers: {', '.join(markers)}")
    if args.source_root and not checks["installed_current"]:
        print(f"installed_mismatches: {', '.join(mismatches)}")
    if args.source_root and not checks["legacy_installed_current"]:
        print(f"legacy_installed_mismatches: {', '.join(legacy_mismatches)}")

    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
