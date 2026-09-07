from __future__ import annotations

import argparse
from pathlib import Path


MOD_NAME = "RagnaCustomsApi"
EXPECTED_VERSION = "0.3.0"


def win64_dir(game_dir: Path) -> Path:
    return game_dir / "Ragnarock" / "Binaries" / "Win64"


def default_log_path(game_dir: Path) -> Path:
    win64 = win64_dir(game_dir)
    modern = win64 / "ue4ss" / "UE4SS.log"
    if modern.exists():
        return modern
    return win64 / "UE4SS.log"


def default_marker_paths(game_dir: Path) -> list[Path]:
    win64 = win64_dir(game_dir)
    return [
        win64 / "ue4ss" / "Mods" / MOD_NAME / "Scripts" / f"{MOD_NAME}.loaded",
        win64 / "ue4ss" / "Mods" / MOD_NAME / "scripts" / f"{MOD_NAME}.loaded",
        win64 / "Mods" / MOD_NAME / "Scripts" / f"{MOD_NAME}.loaded",
        win64 / "Mods" / MOD_NAME / "scripts" / f"{MOD_NAME}.loaded",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Check UE4SS.log for RagnaCustomsApi runtime load evidence.")
    parser.add_argument("--game-dir", required=True, help="Path to the Ragnarock game directory.")
    parser.add_argument("--log", default=None, help="Optional explicit UE4SS.log path.")
    parser.add_argument("--marker", default=None, help="Optional explicit RagnaCustomsApi.loaded marker path.")
    parser.add_argument("--version", default=EXPECTED_VERSION, help="Expected RagnaCustomsApi version.")
    parser.add_argument("--lines", type=int, default=200, help="Number of trailing log lines to inspect.")
    args = parser.parse_args()

    log_path = Path(args.log).expanduser() if args.log else default_log_path(Path(args.game_dir).expanduser())
    marker_paths = [Path(args.marker).expanduser()] if args.marker else default_marker_paths(Path(args.game_dir).expanduser())
    expected = f"[{MOD_NAME}] loaded {args.version}"
    expected_marker = f"version={args.version}"

    marker_loaded = False
    existing_marker = next((path for path in marker_paths if path.exists()), None)
    if existing_marker is not None:
        marker_text = existing_marker.read_text(errors="ignore")
        marker_loaded = expected_marker in marker_text
        print("marker_exists: yes")
        print(f"marker_path: {existing_marker}")
        print(f"marker_loaded: {'yes' if marker_loaded else 'no'}")
    else:
        print("marker_exists: no")
        print("marker_paths:")
        for marker_path in marker_paths:
            print(f"- {marker_path}")

    if not log_path.exists():
        print("log_exists: no")
        print(f"log_path: {log_path}")
        return 0 if marker_loaded else 1

    lines = log_path.read_text(errors="ignore").splitlines()
    tail = lines[-args.lines :] if args.lines > 0 else lines
    loaded = any(expected in line for line in tail)
    failed = [line for line in tail if f"[{MOD_NAME}] failed to load library:" in line]

    print("log_exists: yes")
    print(f"log_path: {log_path}")
    print(f"expected_line: {expected}")
    print(f"loaded: {'yes' if loaded else 'no'}")
    if failed:
        print("load_failures:")
        for line in failed[-5:]:
            print(line)

    return 0 if (loaded or marker_loaded) and not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
