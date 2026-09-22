# RagnaCustomsApi

UE4SS Lua library mod for consuming RagnaCustoms API - song catalog, download, voting etc. to simplify development for other Ragnarock mods.

Build the package:

```bash
python3 scripts/package.py --output dist/RagnaCustomsApi.rmod
python3 scripts/verify_release.py --package dist/RagnaCustomsApi.rmod
```

For installation and deployment, see the [RagnaModManager application repository](https://github.com/Brollyy/RagnaModManager).

The `.rmod` is the distributable library package: it contains a root manifest and this mod's `Scripts/` tree. Other `.rmod`-packaged mods can declare it as a runtime dependency.

Optionally probe the live RagnaCustoms endpoints used by the library:

```bash
python3 scripts/probe_api.py --song-id 6037 --query rawdog
```

Run the full offline verification suite:

```bash
python3 scripts/run_checks.py
```

This repository only builds and verifies the `.rmod` package.

## Public Surface

The mod publishes both globals:

```lua
RagnaCustomsApi
RagnaCustoms
```

Main calls:

```lua
RagnaCustoms.on("ready", function(status)
    print("RagnaCustoms catalog ready: " .. tostring(status.songCount))
end)

RagnaCustoms.configure({
    songFolder = "C:/Users/you/Documents/Ragnarock/CustomSongs",
})

local songs = RagnaCustoms.preloadSongs()
local fresh = RagnaCustoms.refreshSongs()
local updates = RagnaCustoms.checkUpdates()
local matches = RagnaCustoms.search("rawdog")
local uiMatches = RagnaCustoms.searchUi("rawdog")
local cachedMatches = RagnaCustoms.searchCached("Brollyy")
local detail = RagnaCustoms.getSong(matches[1])
local uiSong = RagnaCustoms.getSongUi(detail, { includeInstalled = true })
local capabilities = RagnaCustoms.getCapabilities()
local urls = RagnaCustoms.urlsFor(detail)
local installed = RagnaCustoms.installSong(detail)
local localSongs = RagnaCustoms.scanInstalledSongs()
local alreadyInstalled = RagnaCustoms.isInstalled(detail)
local oneClick = RagnaCustoms.openOneClick(detail)
local paths = RagnaCustoms.getRuntimePaths()
```

See [examples/ConsumerExample/Scripts/main.lua](examples/ConsumerExample/Scripts/main.lua) for a minimal consumer mod.

Song objects normalize fields needed by UI mods:

```lua
{
    id = 6037,
    slug = "rawdog",
    title = "rawdog",
    artists = { "FLAVOR FOLEY", "Hayden" },
    mapper = "Brollyy",
    difficulties = { 6 },
    bpm = 140,
    durationSeconds = 199,
    genres = { "Electronic", "Vocaloid" },
    description = "Fun fact: this song is about hot dogs.",
    upvotes = 2,
    downvotes = 0,
    oneClickUrl = "ragnac://install/6037",
    zipUrl = "https://ragnacustoms.com/songs/ddl/6037",
    detailUrl = "https://ragnacustoms.com/song/rawdog",
    coverUrl = "https://ragnacustoms.com/covers/6037.webp",
    previewUrl = "https://ragnacustoms.com/song/partial/preview/6037",
    infoDatUrl = "https://ragnacustoms.com/ragna-beat/.../info.dat",
    hash = "e69b89ae229dc60e870810a37e6f01e1",
    isRanked = false,
    twitchCode = "!rc 6037",
}
```

The library follows the [documented RagnaCustoms catalog API](https://ragnacustoms.com/api/docs) and falls back to public web-page parsing where needed. Catalog requests use `X-API-Key` when `apiKey` is configured.

The UI helpers turn normalized song data into stable display rows. `toUiSong` adds formatted title, artist, difficulty, duration, vote, install-state, and URL fields; `toUiSongs`, `searchUi`, and `getSongUi` apply the same projection to lists and details.

Use `getCapabilities()` before rendering consumer UI actions. It reports whether the current configuration can fetch the API, open one-click links, download/extract zips, scan installed songs, or vote.

## Download Folder

RagnaCustoms' FAQ says the PC game reads custom songs from either:

```text
C:\Users\...\Documents\Ragnarock\CustomSongs
...\Steam\steamapps\common\Ragnarock\Ragnarock\CustomSongs
```

Set `songFolder` to the `CustomSongs` directory when using zip downloads or installed-song scans. The API does not infer that directory from the executable path; runtime integrations should obtain the exact folder from the loaded Song or BeatMap object. `installSong` uses the RagnaCustoms one-click URL by default. `downloadSong` creates one subfolder per song id, downloads from `https://api.ragnacustoms.com/songs/download/<id>` with `X-API-Key` when configured, and extracts it there.

Use `scanInstalledSongs()` to inspect the resolved `CustomSongs` folder. Downloads made through this library write `.id` and `.hash` marker files into each song folder, and the scanner also recognizes existing folders that contain `info.dat` or use a numeric folder name. `getInstalledSong(songOrId)`, `isInstalled(songOrId)`, and `compareInstalledWithUpdates()` expose that local state for consumer UIs.

## Transport Hooks

VaRest is selected by default in-game and delivers catalog results through the existing events. Set `transport = "shell"` to use synchronous shell/custom HTTP hooks.

The library supports these transport hooks:

- `httpGet`: catalog, search, detail, update, and song-list reads.
- `httpPost`: authenticated API voting and review requests.
- `httpRequest`: asynchronous API transport through a consumer hook or Ragnarock's bundled VaRest plugin.
- `downloadFile` and `unzipFile`: song downloads and extraction.
- `mkdirs`, `listFiles`, `readFile`, and `writeFile`: local song-folder discovery and install metadata.
- `openUrl`: optional `ragnac://install/<id>` launching.

Consumers can inject the callback-shaped hooks when shell or VaRest transports are unavailable:

```lua
RagnaCustoms.configure({
    allowShell = false,
    httpGet = function(url, config, headers)
        return MyHttpGet(url)
    end,
    httpRequest = function(method, url, body, callback, config, headers)
        MyAsyncRequest(method, url, body, callback)
        return "request-id"
    end,
    downloadFile = function(url, destination, config)
        return MyDownload(url, destination)
    end,
    unzipFile = function(zipPath, destinationDir, config)
        return MyUnzip(zipPath, destinationDir)
    end,
    mkdirs = function(path, config)
        return MyMkdirs(path)
    end,
    listFiles = function(root, config)
        return MyRecursiveFileList(root)
    end,
    readFile = function(path, config)
        return MyReadFile(path)
    end,
    writeFile = function(path, content, config)
        return MyWriteFile(path, content)
    end,
})
```

## Events And Status

Consumer mods can subscribe to lifecycle and operation events:

```lua
RagnaCustoms.on("ready", function(status) end)
RagnaCustoms.on("preload.completed", function(payload) end)
RagnaCustoms.on("search.completed", function(payload) end)
RagnaCustoms.on("song.completed", function(payload) end)
RagnaCustoms.on("download.completed", function(payload) end)
RagnaCustoms.on("installed.scan.completed", function(payload) end)
RagnaCustoms.on("installed.compare.completed", function(payload) end)
RagnaCustoms.on("vote.completed", function(payload) end)

local status = RagnaCustoms.getStatus()
local paths = RagnaCustoms.getRuntimePaths()
local ready = RagnaCustoms.isReady()
```

Use `RagnaCustoms.on("*", callback)` to observe all events. Use `RagnaCustoms.off(eventName, callback)` to unsubscribe.

## Voting

The documented voting routes take a numeric song id and use the configured consumer API key through `X-API-Key`.

```lua
RagnaCustoms.configure({
    apiKey = "your-consumer-key",
    httpPost = MyAuthenticatedPost,
})
RagnaCustoms.upvote(song)
RagnaCustoms.downvote(song)
```

The asynchronous `httpRequest` hook and built-in VaRest adapter are internal transports for API operations; the public API does not expose arbitrary third-party callouts.

## Notes

The current implementation is API-first for preload, search, details, song lists, update checks, and downloads. Public RagnaCustoms HTML parsing remains as a fallback for list/detail fields that are only available on site pages or when callers force `{ html = true }`. `baseUrl`, `apiBaseUrl`, and transport hooks are configurable.
