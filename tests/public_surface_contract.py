from __future__ import annotations

import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"
MANIFEST = ROOT / "docs" / "api_manifest.json"


def main() -> int:
    source = LIB.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    declared = {entry["name"] for entry in manifest["exports"]}
    exported = set(re.findall(r"^function Api\.([A-Za-z0-9_]+)\(", source, re.MULTILINE))

    assert exported == declared, f"public surface mismatch: source={sorted(exported)} manifest={sorted(declared)}"
    assert "discoverScoreEndpoint" not in declared
    assert "deriveVoteEndpoint" not in declared
    assert "redactEndpoint" not in declared
    wanapi = {entry["name"] for entry in manifest["exports"] if entry["category"] == "wanapi"}
    assert wanapi == {"getWanApiVote", "setWanApiVote", "clearWanApiVote"}
    assert "voteEndpointTemplate" not in source
    assert "voteApiKey" not in source
    assert "voteApiBaseUrl" not in source

    print("public surface contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
