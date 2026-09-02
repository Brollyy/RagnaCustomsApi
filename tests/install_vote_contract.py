from __future__ import annotations

from pathlib import Path
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "Mods" / "RagnaCustomsApi" / "Scripts" / "ragnacustoms_api.lua"


BASE_URL = "https://ragnacustoms.com"
API_BASE_URL = "https://api.ragnacustoms.com"


def join_url(base: str, path: str) -> str:
    if path.startswith("http://") or path.startswith("https://"):
        return path
    return f"{base.rstrip('/')}/{path.lstrip('/')}"


def urls_for(song_or_id) -> dict:
    song_id = song_or_id["id"] if isinstance(song_or_id, dict) else song_or_id
    return {
        "oneClick": f"ragnac://install/{song_id}",
        "zip": join_url(API_BASE_URL, f"/songs/download/{song_id}"),
        "apiDownload": join_url(API_BASE_URL, f"/songs/download/{song_id}"),
        "apiDetail": join_url(API_BASE_URL, f"/api/song/{song_id}"),
        "webZip": join_url(BASE_URL, f"/songs/ddl/{song_id}"),
        "preview": join_url(BASE_URL, f"/song/partial/preview/{song_id}"),
    }


def install_song_one_click(song_or_id) -> dict:
    song_id = song_or_id["id"] if isinstance(song_or_id, dict) else song_or_id
    urls = urls_for(song_or_id)
    return {
        "id": song_id,
        "method": "oneClick",
        "url": urls["oneClick"],
        "openResult": urls["oneClick"],
    }


def download_url(song_id: int, api_key: str | None = None) -> str:
    if api_key:
        return join_url(API_BASE_URL, f"/songs/download/{song_id}/{api_key}")
    return join_url(API_BASE_URL, f"/songs/download/{song_id}")


def vote_request(song_or_id, direction: str, template: str) -> tuple[str, str]:
    song_id = song_or_id["id"] if isinstance(song_or_id, dict) else song_or_id
    clean_direction = direction.lower()
    if clean_direction not in {"up", "down"}:
        raise ValueError("vote direction must be 'up' or 'down'")
    path = template.replace("{id}", str(song_id)).replace("{direction}", clean_direction)
    body = f"songId={quote(str(song_id), safe='')}&direction={quote(clean_direction, safe='')}"
    return join_url(BASE_URL, path), body


def main() -> int:
    urls = urls_for({"id": 6037})
    assert urls["oneClick"] == "ragnac://install/6037"
    assert urls["zip"] == "https://api.ragnacustoms.com/songs/download/6037"
    assert urls["apiDetail"] == "https://api.ragnacustoms.com/api/song/6037"
    assert urls["webZip"] == "https://ragnacustoms.com/songs/ddl/6037"
    assert urls["preview"] == "https://ragnacustoms.com/song/partial/preview/6037"

    one_click = install_song_one_click({"id": 6037})
    assert one_click == {
        "id": 6037,
        "method": "oneClick",
        "url": "ragnac://install/6037",
        "openResult": "ragnac://install/6037",
    }

    assert download_url(6037) == "https://api.ragnacustoms.com/songs/download/6037"
    assert download_url(6037, "secret-key") == "https://api.ragnacustoms.com/songs/download/6037/secret-key"

    vote_url, vote_body = vote_request(6037, "UP", "/vote/{id}/{direction}")
    assert vote_url == "https://ragnacustoms.com/vote/6037/up"
    assert vote_body == "songId=6037&direction=up"

    source = LIB.read_text()
    for expected in [
        "ragnac://install/",
        "/songs/download/",
        "/songs/ddl/",
        "/api/song/",
        "/song/partial/preview/",
        "seed = { id = tonumber(songOrId) }",
        "fetchApiSongs(\"/api/song/\" .. tostring(seed.id))",
        "voteEndpointTemplate is required",
        "vote direction must be 'up' or 'down'",
        "method = \"oneClick\"",
    ]:
        assert expected in source, f"missing install/vote source guard: {expected}"

    print("install/vote contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
