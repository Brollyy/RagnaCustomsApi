from __future__ import annotations

from pathlib import Path
import tempfile


def scan_installed_songs(root: Path) -> list[dict]:
    by_path: dict[Path, dict] = {}
    for file_path in root.rglob("*"):
        if not file_path.is_file():
            continue
        name = file_path.name.lower()
        if name not in {".id", ".hash", "info.dat"}:
            continue
        entry = by_path.setdefault(file_path.parent, {"path": str(file_path.parent), "metadata": {}})
        if name == ".id":
            raw = file_path.read_text().strip()
            entry["id"] = int(raw) if raw.isdigit() else raw
            entry["metadata"]["idPath"] = str(file_path)
        elif name == ".hash":
            entry["hash"] = file_path.read_text().strip()
            entry["metadata"]["hashPath"] = str(file_path)
        elif name == "info.dat":
            entry["infoDatPath"] = str(file_path)

    songs = []
    for directory, entry in by_path.items():
        if "id" not in entry and directory.name.isdigit():
            entry["id"] = int(directory.name)
        songs.append(entry)
    songs.sort(key=lambda song: str(song.get("id") or song["path"]))
    return songs


def index_installed(songs: list[dict]) -> tuple[dict[str, dict], dict[str, dict]]:
    by_id = {str(song["id"]): song for song in songs if "id" in song}
    by_hash = {song["hash"].lower(): song for song in songs if song.get("hash")}
    return by_id, by_hash


def get_installed_song(song_or_id, by_id: dict[str, dict], by_hash: dict[str, dict]) -> dict | None:
    if isinstance(song_or_id, dict):
        if song_or_id.get("id") is not None and str(song_or_id["id"]) in by_id:
            return by_id[str(song_or_id["id"])]
        if song_or_id.get("hash"):
            return by_hash.get(str(song_or_id["hash"]).lower())
        return None
    if isinstance(song_or_id, int) or str(song_or_id).isdigit():
        return by_id.get(str(int(song_or_id)))
    return by_hash.get(str(song_or_id).lower())


def compare_installed_with_updates(installed: list[dict], updates: list[dict]) -> dict:
    by_id, by_hash = index_installed(installed)
    result = {"missing": [], "changed": [], "unchanged": []}
    for remote in updates:
        local = get_installed_song(remote, by_id, by_hash)
        if local is None:
            result["missing"].append(remote)
        elif remote.get("hash") and local.get("hash") and remote["hash"].lower() != local["hash"].lower():
            result["changed"].append({"remote": remote, "installed": local})
        else:
            result["unchanged"].append({"remote": remote, "installed": local})
    return result


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "CustomSongs"
        installed = root / "6037"
        changed = root / "7000"
        legacy = root / "8123"
        orphan = root / "Song Without Id"
        for folder in [installed, changed, legacy, orphan]:
            folder.mkdir(parents=True)

        (installed / ".id").write_text("6037\n")
        (installed / ".hash").write_text("e69b89ae229dc60e870810a37e6f01e1\n")
        (installed / "info.dat").write_text("{}")

        (changed / ".id").write_text("7000")
        (changed / ".hash").write_text("oldhash")
        (changed / "info.dat").write_text("{}")

        (legacy / "info.dat").write_text("{}")
        (orphan / "info.dat").write_text("{}")

        songs = scan_installed_songs(root)
        by_id, by_hash = index_installed(songs)

        assert by_id["6037"]["hash"] == "e69b89ae229dc60e870810a37e6f01e1"
        assert by_id["6037"]["metadata"]["idPath"].endswith("/6037/.id")
        assert by_id["8123"]["infoDatPath"].endswith("/8123/info.dat")
        assert any("Song Without Id" in song["path"] and "id" not in song for song in songs)

        assert get_installed_song(6037, by_id, by_hash)["id"] == 6037
        assert get_installed_song("E69B89AE229DC60E870810A37E6F01E1", by_id, by_hash)["id"] == 6037
        assert get_installed_song({"id": 9999, "hash": "oldhash"}, by_id, by_hash)["id"] == 7000

        comparison = compare_installed_with_updates(
            songs,
            [
                {"id": 6037, "hash": "e69b89ae229dc60e870810a37e6f01e1"},
                {"id": 7000, "hash": "newhash"},
                {"id": 9999, "hash": "missinghash"},
            ],
        )
        assert [item["id"] for item in comparison["missing"]] == [9999]
        assert [item["remote"]["id"] for item in comparison["changed"]] == [7000]
        assert [item["remote"]["id"] for item in comparison["unchanged"]] == [6037]

    print("installed contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
