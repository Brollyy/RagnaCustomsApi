# RagnaCustomsApi

Standalone UE4SS Lua library mod for exposing RagnaCustoms song discovery and install helpers to other Ragnarock mods.

Build a RagnaModManager package:

```bash
python3 scripts/package.py --output dist/RagnaCustomsApi.rmod
python3 scripts/verify_release.py --package dist/RagnaCustomsApi.rmod
```

Install it through RagnaModManager:

```bash
python3 scripts/install_rmod.py \
  --package dist/RagnaCustomsApi.rmod \
  --manager-cli "/path/to/RagnaModManager" \
  --game-dir "/path/to/steamapps/common/Ragnarock"
python3 scripts/check_install.py --game-dir "/path/to/steamapps/common/Ragnarock" --source-root .
```

The `.rmod` archive contains a root `manifest.json`, a small `Manager/` marker declared as `ue4ss-lua` with `modFolder` set to `RagnaCustomsApi`, and explicit manager-deployed compatibility entries for both UE4SS layouts seen locally:

```text
Ragnarock/Binaries/Win64/ue4ss/Mods/RagnaCustomsApi/Scripts/*.lua
Ragnarock/Binaries/Win64/Mods/RagnaCustomsApi/Scripts/*.lua
```

The marker lets RagnaModManager enable the mod in `mods.txt`; the uppercase `Scripts` targets match the folder used by the bundled UE4SS Lua mods. RagnaModManager imports the package into its local library, enables `ragnacustoms-api`, and deploys the Lua files into UE4SS.

Optionally probe the live RagnaCustoms endpoints used by the library:

```bash
python3 scripts/probe_api.py --song-id 6037 --query rawdog
```

Run the full offline verification suite:

```bash
python3 scripts/run_checks.py
```

`scripts/install.py` remains available for manual direct UE4SS installs, but release and deployment verification use the RagnaModManager `.rmod` path.

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

The library prefers the official app API (`https://api.ragnacustoms.com/api/search/<term>`, `https://api.ragnacustoms.com/api/song/<id>`, `https://api.ragnacustoms.com/api/song/check-updates`, and `https://api.ragnacustoms.com/api/song-list/<id>`) and falls back to public web-page parsing where needed.

For display code, `toUiSong(song)` projects normalized song data into UI-ready strings such as `subtitle`, `artistText`, `difficultyText`, `durationText`, `voteText`, `installText`, and resolved install/download URLs. Install state is tri-state, so `installText` is `"Unknown"` until the installed-song cache has been scanned. `toUiSongs(songs)` maps a list through the same projection. `searchUi(query)` and `getSongUi(songOrId)` compose search/detail lookup with that projection for consumer list and detail screens.

Use `getCapabilities()` before rendering consumer UI actions. It reports whether the current configuration can fetch the API, open one-click links, download/extract zips, scan installed songs, or vote.

## Download Folder

RagnaCustoms' FAQ says the PC game reads custom songs from either:

```text
C:\Users\...\Documents\Ragnarock\CustomSongs
...\Steam\steamapps\common\Ragnarock\Ragnarock\CustomSongs
```

Set `songFolder` to the `CustomSongs` directory when using zip downloads. When loaded from UE4SS, the library infers the Steam-install path from `.../Ragnarock/Binaries/Win64/Mods/RagnaCustomsApi/Scripts/main.lua` and defaults to `.../Ragnarock/CustomSongs`. `installSong` uses the RagnaCustoms one-click URL by default. `downloadSong` creates one subfolder per song id, downloads from `https://api.ragnacustoms.com/songs/download/<id>` or `.../<apiKey>`, and extracts it there.

Use `scanInstalledSongs()` to inspect the resolved `CustomSongs` folder. Downloads made through this library write `.id` and `.hash` marker files into each song folder, and the scanner also recognizes existing folders that contain `info.dat` or use a numeric folder name. `getInstalledSong(songOrId)`, `isInstalled(songOrId)`, and `compareInstalledWithUpdates()` expose that local state for consumer UIs.

## Transport Hooks

UE4SS Lua builds differ. The default transport uses shell `curl` and `unzip` through `io.popen`, but callers can inject safer runtime-specific hooks:

```lua
RagnaCustoms.configure({
    allowShell = false,
    httpGet = function(url, config)
        return MyHttpGet(url)
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

`upvote`, `downvote`, and `vote` are exposed, but RagnaCustoms voting is tied to authenticated site/app state and may require a played-song entitlement. Configure the endpoint template and headers/API key for the authenticated environment you are integrating with:

```lua
RagnaCustoms.configure({
    apiKey = "optional-key",
    headers = {
        Cookie = "optional-auth-cookie",
    },
    voteEndpointTemplate = "/your/vote/route/{id}/{direction}",
})

RagnaCustoms.upvote(6037)
RagnaCustoms.downvote(6037)
```

Without `voteEndpointTemplate`, vote calls fail explicitly instead of guessing a private route.

## Notes

The current implementation is API-first for preload, search, details, song lists, update checks, and downloads. Public RagnaCustoms HTML parsing remains as a fallback for list/detail fields that are only available on site pages or when callers force `{ html = true }`. `baseUrl`, `apiBaseUrl`, transport hooks, and vote routes are configurable so consumer mods do not need to change when runtime transport or endpoint details change.
