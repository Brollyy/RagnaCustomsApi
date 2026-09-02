from __future__ import annotations

from html import unescape
import re


BASE_URL = "https://ragnacustoms.com"


LIBRARY_HTML = """
<table>
<tr>
  <td>
    <div class="d-flex">
      <a href="https://ragnacustoms.com/song/rawdog">
        <div class="card-cover"><img src="/covers/6037.webp" class="small-cover" alt="cover"/></div>
      </a>
      <div class="song pl-1">
        <div class="title"><a href="https://ragnacustoms.com/song/rawdog">rawdog <small>E</small></a></div>
        <div class="author">
          <a href="https://ragnacustoms.com/song-library?search=artist%3AFLAVOR%20FOLEY">FLAVOR FOLEY</a>,&nbsp;
          <a href="https://ragnacustoms.com/song-library?search=artist%3AHayden">Hayden</a>
        </div>
        <div class="mapper"><a href="https://ragnacustoms.com/mapper-profile/Brollyy"><span>Brollyy</span></a></div>
      </div>
    </div>
  </td>
  <td><i class="fas fa-vr-cardboard"></i><i class="fas fa-gamepad"></i></td>
  <td>
    <div class="level-list">
      <div class='level' style="background-color:#9a426d;"><span>6</span></div>
    </div>
  </td>
  <td>140</td>
  <td class="small-col"><div class="up_down_vote" id="up_down_vote_6037">
    <i class="fas fa-arrow-up"></i> 2
    <i class="fas fa-arrow-down"></i> 0
  </div></td>
  <td>0 (0)</td>
  <td>4d ago&nbsp;</td>
  <td>31</td>
  <td class="download">
    <a href="ragnac://install/6037" class="one-click"></a>
    <a href="https://ragnacustoms.com/songs/ddl/6037" class="ddl"></a>
  </td>
</tr>
</table>
"""


DETAIL_HTML = """
<div id="song_detail">
  <img src="/covers/6037.webp" class="img-fluid" alt="rawdog"/>
  <div class="level-list">
    <div class='level ' style="background-color:#9a426d;"><span>6</span></div>
  </div>
  <div class="pt-1 community-level-list">
    <a class='level btn'><span>6</span></a>
  </div>
  <div><i class="fas fa-clock"></i> 3:19</div>
  <div><i class="fas fa-drum"></i> 140</div>
  <a data-no-swup="true" href="ragnac://install/6037" class="btn">1 click</a>
  <a data-no-swup="true" href="https://ragnacustoms.com/songs/ddl/6037" title="4.63 Mo">Zip</a>
  <h1 class="force-default text-warning">rawdog <small>E</small></h1>
  <h2><div class="author">
    <a href="https://ragnacustoms.com/song-library?search=artist%3AFLAVOR%20FOLEY">FLAVOR FOLEY</a>,&nbsp;
    <a href="https://ragnacustoms.com/song-library?search=artist%3AHayden">Hayden</a>
  </div></h2>
  <div class="tags">
    <a class='btn btn-sm btn-tag' href="https://ragnacustoms.com/song-library?search=genre:Electronic">Electronic</a>
    <a class='btn btn-sm btn-tag' href="https://ragnacustoms.com/song-library?search=genre:Vocaloid">Vocaloid</a>
  </div>
  <div class="up_down_vote" id="up_down_vote_6037">
    <i class="fas fa-arrow-up"></i> 2
    <i class="fas fa-arrow-down"></i> 0
  </div>
  <div class="label">Mapped by</div>
  <div class="mapper"><a href="https://ragnacustoms.com/mapper-profile/Brollyy"><span>Brollyy</span></a></div>
  <div class="label">Description</div>
  <div class="description"><p>Fun fact: this song is about hot dogs.</p></div>
  <div id="ragna_6037_detail" data-file="/ragna-beat/6a2474753b5ed/info.dat"></div>
</div>
"""


def strip_tags(value: str) -> str:
    return re.sub(r"\s+", " ", unescape(re.sub(r"<[^>]*>", " ", value))).strip()


def join_url(path: str | None) -> str | None:
    if not path:
        return None
    if path.startswith("http://") or path.startswith("https://"):
        return path
    return f"{BASE_URL}/{path.lstrip('/')}"


def parse_levels(fragment: str) -> list[int]:
    levels = [int(value) for value in re.findall(r"<div class=['\"]level[^>]*>.*?<span>(\d+)</span>", fragment, re.S)]
    return levels or [int(value) for value in re.findall(r"<span>(\d+)</span>", fragment)]


def parse_votes(fragment: str) -> tuple[int, int]:
    match = re.search(r"</i>\s*(\d+)\s*<i[^>]*fa-arrow-down[^>]*>\s*</i>\s*(\d+)", fragment, re.S)
    if not match:
        return 0, 0
    return int(match.group(1)), int(match.group(2))


def list_from_anchors(fragment: str) -> list[str]:
    values = [strip_tags(value) for value in re.findall(r"<a[^>]*>(.*?)</a>", fragment, re.S)]
    return [value for value in values if value]


def parse_library(html: str) -> list[dict]:
    songs = []
    for row in re.findall(r"<tr>(.*?)</tr>", html, re.S):
        id_match = re.search(r"ragnac://install/(\d+)|/songs/ddl/(\d+)", row)
        if not id_match:
            continue
        song_id = int(next(group for group in id_match.groups() if group))
        title_block = re.search(r'<div class="title">(.*?)</div>', row, re.S).group(1)
        slug, title = re.search(r'href="https://ragnacustoms\.com/song/([^"]+)">(.*?)</a>', title_block, re.S).groups()
        author_block = re.search(r'<div class="author">(.*?)</div>', row, re.S).group(1)
        mapper_block = re.search(r'<div class="mapper">(.*?)</div>', row, re.S).group(1)
        level_block = re.search(r'<div class="level-list">(.*?)</td>', row, re.S).group(1)
        vote_block = re.search(r'<div class="up_down_vote".*?</div>', row, re.S).group(0)
        upvotes, downvotes = parse_votes(vote_block)
        songs.append(
            {
                "id": song_id,
                "slug": slug,
                "title": strip_tags(title),
                "artists": list_from_anchors(author_block),
                "mapper": strip_tags(mapper_block),
                "difficulties": parse_levels(level_block),
                "bpm": int(re.search(r'</td>\s*<td>\s*(\d+)\s*</td>', row, re.S).group(1)),
                "upvotes": upvotes,
                "downvotes": downvotes,
                "oneClickUrl": f"ragnac://install/{song_id}",
                "zipUrl": f"{BASE_URL}/songs/ddl/{song_id}",
                "detailUrl": f"{BASE_URL}/song/{slug}",
                "coverUrl": join_url(re.search(r'src="([^"]*/covers/\d+\.webp[^"]*)"', row).group(1)),
                "twitchCode": f"!rc {song_id}",
            }
        )
    return songs


def parse_duration(value: str | None) -> int | None:
    if not value:
        return None
    minutes, seconds = value.split(":")
    return int(minutes) * 60 + int(seconds)


def parse_detail(html: str, seed: dict) -> dict:
    song_id = int(re.search(r"ragnac://install/(\d+)|/songs/ddl/(\d+)", html).group(1))
    upvotes, downvotes = parse_votes(re.search(r'<div class="up_down_vote".*?</div>', html, re.S).group(0))
    result = dict(seed)
    result.update(
        {
            "id": song_id,
            "title": strip_tags(re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S).group(1)),
            "artists": list_from_anchors(re.search(r"<h2[^>]*>(.*?)</h2>", html, re.S).group(1)),
            "mapper": strip_tags(
                re.search(r'<div class="label">Mapped by</div>\s*<div class="mapper">(.*?)</div>', html, re.S).group(1)
            ),
            "description": strip_tags(
                re.search(r'<div class="label">Description</div>\s*<div class="description">(.*?)</div>', html, re.S).group(1)
            ),
            "coverUrl": join_url(re.search(r'src="([^"]*/covers/\d+\.webp[^"]*)"', html).group(1)),
            "durationSeconds": parse_duration(re.search(r'<i class="fas fa-clock"></i>\s*([\d:]+)', html).group(1)),
            "bpm": int(re.search(r'<i class="fas fa-drum"></i>\s*(\d+)', html).group(1)),
            "difficulties": parse_levels(re.search(r'<div class="level-list">(.*?)</div>', html, re.S).group(1)),
            "genres": [
                strip_tags(value)
                for value in re.findall(r'href="https://ragnacustoms\.com/song-library\?search=genre:[^"]+">(.*?)</a>', html)
            ],
            "upvotes": upvotes,
            "downvotes": downvotes,
            "infoDatUrl": join_url(re.search(r'data-file="([^"]+)"', html).group(1)),
            "previewUrl": f"{BASE_URL}/song/partial/preview/{song_id}",
        }
    )
    return result


def main() -> int:
    song = parse_library(LIBRARY_HTML)[0]
    assert song["id"] == 6037
    assert song["slug"] == "rawdog"
    assert song["title"] == "rawdog E"
    assert song["artists"] == ["FLAVOR FOLEY", "Hayden"]
    assert song["mapper"] == "Brollyy"
    assert song["difficulties"] == [6]
    assert song["bpm"] == 140
    assert song["upvotes"] == 2
    assert song["downvotes"] == 0
    assert song["oneClickUrl"] == "ragnac://install/6037"
    assert song["zipUrl"] == "https://ragnacustoms.com/songs/ddl/6037"
    assert song["coverUrl"] == "https://ragnacustoms.com/covers/6037.webp"

    detail = parse_detail(DETAIL_HTML, song)
    assert detail["durationSeconds"] == 199
    assert detail["genres"] == ["Electronic", "Vocaloid"]
    assert detail["description"] == "Fun fact: this song is about hot dogs."
    assert detail["infoDatUrl"] == "https://ragnacustoms.com/ragna-beat/6a2474753b5ed/info.dat"
    assert detail["previewUrl"] == "https://ragnacustoms.com/song/partial/preview/6037"

    print("parser contract ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
