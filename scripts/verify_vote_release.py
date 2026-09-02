from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Mods" / "RagnaCustomsVote" / "Scripts" / "main.lua"


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify the RagnaCustomsVote managed package.")
    parser.add_argument("--package", default="dist/RagnaCustomsVote.rmod")
    args = parser.parse_args()
    package = Path(args.package)
    if not package.is_absolute():
        package = ROOT / package
    with zipfile.ZipFile(package) as archive:
        assert set(archive.namelist()) == {"manifest.json", "Scripts/main.lua"}
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["id"] == "ragnacustoms-vote"
        assert manifest["version"] == "0.1.0"
        assert manifest["requires"] == {"manager": ">=1.1.0"}
        assert manifest["dependencies"] == {"ragnacustoms-api": ">=0.2.0"}
        assert manifest["files"] == [
            {"type": "ue4ss-lua", "source": "Scripts/", "modFolder": "RagnaCustomsVote"}
        ]
        packaged = archive.read("Scripts/main.lua")
    assert hashlib.sha256(packaged).digest() == hashlib.sha256(SOURCE.read_bytes()).digest()
    print("vote package: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
