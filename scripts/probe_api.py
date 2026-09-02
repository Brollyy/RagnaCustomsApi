from __future__ import annotations

import argparse
import json
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


BASE_URL = "https://ragnacustoms.com"
API_BASE_URL = "https://api.ragnacustoms.com"


def read_url(url: str, timeout: float) -> bytes:
    request = Request(url, headers={"User-Agent": "RagnaCustomsApiProbe/0.1"})
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def head_url(url: str, timeout: float) -> tuple[int, dict[str, str]]:
    request = Request(url, method="HEAD", headers={"User-Agent": "RagnaCustomsApiProbe/0.1"})
    with urlopen(request, timeout=timeout) as response:
        return response.status, dict(response.headers.items())


def get_json(url: str, timeout: float) -> Any:
    return json.loads(read_url(url, timeout).decode("utf-8"))


def assert_song_shape(song: dict[str, Any], expected_id: int) -> None:
    assert song.get("Id") == expected_id, f"expected song Id {expected_id}, got {song.get('Id')}"
    for field in ["Name", "Author", "Mapper", "Difficulties", "Hash", "Ragnabeat"]:
        assert song.get(field), f"missing song field {field}"


def has_field(item: dict[str, Any], *names: str) -> bool:
    return any(item.get(name) not in (None, "") for name in names)


def probe_song(song_id: int, timeout: float) -> None:
    song = get_json(f"{API_BASE_URL}/api/song/{song_id}", timeout)
    assert_song_shape(song, song_id)
    print(f"song: ok ({song.get('Name')})")


def probe_search(query: str, song_id: int, timeout: float) -> None:
    payload = get_json(f"{API_BASE_URL}/api/search/{quote(query)}", timeout)
    results = payload.get("Results")
    assert isinstance(results, list), "search response missing Results list"
    assert any(item.get("Id") == song_id for item in results), f"search results do not include {song_id}"
    print(f"search: ok ({len(results)} results)")


def probe_updates(timeout: float) -> None:
    payload = get_json(f"{API_BASE_URL}/api/song/check-updates", timeout)
    assert isinstance(payload, list), "check-updates response is not a list"
    if payload:
        first = payload[0]
        assert has_field(first, "Id", "id"), "check-updates item missing id"
        assert has_field(first, "Name", "name"), "check-updates item missing name"
        assert has_field(first, "Author", "author"), "check-updates item missing author"
        assert has_field(first, "Mapper", "mapper"), "check-updates item missing mapper"
        assert has_field(first, "Hash", "hash"), "check-updates item missing hash"
    print(f"check-updates: ok ({len(payload)} songs)")


def probe_download(song_id: int, timeout: float) -> None:
    status, headers = head_url(f"{API_BASE_URL}/songs/download/{song_id}", timeout)
    assert 200 <= status < 400, f"download HEAD returned {status}"
    disposition = headers.get("Content-Disposition") or headers.get("content-disposition") or ""
    assert str(song_id) in disposition or disposition == "", (
        f"download Content-Disposition does not reference {song_id}: {disposition}"
    )
    print("download: ok")


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe live RagnaCustoms API endpoints used by the Lua mod.")
    parser.add_argument("--song-id", type=int, default=6037, help="Known song id to probe.")
    parser.add_argument("--query", default="rawdog", help="Search query expected to include --song-id.")
    parser.add_argument("--timeout", type=float, default=10.0, help="Request timeout in seconds.")
    parser.add_argument("--skip-download", action="store_true", help="Skip download HEAD probe.")
    args = parser.parse_args()

    try:
        probe_song(args.song_id, args.timeout)
        probe_search(args.query, args.song_id, args.timeout)
        probe_updates(args.timeout)
        if not args.skip_download:
            probe_download(args.song_id, args.timeout)
    except (AssertionError, HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise SystemExit(f"probe failed: {exc}")

    print("live api probe ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
