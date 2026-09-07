from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"


def capabilities(config: dict) -> dict:
    song_folder = config.get("songFolder") or (
        f"{config['gameDir'].rstrip('/')}/CustomSongs" if config.get("gameDir") else None
    )
    has_song_folder = bool(song_folder)
    has_shell = config.get("allowShell") is True
    has_http_get = callable(config.get("httpGet")) or has_shell
    has_http_request = callable(config.get("httpRequest"))
    has_download = callable(config.get("downloadFile")) or has_shell
    has_unzip = callable(config.get("unzipFile")) or has_shell
    has_list_files = callable(config.get("listFiles")) or has_shell
    vote_configured = config.get("useWanApi") is True and config.get("runtimeWanApi") is True
    return {
        "songFolder": song_folder,
        "canFetch": has_http_get,
        "canSearch": has_http_get,
        "canPreload": has_http_get,
        "canOpenOneClick": callable(config.get("openUrl")),
        "canReturnOneClick": True,
        "canDownloadZip": has_song_folder and has_download,
        "canExtractZip": has_song_folder and has_download and has_unzip,
        "canScanInstalled": has_song_folder and has_list_files,
        "canVote": vote_configured and has_http_request,
        "voteConfigured": vote_configured,
    }


def marker() -> object:
    return object()


def main() -> int:
    default = capabilities({"allowShell": True, "gameDir": "/Game/Ragnarock"})
    assert default["songFolder"] == "/Game/Ragnarock/CustomSongs"
    assert default["canFetch"] is True
    assert default["canSearch"] is True
    assert default["canPreload"] is True
    assert default["canReturnOneClick"] is True
    assert default["canOpenOneClick"] is False
    assert default["canDownloadZip"] is True
    assert default["canExtractZip"] is True
    assert default["canScanInstalled"] is True
    assert default["canVote"] is False

    hooked = capabilities(
        {
            "allowShell": False,
            "songFolder": "C:/Songs",
            "httpGet": marker,
            "httpRequest": marker,
            "downloadFile": marker,
            "unzipFile": marker,
            "listFiles": marker,
            "openUrl": marker,
            "useWanApi": True,
            "runtimeWanApi": True,
        }
    )
    assert hooked["canFetch"] is True
    assert hooked["canOpenOneClick"] is True
    assert hooked["canDownloadZip"] is True
    assert hooked["canExtractZip"] is True
    assert hooked["canScanInstalled"] is True
    assert hooked["canVote"] is True

    implicit = capabilities({"allowShell": False, "httpRequest": marker})
    assert implicit["canVote"] is False

    disabled = capabilities({"allowShell": False})
    assert disabled["canFetch"] is False
    assert disabled["canDownloadZip"] is False
    assert disabled["canScanInstalled"] is False
    assert disabled["canReturnOneClick"] is True

    source = LIB.read_text()
    for expected in [
        "function Api.getCapabilities()",
        "canFetch",
        "canOpenOneClick",
        "canDownloadZip",
        "canScanInstalled",
        "canVote",
    ]:
        assert expected in source, f"missing capability source marker: {expected}"

    print("capabilities contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
