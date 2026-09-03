from pathlib import Path
import json
import re
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"
MAIN = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "main.lua"
VOTE_MAIN = ROOT / "Mods" / "RagnaCustomsVote" / "Scripts" / "main.lua"
INSTALLER = ROOT / "scripts" / "install.py"
RMM_INSTALLER = ROOT / "scripts" / "install_rmod.py"
RUNTIME_LOG_CHECKER = ROOT / "scripts" / "check_runtime_log.py"
CHECKER = ROOT / "scripts" / "check_install.py"
PACKAGER = ROOT / "scripts" / "package.py"
VOTE_PACKAGER = ROOT / "scripts" / "package_vote.py"
RELEASE_VERIFIER = ROOT / "scripts" / "verify_release.py"
VOTE_RELEASE_VERIFIER = ROOT / "scripts" / "verify_vote_release.py"
API_PROBE = ROOT / "scripts" / "probe_api.py"
RUN_CHECKS = ROOT / "scripts" / "run_checks.py"
EXAMPLE = ROOT / "examples" / "ConsumerExample" / "Scripts" / "main.lua"
INSTALLED_CONTRACT = ROOT / "tests" / "installed_contract.py"
UI_CONTRACT = ROOT / "tests" / "ui_contract.py"
INSTALL_VOTE_CONTRACT = ROOT / "tests" / "install_vote_contract.py"
CAPABILITIES_CONTRACT = ROOT / "tests" / "capabilities_contract.py"
MANIFEST = ROOT / "docs" / "api_manifest.json"
FORBIDDEN_PACKAGING_NAME = "Ragna" + "Loader"


def main() -> int:
    assert LIB.exists(), f"missing {LIB}"
    assert MAIN.exists(), f"missing {MAIN}"
    assert VOTE_MAIN.exists(), f"missing {VOTE_MAIN}"
    assert INSTALLER.exists(), f"missing {INSTALLER}"
    assert RMM_INSTALLER.exists(), f"missing {RMM_INSTALLER}"
    assert RUNTIME_LOG_CHECKER.exists(), f"missing {RUNTIME_LOG_CHECKER}"
    assert CHECKER.exists(), f"missing {CHECKER}"
    assert PACKAGER.exists(), f"missing {PACKAGER}"
    assert VOTE_PACKAGER.exists(), f"missing {VOTE_PACKAGER}"
    assert RELEASE_VERIFIER.exists(), f"missing {RELEASE_VERIFIER}"
    assert VOTE_RELEASE_VERIFIER.exists(), f"missing {VOTE_RELEASE_VERIFIER}"
    assert API_PROBE.exists(), f"missing {API_PROBE}"
    assert RUN_CHECKS.exists(), f"missing {RUN_CHECKS}"
    assert EXAMPLE.exists(), f"missing {EXAMPLE}"
    assert INSTALLED_CONTRACT.exists(), f"missing {INSTALLED_CONTRACT}"
    assert UI_CONTRACT.exists(), f"missing {UI_CONTRACT}"
    assert INSTALL_VOTE_CONTRACT.exists(), f"missing {INSTALL_VOTE_CONTRACT}"
    assert CAPABILITIES_CONTRACT.exists(), f"missing {CAPABILITIES_CONTRACT}"
    assert MANIFEST.exists(), f"missing {MANIFEST}"

    lib_text = LIB.read_text()
    main_text = MAIN.read_text()
    example_text = EXAMPLE.read_text()
    docs_text = (ROOT / "docs" / "api.md").read_text()
    readme_text = (ROOT / "README.md").read_text()
    manifest = json.loads(MANIFEST.read_text())

    required_exports = [entry["name"] for entry in manifest["exports"]]
    actual_exports = re.findall(r"^function Api\.([A-Za-z0-9_]+)\(", lib_text, flags=re.MULTILINE)
    assert sorted(actual_exports) == sorted(required_exports), (
        f"manifest/API mismatch: actual={sorted(actual_exports)} manifest={sorted(required_exports)}"
    )
    assert manifest["modId"] == "RagnaCustomsApi"
    assert manifest["version"] in lib_text
    assert manifest["globals"] == ["RagnaCustomsApi", "RagnaCustoms"]
    for export in required_exports:
        assert f"function Api.{export}" in lib_text, f"missing Api.{export}"
        assert export in docs_text or export in readme_text, f"missing docs mention for Api.{export}"

    required_events = [
        "runtime.paths",
        "preload.completed",
        "updates.completed",
        "songlist.completed",
        "search.completed",
        "song.completed",
        "install.opened",
        "download.completed",
        "installed.scan.completed",
        "installed.compare.completed",
        "vote.completed",
    ]
    for event_name in required_events:
        assert event_name in docs_text or event_name in readme_text, f"missing docs mention for event {event_name}"

    for expected in [
        "apiBaseUrl",
        "preferApi",
        "/api/search",
        "/api/song",
        "/api/song-list",
        "/songs/download",
    ]:
        assert expected in docs_text or expected in readme_text, f"missing docs mention for {expected}"
    assert "API-first" in readme_text
    assert "scrapes public RagnaCustoms HTML because" not in readme_text

    assert "_G.RagnaCustomsApi" in main_text
    assert "_G.RagnaCustoms" in main_text
    assert "/ue4ss/[Mm]ods/RagnaCustomsApi/[Ss]cripts/main%.lua" in main_text
    assert "/Ragnarock/Binaries/Win64/ue4ss/[Mm]ods/RagnaCustomsApi/[Ss]cripts/main%.lua" in main_text
    assert "RagnaCustomsApi : 1" in INSTALLER.read_text()
    rmm_installer_text = RMM_INSTALLER.read_text()
    assert "inspect" in rmm_installer_text
    assert "import" in rmm_installer_text
    assert "enable" in rmm_installer_text
    assert "deploy" in rmm_installer_text
    assert "read_package_mod_id" in rmm_installer_text
    assert "MOD_ID =" not in rmm_installer_text
    runtime_log_checker_text = RUNTIME_LOG_CHECKER.read_text()
    assert "loaded" in runtime_log_checker_text
    assert "marker_loaded" in runtime_log_checker_text
    assert "MOD_NAME" in runtime_log_checker_text
    assert "RagnaCustomsApi.loaded" in main_text
    checker_text = CHECKER.read_text()
    assert "ue4ss_present" in checker_text
    assert "manager_mods_layout" in checker_text
    assert "ue4ss\" / \"Mods" in checker_text
    assert "legacy_installed_current" in checker_text
    assert "legacy_mod_enabled" in checker_text
    assert "installed_current" in checker_text
    assert "installed_mismatches" in checker_text
    assert "zipfile.ZipFile" in PACKAGER.read_text()
    assert '"ue4ss-lua"' in PACKAGER.read_text()
    assert '"modFolder": MOD_NAME' in PACKAGER.read_text()
    assert '"source": "Scripts/"' in PACKAGER.read_text()
    assert '">=1.1.0"' in PACKAGER.read_text()
    assert '"ragnacustoms-api": ">=0.2.0"' in VOTE_PACKAGER.read_text()
    assert "package_hashes" in RELEASE_VERIFIER.read_text()
    assert "legacy_installed_copy" in RELEASE_VERIFIER.read_text()
    assert "probe_song" in API_PROBE.read_text()
    assert "OFFLINE_TESTS" in RUN_CHECKS.read_text()
    assert "scan_installed_songs" in INSTALLED_CONTRACT.read_text()
    assert "to_ui_song" in UI_CONTRACT.read_text()
    assert "search_ui" in UI_CONTRACT.read_text()
    assert "get_song_ui" in UI_CONTRACT.read_text()
    assert "install_song_one_click" in INSTALL_VOTE_CONTRACT.read_text()
    assert "capabilities(" in CAPABILITIES_CONTRACT.read_text()
    for expected in [
        "getCapabilities",
        "preloadSongs",
        "scanInstalledSongs",
        "search",
        "searchUi",
        "getSong",
        "getSongUi",
        "toUiSong",
        "isInstalled",
        "urlsFor",
        "openOneClick",
    ]:
        assert expected in example_text, f"consumer example does not show {expected}"

    package_path = ROOT / "dist" / "RagnaCustomsApi.rmod"
    if package_path.exists():
        with zipfile.ZipFile(package_path) as archive:
            names = set(archive.namelist())
            package_manifest = json.loads(archive.read("manifest.json"))
        assert "manifest.json" in names
        assert "Scripts/main.lua" in names
        assert "Scripts/ragnacustoms_api.lua" in names
        assert package_manifest["id"] == "ragnacustoms-api"
        assert package_manifest["version"] == "0.2.0"
        assert package_manifest["files"] == [
            {"type": "ue4ss-lua", "source": "Scripts/", "modFolder": "RagnaCustomsApi"}
        ]

    for path in ROOT.rglob("*"):
        if path.is_file() and ".git" not in path.parts:
            assert FORBIDDEN_PACKAGING_NAME not in path.read_text(errors="ignore"), (
                f"unexpected packaging name mention in {path}"
            )

    print("validation ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
