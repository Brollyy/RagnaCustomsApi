from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PACKAGE = ROOT / "dist" / "RagnaCustomsApi.rmod"
DEFAULT_MANAGER_CANDIDATES = (
    Path("/home/brollyy/RiderProjects/RagnaModManager/src/ui/RagnaModManager.Cli/bin/Debug/net9.0/RagnaModManager"),
    Path("/home/brollyy/RiderProjects/RagnaModManager/artifacts/RagnaModManager-linux-x64/RagnaModManager"),
)
MOD_ID = "ragnacustoms-api"


def resolve_manager_cli(value: str | None) -> Path:
    if value:
        path = Path(value).expanduser()
        if path.exists():
            return path
        raise SystemExit(f"RagnaModManager CLI does not exist: {path}")

    env_path = os.environ.get("RMM_CLI")
    if env_path:
        return resolve_manager_cli(env_path)

    for candidate in DEFAULT_MANAGER_CANDIDATES:
        if candidate.exists():
            return candidate

    raise SystemExit("Could not find RagnaModManager CLI. Pass --manager-cli or set RMM_CLI.")


def run(manager_cli: Path, args: list[str], data_dir: Path | None) -> None:
    env = os.environ.copy()
    if data_dir is not None:
        env["RMM_DATA_DIR"] = str(data_dir)
    command = [str(manager_cli), *args]
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, env=env, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Install RagnaCustomsApi through RagnaModManager.")
    parser.add_argument("--package", default=str(DEFAULT_PACKAGE), help="Path to RagnaCustomsApi.rmod.")
    parser.add_argument("--manager-cli", default=None, help="Path to the RagnaModManager CLI executable.")
    parser.add_argument("--game-dir", default=None, help="Optional Ragnarock game directory to save before deploy.")
    parser.add_argument(
        "--data-dir",
        default=None,
        help="Optional RagnaModManager data directory. Defaults to the manager's platform app-data path.",
    )
    parser.add_argument("--priority", type=int, default=0, help="Profile priority for the enabled mod.")
    parser.add_argument(
        "--allow-warnings",
        action="store_true",
        help="Allow manager deployment when only non-blocking warnings are present.",
    )
    args = parser.parse_args()

    manager_cli = resolve_manager_cli(args.manager_cli)
    package = Path(args.package).expanduser()
    if not package.is_absolute():
        package = ROOT / package
    if not package.exists():
        raise SystemExit(f"Package does not exist: {package}")

    data_dir = Path(args.data_dir).expanduser() if args.data_dir else None
    if args.game_dir:
        run(manager_cli, ["set-game", args.game_dir], data_dir)
    run(manager_cli, ["inspect", str(package)], data_dir)
    run(manager_cli, ["import", str(package)], data_dir)
    run(manager_cli, ["enable", MOD_ID, "--priority", str(args.priority)], data_dir)

    deploy_args = ["deploy"]
    if args.allow_warnings:
        deploy_args.append("--allow-warnings")
    run(manager_cli, deploy_args, data_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode)
