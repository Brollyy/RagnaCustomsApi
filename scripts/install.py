from __future__ import annotations

import argparse
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MOD = ROOT / "Mods" / "RagnaCustomsApi"


def win64_dir(game_dir: Path) -> Path:
    return game_dir / "Ragnarock" / "Binaries" / "Win64"


def copy_mod(mods_dir: Path, replace: bool) -> None:
    target = mods_dir / "RagnaCustomsApi"
    if target.exists():
        if not replace:
            raise SystemExit(f"{target} already exists; pass --replace to overwrite it")
        shutil.rmtree(target)
    shutil.copytree(SOURCE_MOD, target)


def enable_mod(mods_dir: Path) -> None:
    mods_txt = mods_dir / "mods.txt"
    lines = []
    if mods_txt.exists():
        lines = mods_txt.read_text().splitlines()

    enabled = False
    output = []
    for line in lines:
        if line.strip().startswith("RagnaCustomsApi"):
            output.append("RagnaCustomsApi : 1")
            enabled = True
        else:
            output.append(line)

    if not enabled:
        output.append("RagnaCustomsApi : 1")

    mods_txt.write_text("\n".join(output).rstrip() + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Install the standalone RagnaCustomsApi UE4SS mod.")
    parser.add_argument("--game-dir", required=True, help="Path to the Ragnarock game directory.")
    parser.add_argument("--replace", action="store_true", help="Replace an existing installed copy.")
    args = parser.parse_args()

    game_dir = Path(args.game_dir).expanduser()
    mods_dir = win64_dir(game_dir) / "Mods"
    mods_dir.mkdir(parents=True, exist_ok=True)

    copy_mod(mods_dir, args.replace)
    enable_mod(mods_dir)
    print(f"Installed RagnaCustomsApi into {mods_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
