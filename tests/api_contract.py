from __future__ import annotations

import json


API_SONG_JSON = """
{
  "Id": 6037,
  "Name": "rawdog",
  "IsRanked": false,
  "Hash": "e69b89ae229dc60e870810a37e6f01e1",
  "Ragnabeat": "/ragna-beat/6a2474753b5ed/info.dat",
  "Author": "FLAVOR FOLEY, Hayden",
  "Mapper": "Brollyy",
  "Difficulties": "6",
  "CoverImageExtension": ".jpg"
}
"""


API_SEARCH_JSON = """
{
  "Results": [
    {
      "Id": 6037,
      "Name": "rawdog",
      "IsRanked": false,
      "Hash": "e69b89ae229dc60e870810a37e6f01e1",
      "Ragnabeat": "/ragna-beat/6a2474753b5ed/info.dat",
      "Author": "FLAVOR FOLEY, Hayden",
      "Mapper": "Brollyy",
      "Difficulties": "6",
      "CoverImageExtension": ".jpg"
    }
  ],
  "Count": 1
}
"""


API_CHECK_UPDATES_JSON = """
[
  {
    "id": 6037,
    "name": "rawdog",
    "author": "FLAVOR FOLEY, Hayden",
    "mapper": "Brollyy",
    "hash": "e69b89ae229dc60e870810a37e6f01e1",
    "Difficulties": "6"
  }
]
"""


def normalize_api_song(raw: dict) -> dict:
    song_id = raw.get("Id") or raw["id"]
    author = raw.get("Author") or raw.get("author") or ""
    ragnabeat = raw.get("Ragnabeat") or raw.get("ragnabeat")
    return {
        "id": song_id,
        "title": raw.get("Name") or raw.get("name"),
        "artists": [part.strip() for part in author.split(",")],
        "author": author,
        "mapper": raw.get("Mapper") or raw.get("mapper"),
        "difficulties": [int(value) for value in raw.get("Difficulties", "").split(",") if value.strip().isdigit()],
        "hash": raw.get("Hash") or raw.get("hash"),
        "isRanked": raw.get("IsRanked"),
        "infoDatUrl": f"https://ragnacustoms.com{ragnabeat}" if ragnabeat else None,
        "oneClickUrl": f"ragnac://install/{song_id}",
        "zipUrl": f"https://api.ragnacustoms.com/songs/download/{song_id}",
        "apiDetailUrl": f"https://api.ragnacustoms.com/api/song/{song_id}",
        "apiDownloadUrl": f"https://api.ragnacustoms.com/songs/download/{song_id}",
        "twitchCode": f"!rc {song_id}",
    }


def main() -> int:
    song = normalize_api_song(json.loads(API_SONG_JSON))
    assert song["id"] == 6037
    assert song["title"] == "rawdog"
    assert song["artists"] == ["FLAVOR FOLEY", "Hayden"]
    assert song["mapper"] == "Brollyy"
    assert song["difficulties"] == [6]
    assert song["hash"] == "e69b89ae229dc60e870810a37e6f01e1"
    assert song["isRanked"] is False
    assert song["infoDatUrl"] == "https://ragnacustoms.com/ragna-beat/6a2474753b5ed/info.dat"
    assert song["zipUrl"] == "https://api.ragnacustoms.com/songs/download/6037"

    search = json.loads(API_SEARCH_JSON)
    results = [normalize_api_song(raw) for raw in search["Results"]]
    assert search["Count"] == 1
    assert results[0] == song

    updates = [normalize_api_song(raw) for raw in json.loads(API_CHECK_UPDATES_JSON)]
    assert updates[0]["id"] == 6037
    assert updates[0]["title"] == "rawdog"
    assert updates[0]["artists"] == ["FLAVOR FOLEY", "Hayden"]
    assert updates[0]["mapper"] == "Brollyy"
    assert updates[0]["difficulties"] == [6]
    assert updates[0]["hash"] == "e69b89ae229dc60e870810a37e6f01e1"
    assert updates[0]["infoDatUrl"] is None

    print("api contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
