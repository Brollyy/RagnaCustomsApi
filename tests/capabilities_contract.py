from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"


def default_song_folder(game_dir: str) -> str:
    normalized = game_dir.replace("\\", "/").rstrip("/")
    match = re.match(r"^(.*)/steamapps/common/Ragnarock", normalized)
    lower = normalized.lower()
    proton_path = normalized.lower().startswith("z:/") or "/.steam/" in lower or "/compatdata/" in lower
    if match and proton_path:
        return f"{match.group(1)}/steamapps/compatdata/1345820/pfx/drive_c/users/steamuser/Documents/Ragnarock/CustomSongs"
    return f"{normalized}/CustomSongs"


def capabilities(config: dict) -> dict:
    transport = config.get("transport", "varest")
    song_folder = config.get("songFolder") or (default_song_folder(config["gameDir"]) if config.get("gameDir") else None)
    has_song_folder = bool(song_folder)
    has_shell = config.get("allowShell") is True
    has_http_get = callable(config.get("httpGet")) or has_shell
    has_http_post = callable(config.get("httpPost")) or has_shell
    has_http_request = callable(config.get("httpRequest")) or config.get("vaRestAvailable") is True
    has_api_key = bool(config.get("apiKey"))
    has_download = callable(config.get("downloadFile")) or has_shell
    has_unzip = callable(config.get("unzipFile")) or has_shell
    has_list_files = callable(config.get("listFiles")) or has_shell
    return {
        "songFolder": song_folder,
        "transport": transport,
        "canAsyncFetch": transport == "varest" and has_http_request,
        "canFetch": has_http_request if transport == "varest" else has_http_get,
        "canSearch": has_http_request if transport == "varest" else has_http_get,
        "canPreload": has_http_request if transport == "varest" else has_http_get,
        "canOpenOneClick": callable(config.get("openUrl")),
        "canReturnOneClick": True,
        "canDownloadZip": has_song_folder and has_download,
        "canExtractZip": has_song_folder and has_download and has_unzip,
        "canScanInstalled": has_song_folder and has_list_files,
        "canVote": has_api_key and (has_http_request if transport == "varest" else has_http_post),
        "voteConfigured": has_api_key and (has_http_request if transport == "varest" else has_http_post),
    }


def marker() -> object:
    return object()


def main() -> int:
    default = capabilities(
        {
            "gameDir": "/Game/Ragnarock",
            "apiKey": "key",
            "httpRequest": marker,
            "downloadFile": marker,
            "unzipFile": marker,
            "listFiles": marker,
        }
    )
    assert default["transport"] == "varest"
    assert default["canAsyncFetch"] is True
    assert default["songFolder"] == "/Game/Ragnarock/CustomSongs"
    assert default["canFetch"] is True
    assert default["canSearch"] is True
    assert default["canPreload"] is True
    assert default["canReturnOneClick"] is True
    assert default["canOpenOneClick"] is False
    assert default["canDownloadZip"] is True
    assert default["canExtractZip"] is True
    assert default["canScanInstalled"] is True
    assert default["canVote"] is True

    proton = capabilities({"gameDir": "Z:/home/test/.steam/debian-installation/steamapps/common/Ragnarock"})
    assert proton["songFolder"] == "Z:/home/test/.steam/debian-installation/steamapps/compatdata/1345820/pfx/drive_c/users/steamuser/Documents/Ragnarock/CustomSongs"

    hooked = capabilities(
        {
            "allowShell": False,
            "transport": "varest",
            "songFolder": "C:/Songs",
            "httpRequest": marker,
            "apiKey": "key",
            "downloadFile": marker,
            "unzipFile": marker,
            "listFiles": marker,
            "openUrl": marker,
        }
    )
    assert hooked["canFetch"] is True
    assert hooked["canOpenOneClick"] is True
    assert hooked["canDownloadZip"] is True
    assert hooked["canExtractZip"] is True
    assert hooked["canScanInstalled"] is True
    assert hooked["canVote"] is True

    shell = capabilities(
        {
            "allowShell": True,
            "transport": "shell",
            "gameDir": "/Game/Ragnarock",
            "apiKey": "key",
        }
    )
    assert shell["transport"] == "shell"
    assert shell["canAsyncFetch"] is False
    assert shell["canFetch"] is True
    assert shell["canVote"] is True

    implicit = capabilities({"allowShell": False})
    assert implicit["canVote"] is False

    disabled = capabilities({"allowShell": False})
    assert disabled["transport"] == "varest"
    assert disabled["canAsyncFetch"] is False
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
        "SetHeader",
        "requestSerial = 0",
        "httpRequest",
        'transport = "varest"',
        "canAsyncFetch",
        "function vaRestAvailable()",
        "local function defaultSongFolder(gameDir)",
        "compatdata/",
        'RAGNAROCK_APP_ID = "1345820"',
    ]:
        assert expected in source, f"missing capability source marker: {expected}"

    print("capabilities contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
