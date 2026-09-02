from __future__ import annotations


def join_list(values: list[str] | None, separator: str = ", ") -> str:
    return separator.join(value.strip() for value in values or [] if value and value.strip())


def format_duration(seconds: int | None) -> str:
    if seconds is None:
        return ""
    minutes, remainder = divmod(int(seconds), 60)
    return f"{minutes}:{remainder:02d}"


def to_ui_song(song: dict, installed_entry: dict | None = None) -> dict:
    artist_text = join_list(song.get("artists"))
    subtitle_parts = []
    if artist_text:
        subtitle_parts.append(artist_text)
    if song.get("mapper"):
        subtitle_parts.append(f"mapped by {song['mapper']}")
    installed = installed_entry is not None if installed_entry is not False else None
    install_text = "Unknown"
    if installed is True:
        install_text = "Installed"
    elif installed is False:
        install_text = "Not installed"
    return {
        "id": song.get("id"),
        "title": song.get("title") or "",
        "subtitle": " - ".join(subtitle_parts),
        "artistText": artist_text,
        "mapperText": f"mapped by {song['mapper']}" if song.get("mapper") else "",
        "difficultyText": ", ".join(str(value) for value in song.get("difficulties", [])),
        "bpmText": f"{song['bpm']} BPM" if song.get("bpm") is not None else "",
        "durationText": format_duration(song.get("durationSeconds")),
        "genreText": join_list(song.get("genres")),
        "voteText": f"{song.get('upvotes') or 0} up / {song.get('downvotes') or 0} down",
        "installed": installed,
        "installedPath": installed_entry.get("path") if installed_entry else None,
        "installText": install_text,
        "oneClickUrl": song.get("oneClickUrl") or f"ragnac://install/{song['id']}",
        "zipUrl": song.get("zipUrl") or f"https://api.ragnacustoms.com/songs/download/{song['id']}",
        "previewUrl": song.get("previewUrl") or f"https://ragnacustoms.com/song/partial/preview/{song['id']}",
        "raw": song,
    }


def search_ui(songs: list[dict]) -> list[dict]:
    return [to_ui_song(song) for song in songs]


def get_song_ui(song: dict) -> dict:
    return to_ui_song(song)


def main() -> int:
    song = {
        "id": 6037,
        "title": "rawdog",
        "artists": ["FLAVOR FOLEY", "Hayden"],
        "mapper": "Brollyy",
        "difficulties": [6],
        "bpm": 140,
        "durationSeconds": 199,
        "genres": ["Electronic", "Vocaloid"],
        "upvotes": 2,
        "downvotes": 0,
        "hash": "e69b89ae229dc60e870810a37e6f01e1",
    }

    ui = to_ui_song(song, {"id": 6037, "path": "/CustomSongs/6037"})
    assert ui["id"] == 6037
    assert ui["title"] == "rawdog"
    assert ui["subtitle"] == "FLAVOR FOLEY, Hayden - mapped by Brollyy"
    assert ui["artistText"] == "FLAVOR FOLEY, Hayden"
    assert ui["mapperText"] == "mapped by Brollyy"
    assert ui["difficultyText"] == "6"
    assert ui["bpmText"] == "140 BPM"
    assert ui["durationText"] == "3:19"
    assert ui["genreText"] == "Electronic, Vocaloid"
    assert ui["voteText"] == "2 up / 0 down"
    assert ui["installed"] is True
    assert ui["installedPath"] == "/CustomSongs/6037"
    assert ui["installText"] == "Installed"
    assert ui["oneClickUrl"] == "ragnac://install/6037"
    assert ui["zipUrl"] == "https://api.ragnacustoms.com/songs/download/6037"
    assert ui["previewUrl"] == "https://ragnacustoms.com/song/partial/preview/6037"
    assert ui["raw"] is song

    unknown = to_ui_song(song, False)
    assert unknown["installed"] is None
    assert unknown["installText"] == "Unknown"

    missing = to_ui_song(song)
    assert missing["installed"] is False
    assert missing["installText"] == "Not installed"

    rows = search_ui([song])
    assert len(rows) == 1
    assert rows[0]["id"] == 6037
    assert rows[0]["title"] == "rawdog"

    detail = get_song_ui(song)
    assert detail["raw"] is song
    assert detail["oneClickUrl"] == "ragnac://install/6037"

    print("ui contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
