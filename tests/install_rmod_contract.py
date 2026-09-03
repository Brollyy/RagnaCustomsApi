from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "scripts" / "install_rmod.py"


def load_installer():
    spec = importlib.util.spec_from_file_location("install_rmod", INSTALLER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_package(path: Path, mod_id: str) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("manifest.json", json.dumps({"id": mod_id}))


def main() -> int:
    installer = load_installer()
    with tempfile.TemporaryDirectory(prefix="ragnacustoms-install-contract-") as directory:
        root = Path(directory)
        api = root / "RagnaCustomsApi.rmod"
        vote = root / "RagnaCustomsVote.rmod"
        write_package(api, "ragnacustoms-api")
        write_package(vote, "ragnacustoms-vote")
        assert installer.read_package_mod_id(api) == "ragnacustoms-api"
        assert installer.read_package_mod_id(vote) == "ragnacustoms-vote"
    source = INSTALLER.read_text()
    assert "MOD_ID =" not in source
    assert '["enable", mod_id' in source
    print("managed package installer contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
