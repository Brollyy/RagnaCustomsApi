from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PACKAGE = "dist/RagnaCustomsApi.rmod"
OFFLINE_TESTS = (
    "tests/validate.py",
    "tests/parser_contract.py",
    "tests/api_contract.py",
    "tests/installed_contract.py",
    "tests/ui_contract.py",
    "tests/install_vote_contract.py",
    "tests/install_rmod_contract.py",
    "tests/capabilities_contract.py",
    "tests/vote_endpoint_contract.py",
    "tests/vote_ui_contract.py",
)


def run(command: list[str]) -> None:
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run RagnaCustomsApi verification checks.")
    parser.add_argument(
        "--package",
        default=DEFAULT_PACKAGE,
        help="Package .rmod path to build and verify. Defaults to dist/RagnaCustomsApi.rmod.",
    )
    parser.add_argument(
        "--game-dir",
        default=None,
        help="Optional Ragnarock game directory. Verifies installed copy and install state when set.",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="Also probe live RagnaCustoms API endpoints.",
    )
    parser.add_argument("--song-id", type=int, default=6037, help="Known song id for live probe.")
    parser.add_argument("--query", default="rawdog", help="Search query for live probe.")
    args = parser.parse_args()

    run([sys.executable, "scripts/package.py", "--output", args.package])
    run([sys.executable, "scripts/package_vote.py", "--output", "dist/RagnaCustomsVote.rmod"])

    for test in OFFLINE_TESTS:
        run([sys.executable, test])

    verify_command = [sys.executable, "scripts/verify_release.py", "--package", args.package]
    if args.game_dir:
        verify_command.extend(["--game-dir", args.game_dir])
    run(verify_command)
    run([sys.executable, "scripts/verify_vote_release.py", "--package", "dist/RagnaCustomsVote.rmod"])

    if args.game_dir:
        run([sys.executable, "scripts/check_install.py", "--game-dir", args.game_dir])

    if args.live:
        run([
            sys.executable,
            "scripts/probe_api.py",
            "--song-id",
            str(args.song_id),
            "--query",
            args.query,
        ])

    print("all requested checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
