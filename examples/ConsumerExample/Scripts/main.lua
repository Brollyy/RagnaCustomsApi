local MOD_ID = "RagnaCustomsConsumerExample"

local function log(message)
    if print then
        print("[" .. MOD_ID .. "] " .. tostring(message) .. "\n")
    end
end

local function withApi(callback)
    local api = _G.RagnaCustomsApi or _G.RagnaCustoms
    if type(api) ~= "table" then
        log("RagnaCustomsApi is not loaded yet")
        return
    end
    callback(api)
end

withApi(function(api)
    local paths = api.getRuntimePaths()
    local capabilities = api.getCapabilities()
    log("default song folder: " .. tostring(paths.songFolder))
    log("can fetch catalog: " .. tostring(capabilities.canFetch))
    log("can open one-click links: " .. tostring(capabilities.canOpenOneClick))
    log("can download zips: " .. tostring(capabilities.canDownloadZip))

    api.on("ready", function(status)
        log("catalog ready with " .. tostring(status.songCount) .. " cached songs")

        local matches = api.searchCached("Alestorm")
        if #matches > 0 then
            local first = api.toUiSong(matches[1])
            log("first cached match: " .. tostring(first.title) .. " - " .. tostring(first.subtitle))
        end
    end)

    api.on("search.completed", function(payload)
        log("search returned " .. tostring(#payload.songs) .. " songs for " .. tostring(payload.query))
    end)

    local songs, err = api.preloadSongs({ pages = 1 })
    if err then
        log("preload failed: " .. tostring(err))
        return
    end

    log("preload returned " .. tostring(#songs) .. " songs")

    local installed, scanErr = api.scanInstalledSongs()
    if scanErr then
        log("installed song scan failed: " .. tostring(scanErr))
    else
        log("installed song scan found " .. tostring(#installed) .. " folders")
    end

    local matches, searchErr = api.searchUi("rawdog")
    if searchErr or matches == nil or #matches == 0 then
        log("search failed or returned no songs: " .. tostring(searchErr))
        return
    end

    local detail, detailErr = api.getSongUi(matches[1].raw or matches[1], { includeInstalled = true })
    if detailErr then
        log("detail lookup failed: " .. tostring(detailErr))
        return
    end

    local isInstalled, installedEntry = api.isInstalled(detail.raw or detail)
    log("selected song: " .. tostring(detail.title) .. " - " .. tostring(detail.subtitle))
    log("difficulties: " .. tostring(detail.difficultyText))
    log("duration: " .. tostring(detail.durationText))
    log("already installed: " .. tostring(isInstalled))
    if installedEntry ~= nil then
        log("installed path: " .. tostring(installedEntry.path))
    end

    local urls = api.urlsFor(detail.raw or detail)
    log("one-click URL: " .. tostring(detail.oneClickUrl or urls.oneClick))
    log("zip URL: " .. tostring(detail.zipUrl or urls.zip))

    -- UI mods can call this from an explicit user action, such as an Install button.
    -- This sample only logs the URL so loading the example never starts an install by itself.
    log("install button would call api.openOneClick(detail)")
end)
