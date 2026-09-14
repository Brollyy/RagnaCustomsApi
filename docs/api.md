# API Reference

## Configure

```lua
RagnaCustoms.configure(options)
local config = RagnaCustoms.getConfig()
```

Supported options:

```lua
{
    baseUrl = "https://ragnacustoms.com",
    apiBaseUrl = "https://ragnacustoms.com",
    downloadBaseUrl = "https://api.ragnacustoms.com",
    preferApi = true,
    cacheTtlSeconds = 300,
    maxPreloadPages = 1,
    songFolder = "C:/Users/you/Documents/Ragnarock/CustomSongs",
    downloadSubfolder = nil,
    allowShell = true, -- POSIX fallback only; Windows requires transport hooks
    curlPath = "curl",
    unzipPath = "unzip",
    scriptPath = nil,
    scriptDir = nil,
    win64Dir = nil,
    gameDir = nil,
    apiKey = nil, -- consumer API key sent as X-API-Key for documented API requests
    sensitiveConsent = {
        getCustomApiUrls = false, -- opt in before reading the game's URL configuration
    },
    headers = {},
    gameConfigPath = nil,
    httpGet = nil, -- function(url, config, headers)
    httpPost = nil, -- function(url, body, config, headers)
    httpRequest = nil, -- function(method, url, body, callback, config, headers)
    downloadFile = nil,
    unzipFile = nil,
    openUrl = nil,
    mkdirs = nil,
    listFiles = nil,
    readFile = nil,
    writeFile = nil,
    now = nil,
}
```

`getConfig()` returns a shallow copy of the active configuration table.

Every documented `/api` request requires an API key. The built-in shell and VaRest transports send it as `X-API-Key`; injected transport hooks receive a computed headers table as their final argument and should forward it unchanged.

When `sensitiveConsent.getCustomApiUrls` is true, the library may read the RagnaCustoms key from the game's `GetCustomApiURLs()` value. Consent is disabled by default; an explicit `apiKey` takes precedence and is never exposed by `getConfig()`.

## Status And Events

```lua
local status = RagnaCustoms.getStatus()
local ready = RagnaCustoms.isReady()
local lastError = RagnaCustoms.lastError()
local capabilities = RagnaCustoms.getCapabilities()

local callback = RagnaCustoms.on("ready", function(status)
    print("cached songs: " .. tostring(status.songCount))
end)

RagnaCustoms.off("ready", callback)
```

Event names:

```text
configured
runtime.paths
cache.hit
preload.started
preload.completed
preload.failed
ready
updates.completed
songlist.completed
songlist.failed
search.started
search.completed
search.failed
search.cached
song.started
song.completed
song.failed
install.opened
install.failed
download.completed
download.failed
installed.scan.completed
installed.scan.failed
installed.compare.completed
vote.started
vote.completed
vote.failed
```

`on("*", callback)` receives `{ event = "...", payload = ... }`.

## Capabilities

```lua
local capabilities = RagnaCustoms.getCapabilities()
```

Use this before rendering install/search/vote controls. The result describes current configuration and runtime hooks:

```lua
{
    canFetch = true,
    canSearch = true,
    canPreload = true,
    canOpenOneClick = false,
    canReturnOneClick = true,
    canDownloadZip = true,
    canExtractZip = true,
    canScanInstalled = true,
    canVote = false,
    voteConfigured = false,
    shellAllowed = true,
    songFolder = ".../Ragnarock/CustomSongs",
    transports = {
        httpGet = false,
        openUrl = false,
        downloadFile = false,
        listFiles = false,
    },
}
```

## Runtime Paths

`main.lua` calls `setRuntimePaths` automatically when UE4SS loads the mod. Consumers normally only need the read helpers:

```lua
local paths = RagnaCustoms.getRuntimePaths()
local folder = RagnaCustoms.resolveSongFolder()
```

Manual tests can inject paths directly:

```lua
RagnaCustoms.setRuntimePaths({
    gameDir = "D:/Steam/steamapps/common/Ragnarock/Ragnarock",
    win64Dir = "D:/Steam/steamapps/common/Ragnarock/Ragnarock/Binaries/Win64",
})
```

## Package And Install The Mod

```bash
python3 scripts/package.py --output dist/RagnaCustomsApi.rmod
```

For installation and deployment, see the [RagnaModManager application repository](https://github.com/Brollyy/RagnaModManager).

Use `scripts/probe_api.py` as an optional live network check when you want to verify that the RagnaCustoms endpoints still match the library assumptions:

```bash
python3 scripts/probe_api.py --song-id 6037 --query rawdog
```

## Song Catalog

```lua
local songs = RagnaCustoms.preloadSongs()
local more = RagnaCustoms.preloadSongs({ pages = 5 })
local all = RagnaCustoms.preloadAllSongs(250)
local songs = RagnaCustoms.refreshSongs()
local cached = RagnaCustoms.getCachedSongs()
local updates = RagnaCustoms.checkUpdates()
local playlist = RagnaCustoms.getSongList(42)
```

`preloadSongs` uses the in-memory cache until `cacheTtlSeconds` expires. `refreshSongs` forces a network refresh. `preloadAllSongs(maxPages)` keeps fetching pages until a page returns no songs or `maxPages` is reached.

When `preferApi` is true, preload uses the documented `GET /api/song/check-updates` route from `apiBaseUrl` before falling back to public web pages. The documented API base is `https://ragnacustoms.com/api`.

`checkUpdates()` exposes `GET /api/song/check-updates` directly. `getSongList(listId)` exposes `GET /api/song-list/<id>`.

Catalog endpoints:

```lua
local played = RagnaCustoms.getLastPlayed(10)
local uploaded = RagnaCustoms.getLastUploaded(10)
local rated = RagnaCustoms.getTopRated(10, 30)
local categories = RagnaCustoms.searchCategories("metal")
local mappers = RagnaCustoms.searchMappers("alice")
```

## Search

```lua
local songs = RagnaCustoms.search("artist:Alestorm")
local songs = RagnaCustoms.search("rawdog", { page = 1 })
local cachedMatches = RagnaCustoms.searchCached("Brollyy")
local uiRows = RagnaCustoms.toUiSongs(cachedMatches)
local uiRows = RagnaCustoms.searchUi("rawdog")
```

Search returns normalized lightweight song rows suitable for list UIs. Pass a returned row to `getSong` for detail fields.

When `preferApi` is true, search uses `GET /api/search/<term>` from `apiBaseUrl`; pass `{ html = true }` to force public page parsing.

## UI Projection

```lua
local ui = RagnaCustoms.toUiSong(song)
local ui = RagnaCustoms.toUiSong(song, { includeInstalled = true })
local rows = RagnaCustoms.toUiSongs(songs)
local rows = RagnaCustoms.searchUi("rawdog")
local detail = RagnaCustoms.getSongUi(6037)
```

`toUiSong` does not fetch song details or start installs. It formats an existing normalized song into stable fields for list rows, detail panels, and install buttons. Install state is tri-state: `installed = true`, `false`, or `nil` when no installed-song scan has been run. Pass `includeInstalled = true` to use or populate the installed-song cache, or `scanInstalled = true` to refresh it during projection.

`searchUi(query, options)` is shorthand for `search(query, options)` followed by `toUiSongs`. Pass `{ cached = true }` to use `searchCached` instead. `getSongUi(songOrId, options)` is shorthand for `getSong` followed by `toUiSong`.

Result:

```lua
{
    id = 6037,
    title = "rawdog",
    subtitle = "FLAVOR FOLEY, Hayden - mapped by Brollyy",
    artistText = "FLAVOR FOLEY, Hayden",
    mapperText = "mapped by Brollyy",
    difficultyText = "6",
    bpmText = "140 BPM",
    durationText = "3:19",
    genreText = "Electronic, Vocaloid",
    voteText = "2 up / 0 down",
    installed = false,
    installText = "Not installed", -- "Unknown" before install state has been scanned
    oneClickUrl = "ragnac://install/6037",
    zipUrl = "https://api.ragnacustoms.com/songs/download/6037",
    raw = song,
}
```

## Details

```lua
local detail = RagnaCustoms.getSong(song)
local detail = RagnaCustoms.getSong(6037)
local detail = RagnaCustoms.getSong(song, { refresh = true })
```

When `preferApi` is true, numeric IDs use `GET /api/song/<id>` from `apiBaseUrl`, so `getSong(6037)` can fetch details without a prior search. Pass `{ details = true }` to use `GET /api/song/details/<id>`. Public web detail fallback is slug-based, so if `preferApi` is false, call `search` or `preloadSongs` first or pass a song table with `detailUrl`.

## Downloads

```lua
local folder = RagnaCustoms.resolveSongFolder()
local paths = RagnaCustoms.getRuntimePaths()
local oneClick = RagnaCustoms.installSong(song)
local oneClick = RagnaCustoms.downloadSong(song, { method = "oneClick" })
local result = RagnaCustoms.downloadSong(song)
local result = RagnaCustoms.downloadSong(song, {
    songFolder = "D:/Steam/steamapps/common/Ragnarock/Ragnarock/CustomSongs",
    subfolder = "Requests",
    extract = true,
})
```

By default `installSong` returns or opens the `ragnac://install/<id>` URL. Configure `openUrl` if the UE4SS runtime has a protocol-launch hook. `downloadSong` uses `GET /songs/download/<id>` from `downloadBaseUrl` and sends `X-API-Key` when configured. The key is never placed in the URL.

Result:

```lua
{
    id = 6037,
    zipPath = ".../6037.zip",
    targetDir = ".../CustomSongs/6037",
    extracted = true,
}
```

`openOneClick(song)` returns the `ragnac://install/<id>` URL by default. If configured with `openUrl`, it delegates to that hook.

## Installed Songs

```lua
local installed = RagnaCustoms.scanInstalledSongs()
local entry = RagnaCustoms.getInstalledSong(song)
local ok, entry = RagnaCustoms.isInstalled(song)
local comparison = RagnaCustoms.compareInstalledWithUpdates()
```

`scanInstalledSongs()` reads the resolved `CustomSongs` folder. It indexes folders with `.id`, `.hash`, or `info.dat`, and also infers the id from numeric folder names. `downloadSong()` writes `.id` and `.hash` metadata when the caller passes a song table with those fields.

Installed entry shape:

```lua
{
    id = 6037,
    hash = "e69b89ae229dc60e870810a37e6f01e1",
    path = ".../CustomSongs/6037",
    infoDatPath = ".../CustomSongs/6037/info.dat",
    metadata = {
        idPath = ".../CustomSongs/6037/.id",
        hashPath = ".../CustomSongs/6037/.hash",
    },
}
```

`compareInstalledWithUpdates({ updates = songs })` compares local entries against provided remote rows, or calls `checkUpdates()` when `updates` is omitted. The result has `installed`, `remote`, `missing`, `changed`, and `unchanged` arrays.

## Voting

The documented API voting routes use the caller's API key. Provide an `httpPost` transport when shell fallback is unavailable:

```lua
RagnaCustoms.configure({
    httpPost = MyAuthenticatedPost,
})
RagnaCustoms.upvote(song) -- POST /api/song/<song id>/vote/up
RagnaCustoms.downvote(song) -- POST /api/song/<song id>/vote/down
```

API-key catalog voting and reviews use the documented routes:

```lua
local vote = RagnaCustoms.getSongVote(song)
RagnaCustoms.upvote(song) -- POST /api/song/<id>/vote/up
RagnaCustoms.downvote(song) -- POST /api/song/<id>/vote/down
RagnaCustoms.reviewSong(song, { funFactor = 5, rhythm = 5, patternQuality = 5, readability = 5 })
```

Catalog reads also accept `{ callback = function(result, error) end }` where asynchronous operation is needed; those calls use the configured `httpRequest` hook or built-in VaRest adapter. Arbitrary third-party callouts are not exposed through the public catalog API.
