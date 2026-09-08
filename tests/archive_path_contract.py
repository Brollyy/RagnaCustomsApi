from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"
LUA_TEST = Path(__file__).with_suffix(".lua")


def main() -> int:
    lua = shutil.which("lua") or shutil.which("luajit")
    if lua is None:
        print("archive path contract skipped: no Lua interpreter available")
        return 0
    subprocess.run([lua, str(LUA_TEST), str(LIB)], cwd=ROOT, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
