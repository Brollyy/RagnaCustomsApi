local Api = {
    VERSION = "0.2.1",
}

local state = {
    config = {
        baseUrl = "https://ragnacustoms.com",
        apiBaseUrl = "https://api.ragnacustoms.com",
        preferApi = true,
        cacheTtlSeconds = 300,
        maxPreloadPages = 1,
        songFolder = nil,
        downloadSubfolder = nil,
        allowShell = true,
        curlPath = "curl",
        unzipPath = "unzip",
        scriptPath = nil,
        scriptDir = nil,
        win64Dir = nil,
        gameDir = nil,
        apiKey = nil,
        headers = {},
        useWanApi = false,
        gameConfigPath = nil,
        httpRequest = nil,
        httpGet = nil,
        httpPost = nil,
        downloadFile = nil,
        unzipFile = nil,
        openUrl = nil,
        mkdirs = nil,
        listFiles = nil,
        readFile = nil,
        writeFile = nil,
        now = nil,
    },
    cache = {
        songs = nil,
        songsAt = 0,
        byId = {},
        bySlug = {},
    },
    installed = {
        songs = nil,
        scannedAt = nil,
        root = nil,
        byId = {},
        byHash = {},
    },
    subscribers = {},
    activeRequests = {},
    voteGenerations = {},
    requestSerial = 0,
    status = {
        ready = false,
        loading = false,
        lastRefreshAt = nil,
        songCount = 0,
    },
    lastError = nil,
}

local function setError(message)
    state.lastError = tostring(message)
    return nil, state.lastError
end

local function now()
    if type(state.config.now) == "function" then
        return state.config.now()
    end
    if os and os.time then
        return os.time()
    end
    return 0
end

local function safeCall(callback, payload)
    local ok, err = pcall(callback, payload)
    if not ok then
        state.lastError = "event subscriber failed: " .. tostring(err)
    end
end

local function emit(eventName, payload)
    local eventSubscribers = state.subscribers[eventName]
    if type(eventSubscribers) == "table" then
        for _, callback in ipairs(eventSubscribers) do
            safeCall(callback, payload)
        end
    end

    local allSubscribers = state.subscribers["*"]
    if type(allSubscribers) == "table" then
        local wrapped = {
            event = eventName,
            payload = payload,
        }
        for _, callback in ipairs(allSubscribers) do
            safeCall(callback, wrapped)
        end
    end
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeSpace(value)
    return trim(tostring(value or ""):gsub("%s+", " "))
end

local function htmlDecode(value)
    local text = tostring(value or "")
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&#039;", "'")
    text = text:gsub("&#39;", "'")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&#(%d+);", function(code)
        local number = tonumber(code)
        if number == nil or number < 0 or number > 255 then
            return ""
        end
        return string.char(number)
    end)
    return text
end

local function stripTags(value)
    return normalizeSpace(htmlDecode(tostring(value or ""):gsub("<[^>]->", " ")))
end

local function shellQuote(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function shellFallbackAvailable()
    if state.config.allowShell ~= true then
        return false
    end
    if package ~= nil and type(package.config) == "string" then
        return package.config:sub(1, 1) ~= "\\"
    end
    return false
end

local function archivePathIsSafe(entry)
    local path = tostring(entry or ""):gsub("\\", "/")
    if path == "" or path:find("%z", 1, true) ~= nil then
        return false
    end
    if path:match("^/") or path:match("^//") or path:match("^%a:/") then
        return false
    end
    for component in path:gmatch("[^/]+") do
        if component == ".." then
            return false
        end
    end
    return true
end

local function joinUrl(base, path)
    if tostring(path or ""):match("^https?://") then
        return path
    end
    return tostring(base or ""):gsub("/+$", "") .. "/" .. tostring(path or ""):gsub("^/+", "")
end

local function joinPath(left, right)
    local l = tostring(left or ""):gsub("\\", "/"):gsub("/+$", "")
    local r = tostring(right or ""):gsub("\\", "/"):gsub("^/+", "")
    if l == "" then
        return r
    end
    if r == "" then
        return l
    end
    return l .. "/" .. r
end

local function parentPath(path)
    local clean = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
    return clean:match("^(.*)/[^/]+$") or ""
end

local function baseName(path)
    return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or tostring(path or "")
end

local function urlEncode(value)
    return tostring(value or ""):gsub("\n", "\r\n"):gsub("([^%w%-%_%.%~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function jsonDecodeString(value)
    local text = tostring(value or "")
    text = text:gsub("\\/", "/")
    text = text:gsub('\\"', '"')
    text = text:gsub("\\\\", "\\")
    text = text:gsub("\\n", "\n")
    text = text:gsub("\\r", "\r")
    text = text:gsub("\\t", "\t")
    return text
end

local function jsonStringField(objectText, name)
    local value = tostring(objectText or ""):match('"' .. name .. '"%s*:%s*"(.-)"')
    if value == nil then
        return nil
    end
    return jsonDecodeString(value)
end

local function jsonNumberField(objectText, name)
    return tonumber(tostring(objectText or ""):match('"' .. name .. '"%s*:%s*(-?%d+%.?%d*)'))
end

local function jsonBooleanField(objectText, name)
    local value = tostring(objectText or ""):match('"' .. name .. '"%s*:%s*(true)')
        or tostring(objectText or ""):match('"' .. name .. '"%s*:%s*(false)')
    if value == "true" then
        return true
    end
    if value == "false" then
        return false
    end
    return nil
end

local function jsonStringAny(objectText, names)
    for _, name in ipairs(names) do
        local value = jsonStringField(objectText, name)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function jsonNumberAny(objectText, names)
    for _, name in ipairs(names) do
        local value = jsonNumberField(objectText, name)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function jsonBooleanAny(objectText, names)
    for _, name in ipairs(names) do
        local value = jsonBooleanField(objectText, name)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function jsonEscape(value)
    return tostring(value or "")
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
end

local function unwrapRemoteValue(value)
    if value ~= nil and type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" then
        local hasGetter, getter = pcall(function()
            return value.get
        end)
        if hasGetter and type(getter) == "function" then
            local ok, unwrapped = pcall(function()
                return value:get()
            end)
            if ok and unwrapped ~= nil then
                return unwrapped
            end
        end
    end
    return value
end

local function redactEndpoint(value)
    local endpoint = tostring(value or "")
    return endpoint:gsub("(/wanapi/score/)[^/%?#]+", "%1[redacted]")
end

local function deriveVoteEndpoint(scoreEndpoint)
    local endpoint = trim(scoreEndpoint)
    local scheme, host, path = endpoint:match("^(https?)://([^/%?#]+)([^%?#]*)/*$")
    if scheme == nil or host == nil or path == nil then
        return nil, "configured custom leaderboard endpoint is not a valid HTTP URL"
    end
    local hostOnly = host:match("^%[([^%]]+)%]") or host:match("^([^:]+)") or host
    if scheme == "http" and hostOnly ~= "127.0.0.1" and hostOnly ~= "localhost" and hostOnly ~= "::1" then
        return nil, "unencrypted custom leaderboard endpoints are allowed only on loopback"
    end
    if path:match("^/wanapi/score/[^/]+/?$") == nil then
        return nil, "configured custom leaderboard endpoint must end with /wanapi/score/{apiKey}"
    end
    return endpoint:gsub("/+$", "") .. "/vote", nil
end

local function parseVoteResponse(content)
    local text = tostring(content or "")
    local errorCode = jsonStringField(text, "error")
    if errorCode ~= nil then
        return nil, {
            code = errorCode,
            message = jsonStringField(text, "message") or "vote request failed",
        }
    end
    local upvotes = jsonNumberField(text, "upvotes")
    local downvotes = jsonNumberField(text, "downvotes")
    if upvotes == nil or downvotes == nil then
        return nil, { code = "invalid_response", message = "vote response is missing counts" }
    end
    local currentVote = jsonStringField(text, "currentVote")
    if currentVote ~= nil and currentVote ~= "up" and currentVote ~= "down" then
        return nil, { code = "invalid_response", message = "vote response contains an invalid selection" }
    end
    return {
        songId = jsonNumberField(text, "songId"),
        beatmap = jsonStringField(text, "beatmap"),
        currentVote = currentVote,
        upvotes = upvotes,
        downvotes = downvotes,
    }, nil
end

local function splitCsv(value)
    local result = {}
    for part in tostring(value or ""):gmatch("[^,]+") do
        local clean = trim(part)
        if clean ~= "" then
            table.insert(result, clean)
        end
    end
    return result
end

local function splitDifficulties(value)
    local result = {}
    for difficulty in tostring(value or ""):gmatch("%d+") do
        table.insert(result, tonumber(difficulty))
    end
    return result
end

local function joinList(values, separator)
    local parts = {}
    for _, value in ipairs(values or {}) do
        local clean = trim(value)
        if clean ~= "" then
            table.insert(parts, clean)
        end
    end
    return table.concat(parts, separator or ", ")
end

local function formatDuration(seconds)
    local total = tonumber(seconds)
    if total == nil then
        return nil
    end
    total = math.floor(total)
    local minutes = math.floor(total / 60)
    local remainder = total % 60
    return string.format("%d:%02d", minutes, remainder)
end

local function formatNumbers(values, separator)
    local parts = {}
    for _, value in ipairs(values or {}) do
        table.insert(parts, tostring(value))
    end
    return table.concat(parts, separator or ", ")
end

local function readPipe(command)
    if not shellFallbackAvailable() then
        return setError("POSIX shell transport is disabled or unavailable; provide a transport hook")
    end
    if io == nil or type(io.popen) ~= "function" then
        return setError("io.popen is unavailable and no transport hook was provided")
    end
    local handle = io.popen(command)
    if handle == nil then
        return setError("failed to start command: " .. command)
    end
    local output = handle:read("*a")
    local ok = handle:close()
    if ok == false then
        return setError("command failed: " .. command)
    end
    return output or ""
end

local function defaultListFiles(root)
    if not shellFallbackAvailable() then
        return setError("POSIX file listing is disabled or unavailable; provide a listFiles hook")
    end
    local quoted = shellQuote(root)
    local command = string.format("if [ -d %s ]; then find %s -maxdepth 4 -type f; fi", quoted, quoted)
    local output, err = readPipe(command)
    if err then
        return nil, err
    end
    local files = {}
    for line in tostring(output or ""):gmatch("[^\r\n]+") do
        table.insert(files, line)
    end
    return files
end

local function listFiles(root)
    if type(state.config.listFiles) == "function" then
        return state.config.listFiles(root, state.config)
    end
    return defaultListFiles(root)
end

local function defaultReadFile(path)
    if io == nil or type(io.open) ~= "function" then
        return setError("io.open is unavailable and no readFile hook was provided")
    end
    local handle, err = io.open(path, "rb")
    if handle == nil then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content or ""
end

local function readTextFile(path)
    if type(state.config.readFile) == "function" then
        return state.config.readFile(path, state.config)
    end
    return defaultReadFile(path)
end

local function defaultWriteFile(path, content)
    if io == nil or type(io.open) ~= "function" then
        return setError("io.open is unavailable and no writeFile hook was provided")
    end
    local handle, err = io.open(path, "wb")
    if handle == nil then
        return nil, err
    end
    handle:write(tostring(content or ""))
    handle:close()
    return path
end

local function writeTextFile(path, content)
    if type(state.config.writeFile) == "function" then
        return state.config.writeFile(path, content, state.config)
    end
    return defaultWriteFile(path, content)
end

local function defaultHttpGet(url)
    local headerArgs = ""
    for name, value in pairs(state.config.headers or {}) do
        headerArgs = headerArgs .. " -H " .. shellQuote(tostring(name) .. ": " .. tostring(value))
    end
    if state.config.apiKey ~= nil then
        headerArgs = headerArgs .. " -H " .. shellQuote("X-API-Key: " .. tostring(state.config.apiKey))
    end
    local command = string.format("%s -fsSL%s %s", shellQuote(state.config.curlPath), headerArgs, shellQuote(url))
    return readPipe(command)
end

local function defaultHttpPost(url, body)
    local headerArgs = " -H " .. shellQuote("Content-Type: application/x-www-form-urlencoded")
    for name, value in pairs(state.config.headers or {}) do
        headerArgs = headerArgs .. " -H " .. shellQuote(tostring(name) .. ": " .. tostring(value))
    end
    if state.config.apiKey ~= nil then
        headerArgs = headerArgs .. " -H " .. shellQuote("X-API-Key: " .. tostring(state.config.apiKey))
    end
    local command = string.format(
        "%s -fsSL -X POST%s --data %s %s",
        shellQuote(state.config.curlPath),
        headerArgs,
        shellQuote(body or ""),
        shellQuote(url)
    )
    return readPipe(command)
end

local function defaultDownloadFile(url, destination)
    if not shellFallbackAvailable() then
        return setError("POSIX shell download is disabled or unavailable; provide a downloadFile hook")
    end
    local command = string.format(
        "%s -fL --create-dirs -o %s %s",
        shellQuote(state.config.curlPath),
        shellQuote(destination),
        shellQuote(url)
    )
    local _, err = readPipe(command)
    if err then
        return nil, err
    end
    return destination
end

local function validateArchive(zipPath)
    local listing, err = readPipe(string.format(
        "%s -Z1 %s",
        shellQuote(state.config.unzipPath),
        shellQuote(zipPath)
    ))
    if err then
        return nil, err
    end
    for entry in tostring(listing or ""):gmatch("[^\r\n]+") do
        if not archivePathIsSafe(entry) then
            return nil, "archive contains an unsafe member path: " .. entry
        end
        local metadata, metadataError = readPipe(string.format(
            "%s -Z -v %s %s",
            shellQuote(state.config.unzipPath),
            shellQuote(zipPath),
            shellQuote(entry)
        ))
        if metadataError then
            return nil, metadataError
        end
        local mode = tostring(metadata or ""):match("Unix file attributes %((%d+) octal%)")
        if mode ~= nil then
            local fileType = math.floor(tonumber(mode, 8) / 4096)
            if fileType ~= 0 and fileType ~= 4 and fileType ~= 8 then
                return nil, "archive contains a special-file member: " .. entry
            end
        end
    end
    return true
end

local function defaultUnzipFile(zipPath, destinationDir)
    if not shellFallbackAvailable() then
        return setError("POSIX shell unzip is disabled or unavailable; provide a safe unzipFile hook")
    end
    local validArchive, validationError = validateArchive(zipPath)
    if not validArchive then
        return nil, validationError
    end
    local command = string.format(
        "%s -o %s -d %s",
        shellQuote(state.config.unzipPath),
        shellQuote(zipPath),
        shellQuote(destinationDir)
    )
    local _, err = readPipe(command)
    if err then
        return nil, err
    end
    return destinationDir
end

local function httpGet(url)
    if type(state.config.httpGet) == "function" then
        return state.config.httpGet(url, state.config)
    end
    return defaultHttpGet(url)
end

local function httpPost(url, body)
    if type(state.config.httpPost) == "function" then
        return state.config.httpPost(url, body, state.config)
    end
    return defaultHttpPost(url, body)
end

local function safeObjectCall(callback, fallback)
    local ok, result = pcall(callback)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

local function constructVaRestRequest()
    if type(StaticFindObject) ~= "function" or type(StaticConstructObject) ~= "function" then
        return nil, "VaRest construction is unavailable"
    end
    local subsystem = nil
    if type(FindFirstOf) == "function" then
        subsystem = safeObjectCall(function()
            return FindFirstOf("VaRestSubsystem")
        end, nil)
    end
    if subsystem ~= nil then
        local managedRequest = safeObjectCall(function()
            return subsystem:ConstructVaRestRequest()
        end, nil)
        if managedRequest ~= nil then
            return managedRequest, nil
        end
    end
    local class = safeObjectCall(function()
        return StaticFindObject("/Script/VaRest.VaRestRequestJSON")
    end, nil)
    if class == nil then
        return nil, "VaRest request class is unavailable"
    end
    local outer = subsystem
    local request = safeObjectCall(function()
        return StaticConstructObject(class, outer, 0, 0, 0, nil, false, false, nil)
    end, nil)
    if request == nil then
        return nil, "VaRest request construction failed"
    end
    return request, nil
end

local function defaultHttpRequest(method, url, body, callback)
    print("[RagnaCustomsApi] vote transport stage=construct method=" .. tostring(method) .. "\n")
    local request, constructError = constructVaRestRequest()
    if request == nil then
        callback(nil, { code = "transport_unavailable", message = constructError })
        return nil
    end

    state.requestSerial = state.requestSerial + 1
    local requestId = state.requestSerial
    state.activeRequests[requestId] = request
    local configured, configuredError = pcall(function()
        request:SetVerb(method == "GET" and 0 or 2)
        request:SetContentType(2)
        if method ~= "GET" then
            local requestObject = unwrapRemoteValue(request:GetRequestObject())
            requestObject:DecodeJson(body or "{}", true)
        end
        request:ProcessURL(url)
    end)
    if not configured then
        print("[RagnaCustomsApi] vote transport stage=failed error=" .. tostring(configuredError) .. "\n")
        state.activeRequests[requestId] = nil
        callback(nil, { code = "transport_start_failed", message = "VaRest could not start the request" })
        return nil
    end

    local attempts = 0
    local function poll()
        attempts = attempts + 1
        local responseCode = safeObjectCall(function()
            return tonumber(unwrapRemoteValue(request:GetResponseCode()))
        end, 0)
        local status = safeObjectCall(function()
            return tonumber(unwrapRemoteValue(request:GetStatus()))
        end, 1)
        if responseCode > 0 then
            local content = safeObjectCall(function()
                request:GetResponseContentAsString(true)
                return request.ResponseContent:ToString()
            end, "")
            print("[RagnaCustomsApi] vote transport stage=complete code=" .. tostring(responseCode)
                .. " bytes=" .. tostring(#tostring(content)) .. "\n")
            state.activeRequests[requestId] = nil
            callback({ status = responseCode, body = content }, nil)
            return
        end
        if attempts >= 300 then
            print("[RagnaCustomsApi] vote transport stage=timeout status=" .. tostring(status) .. "\n")
            state.activeRequests[requestId] = nil
            callback(nil, {
                code = "timeout",
                message = "vote request timed out",
            })
            return
        end
        ExecuteWithDelay(100, poll)
    end

    if type(ExecuteWithDelay) ~= "function" then
        state.activeRequests[requestId] = nil
        callback(nil, { code = "scheduler_unavailable", message = "UE4SS delayed execution is unavailable" })
        return nil
    end
    ExecuteWithDelay(100, poll)
    return requestId
end

local function httpRequest(method, url, body, callback)
    if type(state.config.httpRequest) == "function" then
        return state.config.httpRequest(method, url, body, callback, state.config)
    end
    return defaultHttpRequest(method, url, body, callback)
end

local function listFromAnchors(fragment)
    local result = {}
    for label in tostring(fragment or ""):gmatch("<a[^>]*>(.-)</a>") do
        local clean = stripTags(label)
        if clean ~= "" then
            table.insert(result, clean)
        end
    end
    if #result == 0 then
        local clean = stripTags(fragment)
        if clean ~= "" then
            table.insert(result, clean)
        end
    end
    return result
end

local function parseLevels(fragment)
    local levels = {}
    for level in tostring(fragment or ""):gmatch("<div class=['\"]level[^>]-.-<span>(%d+)</span>") do
        table.insert(levels, tonumber(level))
    end
    if #levels > 0 then
        return levels
    end
    for level in tostring(fragment or ""):gmatch("<span>(%d+)</span>") do
        table.insert(levels, tonumber(level))
    end
    return levels
end

local function parseVotes(fragment)
    local up, down = tostring(fragment or ""):match("</i>%s*(%d+)%s*<i[^>]-fa%-arrow%-down[^>]->%s*</i>%s*(%d+)")
    return tonumber(up) or 0, tonumber(down) or 0
end

local function extractFirst(fragment, pattern)
    return tostring(fragment or ""):match(pattern)
end

local function parseSongRow(row)
    local id = tonumber(row:match("ragnac://install/(%d+)") or row:match("/songs/ddl/(%d+)") or row:match("data%-song%-id=['\"](%d+)['\"]"))
    if id == nil then
        return nil
    end

    local titleBlock = extractFirst(row, '<div class="title">(.-)</div>') or row
    local slug, titleHtml = titleBlock:match('href="https://ragnacustoms%.com/song/([^"]+)">(.-)</a>')
    if slug == nil then
        slug, titleHtml = titleBlock:match('href="/song/([^"]+)">(.-)</a>')
    end

    local authorBlock = extractFirst(row, '<div class="author">(.-)</div>') or ""
    local mapperBlock = extractFirst(row, '<div class="mapper">(.-)</div>') or ""
    local levelBlock = extractFirst(row, '<div class="level%-list">(.-)</td>') or row
    local voteBlock = extractFirst(row, '<div class="up_down_vote".-</div>') or ""
    local upvotes, downvotes = parseVotes(voteBlock)
    local cover = row:match('src="([^"]-/covers/%d+%.webp[^"]*)"') or row:match('src="(/covers/%d+%.webp[^"]*)"')

    local bpm = nil
    local afterLevels = row:match('<div class="level%-list">.-</div>%s*</td>%s*<td>%s*(%d+)%s*</td>')
    if afterLevels then
        bpm = tonumber(afterLevels)
    end

    local installText = "Unknown"
    if installed == true then
        installText = "Installed"
    elseif installed == false then
        installText = "Not installed"
    end

    return {
        id = id,
        slug = slug,
        title = stripTags(titleHtml or ""),
        artists = listFromAnchors(authorBlock),
        mapper = stripTags(mapperBlock),
        difficulties = parseLevels(levelBlock),
        bpm = bpm,
        upvotes = upvotes,
        downvotes = downvotes,
        oneClickUrl = "ragnac://install/" .. tostring(id),
        zipUrl = joinUrl(state.config.baseUrl, "/songs/ddl/" .. tostring(id)),
        detailUrl = slug and joinUrl(state.config.baseUrl, "/song/" .. slug) or nil,
        coverUrl = cover and joinUrl(state.config.baseUrl, cover) or nil,
        twitchCode = "!rc " .. tostring(id),
    }
end

local function parseLibrary(html)
    local songs = {}
    for row in tostring(html or ""):gmatch("<tr>(.-)</tr>") do
        local song = parseSongRow(row)
        if song ~= nil then
            table.insert(songs, song)
        end
    end
    return songs
end

local function parseApiSongObject(objectText)
    local id = jsonNumberAny(objectText, { "Id", "id" })
    if id == nil then
        return nil
    end

    local author = jsonStringAny(objectText, { "Author", "author" })
    local ragnabeat = jsonStringAny(objectText, { "Ragnabeat", "ragnabeat" })
    return {
        id = id,
        title = jsonStringAny(objectText, { "Name", "name" }) or "",
        artists = splitCsv(author),
        author = author,
        mapper = jsonStringAny(objectText, { "Mapper", "mapper" }) or "",
        difficulties = splitDifficulties(jsonStringAny(objectText, { "Difficulties", "difficulties" })),
        hash = jsonStringAny(objectText, { "Hash", "hash" }),
        isRanked = jsonBooleanAny(objectText, { "IsRanked", "isRanked", "is_ranked" }),
        ragnabeat = ragnabeat,
        infoDatUrl = ragnabeat and joinUrl(state.config.baseUrl, ragnabeat) or nil,
        oneClickUrl = "ragnac://install/" .. tostring(id),
        zipUrl = joinUrl(state.config.apiBaseUrl, "/songs/download/" .. tostring(id)),
        apiDetailUrl = joinUrl(state.config.apiBaseUrl, "/api/song/" .. tostring(id)),
        apiDownloadUrl = joinUrl(state.config.apiBaseUrl, "/songs/download/" .. tostring(id)),
        coverImageExtension = jsonStringAny(objectText, { "CoverImageExtension", "coverImageExtension", "cover_image_extension" }),
        twitchCode = "!rc " .. tostring(id),
    }
end

local function parseApiSongs(json)
    local songs = {}
    for objectText in tostring(json or ""):gmatch("{[^{}]-}") do
        local song = parseApiSongObject(objectText)
        if song ~= nil then
            table.insert(songs, song)
        end
    end
    return songs
end

local function fetchApiSongs(path)
    local json, err = httpGet(joinUrl(state.config.apiBaseUrl, path))
    if err then
        return nil, err
    end
    return parseApiSongs(json)
end

local function appendSongs(target, source)
    for _, song in ipairs(source or {}) do
        table.insert(target, song)
    end
    return target
end

local function libraryUrl(query, page)
    local params = {}
    if query ~= nil and query ~= "" then
        table.insert(params, "search=" .. urlEncode(query))
    end
    if page ~= nil then
        table.insert(params, "ppage1=" .. tostring(page))
    end
    local path = "/song-library"
    if #params > 0 then
        path = path .. "?" .. table.concat(params, "&")
    end
    return joinUrl(state.config.baseUrl, path)
end

local function fetchLibraryPage(query, page)
    local html, err = httpGet(libraryUrl(query, page))
    if err then
        return nil, err
    end
    return parseLibrary(html)
end

local function containsText(value, needle)
    return string.find(string.lower(tostring(value or "")), needle, 1, true) ~= nil
end

local function songMatches(song, query)
    local needle = string.lower(trim(query or ""))
    if needle == "" then
        return true
    end
    if containsText(song.title, needle) or containsText(song.mapper, needle) or containsText(song.slug, needle) then
        return true
    end
    for _, artist in ipairs(song.artists or {}) do
        if containsText(artist, needle) then
            return true
        end
    end
    for _, genre in ipairs(song.genres or {}) do
        if containsText(genre, needle) then
            return true
        end
    end
    return false
end

local function mergeSong(base, detail)
    local merged = {}
    for key, value in pairs(base or {}) do
        merged[key] = value
    end
    for key, value in pairs(detail or {}) do
        if value ~= nil then
            merged[key] = value
        end
    end
    return merged
end

local function parseDuration(text)
    local minutes, seconds = tostring(text or ""):match("(%d+):(%d+)")
    if minutes == nil then
        return nil
    end
    return tonumber(minutes) * 60 + tonumber(seconds)
end

local function parseSongDetail(html, seed)
    local source = tostring(html or "")
    local id = tonumber(source:match("ragnac://install/(%d+)") or source:match("/songs/ddl/(%d+)") or (seed and seed.id))
    local detail = {
        id = id,
    }

    detail.title = stripTags(source:match("<h1[^>]->(.-)</h1>") or "")
    local artistBlock = source:match("<h2[^>]->%s*(.-)%s*</h2>") or ""
    detail.artists = listFromAnchors(artistBlock)
    detail.mapper = stripTags(source:match('<div class="label">Mapped by</div>%s*<div class="mapper">(.-)</div>') or "")
    detail.description = stripTags(source:match('<div class="label">Description</div>%s*<div class="description">(.-)</div>') or "")
    detail.coverUrl = joinUrl(state.config.baseUrl, source:match('src="([^"]-/covers/%d+%.webp[^"]*)"') or source:match('src="(/covers/%d+%.webp[^"]*)"') or "")
    if detail.coverUrl == state.config.baseUrl .. "/" then
        detail.coverUrl = nil
    end
    detail.zipUrl = id and joinUrl(state.config.baseUrl, "/songs/ddl/" .. tostring(id)) or nil
    detail.oneClickUrl = id and ("ragnac://install/" .. tostring(id)) or nil
    detail.twitchCode = id and ("!rc " .. tostring(id)) or nil
    detail.durationSeconds = parseDuration(source:match('<i class="fas fa%-clock"></i>%s*([%d:]+)'))
    detail.bpm = tonumber(source:match('<i class="fas fa%-drum"></i>%s*(%d+)'))
    detail.infoDatUrl = joinUrl(state.config.baseUrl, source:match('data%-file="([^"]+)"') or "")
    if detail.infoDatUrl == state.config.baseUrl .. "/" then
        detail.infoDatUrl = nil
    end
    detail.previewUrl = id and joinUrl(state.config.baseUrl, "/song/partial/preview/" .. tostring(id)) or nil

    local levelBlock = source:match('<div class="level%-list">(.-)</div>') or ""
    detail.difficulties = parseLevels(levelBlock)

    local genres = {}
    for genre in source:gmatch('href="https://ragnacustoms%.com/song%-library%?search=genre:[^"]+">(.-)</a>') do
        table.insert(genres, stripTags(genre))
    end
    detail.genres = genres

    local upvotes, downvotes = parseVotes(source:match('<div class="up_down_vote".-</div>') or "")
    detail.upvotes = upvotes
    detail.downvotes = downvotes

    return mergeSong(seed or {}, detail)
end

local function rememberSongs(songs)
    for _, song in ipairs(songs or {}) do
        if song.id ~= nil then
            state.cache.byId[tostring(song.id)] = song
        end
        if song.slug ~= nil then
            state.cache.bySlug[tostring(song.slug)] = song
        end
    end
    state.status.songCount = #(state.cache.songs or {})
end

local function rememberInstalled(songs, root)
    state.installed.songs = songs or {}
    state.installed.scannedAt = now()
    state.installed.root = root
    state.installed.byId = {}
    state.installed.byHash = {}
    for _, song in ipairs(state.installed.songs) do
        if song.id ~= nil then
            state.installed.byId[tostring(song.id)] = song
        end
        if song.hash ~= nil and song.hash ~= "" then
            state.installed.byHash[string.lower(tostring(song.hash))] = song
        end
    end
end

local function readTrimmed(path)
    local content = readTextFile(path)
    if content == nil then
        return nil
    end
    return trim(content)
end

local function recordInstalledMetadata(targetDir, songOrId)
    local id = type(songOrId) == "table" and songOrId.id or songOrId
    local hash = type(songOrId) == "table" and songOrId.hash or nil
    if targetDir == nil or targetDir == "" or id == nil then
        return
    end
    writeTextFile(joinPath(targetDir, ".id"), tostring(id))
    if hash ~= nil and hash ~= "" then
        writeTextFile(joinPath(targetDir, ".hash"), tostring(hash))
    end
end

local function scoreEndpointFromRuntime()
    if type(FindFirstOf) ~= "function" then
        return nil
    end
    for _, className in ipairs({ "RagnarockGameInstance", "BP_RagnarockGameInstance_C", "GameInstance" }) do
        local instance = safeObjectCall(function()
            return FindFirstOf(className)
        end, nil)
        if instance ~= nil then
            local urls = safeObjectCall(function()
                return instance:GetCustomApiURLs()
            end, nil)
            if type(urls) == "table" then
                for _, value in pairs(urls) do
                    local endpoint = tostring(unwrapRemoteValue(value) or "")
                    if deriveVoteEndpoint(endpoint) ~= nil then
                        return endpoint
                    end
                end
            end
        end
    end
    return nil
end

local function scoreEndpointFromConfig()
    local candidates = {}
    if state.config.gameConfigPath ~= nil and state.config.gameConfigPath ~= "" then
        table.insert(candidates, state.config.gameConfigPath)
    end
    if os ~= nil and type(os.getenv) == "function" then
        local localAppData = os.getenv("LOCALAPPDATA")
        if localAppData ~= nil and localAppData ~= "" then
            table.insert(candidates, joinPath(localAppData, "Ragnarock/Saved/Config/WindowsNoEditor/Game.ini"))
        end
    end
    for _, path in ipairs(candidates) do
        local content = readTextFile(path)
        if content ~= nil then
            for endpoint in tostring(content):gmatch('CustomApiURLs%s*=%s*"([^"]+)"') do
                if deriveVoteEndpoint(endpoint) ~= nil then
                    return endpoint
                end
            end
        end
    end
    return nil
end

function Api.configure(options)
    for key, value in pairs(options or {}) do
        state.config[key] = value
    end
    emit("configured", Api.getStatus())
    return Api
end

function Api.getConfig()
    local copy = {}
    for key, value in pairs(state.config) do
        if key ~= "apiKey" then
            copy[key] = value
        end
    end
    return copy
end

local function discoverWanApiScoreEndpoint()
    if state.config.useWanApi ~= true then
        return setError("WanApi voting is opt-in; configure useWanApi=true")
    end
    local endpoint = scoreEndpointFromRuntime() or scoreEndpointFromConfig()
    if endpoint == nil then
        return setError("configured custom leaderboard score endpoint was not found")
    end
    emit("vote.endpoint.discovered", { endpoint = redactEndpoint(endpoint) })
    return endpoint
end

function Api.setRuntimePaths(paths)
    paths = paths or {}
    for _, key in ipairs({ "scriptPath", "scriptDir", "win64Dir", "gameDir" }) do
        if paths[key] ~= nil then
            state.config[key] = paths[key]
        end
    end

    if (state.config.songFolder == nil or state.config.songFolder == "") and state.config.gameDir ~= nil then
        state.config.songFolder = joinPath(state.config.gameDir, "CustomSongs")
    end

    emit("runtime.paths", Api.getRuntimePaths())
    return Api.getRuntimePaths()
end

function Api.getRuntimePaths()
    return {
        scriptPath = state.config.scriptPath,
        scriptDir = state.config.scriptDir,
        win64Dir = state.config.win64Dir,
        gameDir = state.config.gameDir,
        songFolder = state.config.songFolder,
    }
end

function Api.resolveSongFolder()
    if state.config.songFolder ~= nil and state.config.songFolder ~= "" then
        return state.config.songFolder
    end
    if state.config.gameDir ~= nil and state.config.gameDir ~= "" then
        return joinPath(state.config.gameDir, "CustomSongs")
    end
    return nil
end

function Api.lastError()
    return state.lastError
end

function Api.getCapabilities()
    local songFolder = Api.resolveSongFolder()
    local hasSongFolder = songFolder ~= nil and songFolder ~= ""
    local hasShell = shellFallbackAvailable()
    local hasHttpGet = type(state.config.httpGet) == "function" or hasShell
    local hasHttpPost = type(state.config.httpPost) == "function" or hasShell
    local hasHttpRequest = type(state.config.httpRequest) == "function"
        or (type(StaticFindObject) == "function" and type(StaticConstructObject) == "function" and type(ExecuteWithDelay) == "function")
    local hasDownload = type(state.config.downloadFile) == "function" or hasShell
    local hasUnzip = type(state.config.unzipFile) == "function" or hasShell
    local hasListFiles = type(state.config.listFiles) == "function" or hasShell
    local hasOpenUrl = type(state.config.openUrl) == "function"
    local scoreEndpoint = nil
    if state.config.useWanApi == true then
        scoreEndpoint = scoreEndpointFromRuntime() or scoreEndpointFromConfig()
    end
    local canWanApiVote = scoreEndpoint ~= nil and deriveVoteEndpoint(scoreEndpoint) ~= nil and hasHttpRequest
    local canAuthenticatedVote = type(state.config.httpPost) == "function"

    return {
        version = Api.VERSION,
        baseUrl = state.config.baseUrl,
        apiBaseUrl = state.config.apiBaseUrl,
        preferApi = state.config.preferApi,
        songFolder = songFolder,
        shellAllowed = hasShell,
        transports = {
            httpGet = type(state.config.httpGet) == "function",
            httpPost = type(state.config.httpPost) == "function",
            httpRequest = type(state.config.httpRequest) == "function",
            downloadFile = type(state.config.downloadFile) == "function",
            unzipFile = type(state.config.unzipFile) == "function",
            openUrl = hasOpenUrl,
            mkdirs = type(state.config.mkdirs) == "function",
            listFiles = type(state.config.listFiles) == "function",
            readFile = type(state.config.readFile) == "function",
            writeFile = type(state.config.writeFile) == "function",
        },
        canFetch = hasHttpGet,
        canSearch = hasHttpGet,
        canPreload = hasHttpGet,
        canOpenOneClick = hasOpenUrl,
        canReturnOneClick = true,
        canDownloadZip = hasSongFolder and hasDownload,
        canExtractZip = hasSongFolder and hasDownload and hasUnzip,
        canScanInstalled = hasSongFolder and hasListFiles,
        canWriteInstallMetadata = hasSongFolder and (type(state.config.writeFile) == "function" or io ~= nil),
        canVote = canAuthenticatedVote or canWanApiVote,
        voteConfigured = canAuthenticatedVote or canWanApiVote,
        canAuthenticatedVote = canAuthenticatedVote,
        canWanApiVote = canWanApiVote,
        scoreEndpoint = scoreEndpoint and redactEndpoint(scoreEndpoint) or nil,
        voteMode = state.config.useWanApi == true and "wanapi" or "authenticated",
    }
end

function Api.getStatus()
    return {
        ready = state.status.ready,
        loading = state.status.loading,
        lastRefreshAt = state.status.lastRefreshAt,
        songCount = state.status.songCount,
        lastError = state.lastError,
        version = Api.VERSION,
    }
end

function Api.isReady()
    return state.status.ready
end

function Api.on(eventName, callback)
    if type(callback) ~= "function" then
        return setError("event callback must be a function")
    end
    local key = tostring(eventName or "")
    if key == "" then
        return setError("event name is required")
    end
    if state.subscribers[key] == nil then
        state.subscribers[key] = {}
    end
    table.insert(state.subscribers[key], callback)
    if key == "ready" and state.status.ready then
        safeCall(callback, Api.getStatus())
    end
    return callback
end

function Api.off(eventName, callback)
    local key = tostring(eventName or "")
    local callbacks = state.subscribers[key]
    if type(callbacks) ~= "table" then
        return false
    end
    for index = #callbacks, 1, -1 do
        if callbacks[index] == callback then
            table.remove(callbacks, index)
            return true
        end
    end
    return false
end

function Api.urlsFor(songOrId)
    local id = type(songOrId) == "table" and songOrId.id or songOrId
    if id == nil then
        return nil
    end
    return {
        oneClick = "ragnac://install/" .. tostring(id),
        zip = joinUrl(state.config.apiBaseUrl, "/songs/download/" .. tostring(id)),
        apiDownload = joinUrl(state.config.apiBaseUrl, "/songs/download/" .. tostring(id)),
        apiDetail = joinUrl(state.config.apiBaseUrl, "/api/song/" .. tostring(id)),
        webZip = joinUrl(state.config.baseUrl, "/songs/ddl/" .. tostring(id)),
        preview = joinUrl(state.config.baseUrl, "/song/partial/preview/" .. tostring(id)),
    }
end

function Api.preloadSongs(options)
    options = options or {}
    local age = now() - (state.cache.songsAt or 0)
    if not options.force and state.cache.songs ~= nil and age >= 0 and age < state.config.cacheTtlSeconds then
        emit("cache.hit", {
            songs = state.cache.songs,
            status = Api.getStatus(),
        })
        return state.cache.songs
    end

    state.status.loading = true
    emit("preload.started", Api.getStatus())

    local pageCount = tonumber(options.pages or options.maxPages or state.config.maxPreloadPages) or 1
    if pageCount < 1 then
        pageCount = 1
    end
    local songs = nil
    if state.config.preferApi then
        local apiSongs, apiErr = fetchApiSongs("/api/song/check-updates")
        if apiSongs ~= nil and #apiSongs > 0 then
            songs = apiSongs
        elseif apiErr ~= nil then
            state.lastError = apiErr
        end
    end

    if songs == nil then
        songs = {}
        for page = 1, pageCount do
            local pageSongs, err = fetchLibraryPage(nil, page)
            if err then
                state.status.loading = false
                emit("preload.failed", {
                    error = err,
                    status = Api.getStatus(),
                })
                return nil, err
            end
            if #pageSongs == 0 then
                break
            end
            appendSongs(songs, pageSongs)
        end
    end
    state.cache.songs = songs
    state.cache.songsAt = now()
    state.status.ready = true
    state.status.loading = false
    state.status.lastRefreshAt = state.cache.songsAt
    rememberSongs(songs)
    emit("preload.completed", {
        songs = songs,
        status = Api.getStatus(),
    })
    emit("ready", Api.getStatus())
    return songs
end

function Api.refreshSongs()
    return Api.preloadSongs({ force = true })
end

function Api.preloadAllSongs(maxPages)
    return Api.preloadSongs({ force = true, pages = maxPages or 9999 })
end

function Api.checkUpdates()
    local songs, err = fetchApiSongs("/api/song/check-updates")
    if err then
        return nil, err
    end
    rememberSongs(songs)
    emit("updates.completed", {
        songs = songs,
    })
    return songs
end

function Api.getSongList(listId)
    if listId == nil or tostring(listId) == "" then
        return setError("song list id is required")
    end
    local songs, err = fetchApiSongs("/api/song-list/" .. urlEncode(listId))
    if err then
        emit("songlist.failed", {
            id = listId,
            error = err,
        })
        return nil, err
    end
    rememberSongs(songs)
    emit("songlist.completed", {
        id = listId,
        songs = songs,
    })
    return songs
end

function Api.search(query, options)
    options = options or {}
    local page = tonumber(options.page or 1) or 1
    emit("search.started", {
        query = query or "",
        page = page,
    })
    local songs, err = nil, nil
    if state.config.preferApi and not options.html then
        songs, err = fetchApiSongs("/api/search/" .. urlEncode(query or ""))
    end
    if songs == nil then
        songs, err = fetchLibraryPage(query or "", page)
    end
    if err then
        emit("search.failed", {
            query = query or "",
            page = page,
            error = err,
        })
        return nil, err
    end
    rememberSongs(songs)
    emit("search.completed", {
        query = query or "",
        page = page,
        songs = songs,
    })
    return songs
end

function Api.searchCached(query)
    local matches = {}
    for _, song in ipairs(state.cache.songs or {}) do
        if songMatches(song, query) then
            table.insert(matches, song)
        end
    end
    emit("search.cached", {
        query = query or "",
        songs = matches,
    })
    return matches
end

function Api.getCachedSongs()
    return state.cache.songs or {}
end

function Api.toUiSong(songOrId, options)
    options = options or {}
    local song = songOrId
    if type(songOrId) ~= "table" then
        song = state.cache.byId[tostring(songOrId)] or state.cache.bySlug[tostring(songOrId)]
    end
    if type(song) ~= "table" then
        return setError("song is required")
    end

    local artists = song.artists or splitCsv(song.author)
    local artistText = joinList(artists)
    local difficultyText = formatNumbers(song.difficulties)
    local durationText = formatDuration(song.durationSeconds)
    local urls = Api.urlsFor(song) or {}
    local installed = nil
    local installedEntry = nil
    if options.includeInstalled or options.scanInstalled or options.refreshInstalled then
        installed, installedEntry = Api.isInstalled(song, {
            refresh = options.scanInstalled or options.refreshInstalled,
            songFolder = options.songFolder,
        })
        if installed == nil and installedEntry ~= nil then
            return nil, installedEntry
        end
    elseif state.installed.songs ~= nil then
        installedEntry = Api.getInstalledSong(song)
        installed = installedEntry ~= nil
    end

    local subtitleParts = {}
    if artistText ~= "" then
        table.insert(subtitleParts, artistText)
    end
    if song.mapper ~= nil and song.mapper ~= "" then
        table.insert(subtitleParts, "mapped by " .. tostring(song.mapper))
    end

    return {
        id = song.id,
        title = song.title or "",
        subtitle = table.concat(subtitleParts, " - "),
        artists = artists,
        artistText = artistText,
        mapper = song.mapper,
        mapperText = song.mapper ~= nil and ("mapped by " .. tostring(song.mapper)) or "",
        difficulties = song.difficulties or {},
        difficultyText = difficultyText,
        bpm = song.bpm,
        bpmText = song.bpm ~= nil and (tostring(song.bpm) .. " BPM") or "",
        durationSeconds = song.durationSeconds,
        durationText = durationText or "",
        genres = song.genres or {},
        genreText = joinList(song.genres),
        description = song.description,
        upvotes = song.upvotes or 0,
        downvotes = song.downvotes or 0,
        voteText = tostring(song.upvotes or 0) .. " up / " .. tostring(song.downvotes or 0) .. " down",
        isRanked = song.isRanked,
        hash = song.hash,
        installed = installed,
        installedPath = installedEntry and installedEntry.path or nil,
        installText = installText,
        oneClickUrl = song.oneClickUrl or urls.oneClick,
        zipUrl = song.zipUrl or urls.zip,
        detailUrl = song.detailUrl or urls.apiDetail,
        coverUrl = song.coverUrl,
        previewUrl = song.previewUrl or urls.preview,
        infoDatUrl = song.infoDatUrl,
        twitchCode = song.twitchCode,
        raw = song,
    }
end

function Api.toUiSongs(songs, options)
    local result = {}
    for _, song in ipairs(songs or {}) do
        local uiSong, err = Api.toUiSong(song, options)
        if err then
            return nil, err
        end
        table.insert(result, uiSong)
    end
    return result
end

function Api.searchUi(query, options)
    options = options or {}
    local songs, err
    if options.cached then
        songs = Api.searchCached(query)
    else
        songs, err = Api.search(query, options)
    end
    if err then
        return nil, err
    end
    return Api.toUiSongs(songs, options)
end

function Api.getSongUi(songOrId, options)
    options = options or {}
    local detail, err = Api.getSong(songOrId, options)
    if err then
        return nil, err
    end
    return Api.toUiSong(detail, options)
end

function Api.scanInstalledSongs(options)
    options = options or {}
    local root = options.songFolder or Api.resolveSongFolder()
    if root == nil or root == "" then
        return setError("songFolder is required; use configure({ songFolder = '.../Ragnarock/CustomSongs' })")
    end

    local files, err = listFiles(root)
    if err then
        emit("installed.scan.failed", {
            root = root,
            error = err,
        })
        return nil, err
    end

    local byPath = {}
    for _, filePath in ipairs(files or {}) do
        local name = string.lower(baseName(filePath))
        local directory = parentPath(filePath)
        if directory ~= "" and (name == ".id" or name == ".hash" or name == "info.dat") then
            if byPath[directory] == nil then
                byPath[directory] = {
                    path = directory,
                    metadata = {},
                }
            end
            local entry = byPath[directory]
            if name == ".id" then
                local value = readTrimmed(filePath)
                entry.id = tonumber(value) or value
                entry.metadata.idPath = filePath
            elseif name == ".hash" then
                entry.hash = readTrimmed(filePath)
                entry.metadata.hashPath = filePath
            elseif name == "info.dat" then
                entry.infoDatPath = filePath
            end
        end
    end

    local songs = {}
    for directory, entry in pairs(byPath) do
        if entry.id == nil then
            local inferredId = tonumber(baseName(directory))
            if inferredId ~= nil then
                entry.id = inferredId
            end
        end
        table.insert(songs, entry)
    end
    table.sort(songs, function(left, right)
        return tostring(left.id or left.path) < tostring(right.id or right.path)
    end)
    rememberInstalled(songs, root)
    emit("installed.scan.completed", {
        root = root,
        songs = songs,
    })
    return songs
end

function Api.getInstalledSong(songOrId, options)
    options = options or {}
    if options.refresh or state.installed.songs == nil then
        local _, err = Api.scanInstalledSongs(options)
        if err then
            return nil, err
        end
    end

    if type(songOrId) == "table" then
        if songOrId.id ~= nil and state.installed.byId[tostring(songOrId.id)] ~= nil then
            return state.installed.byId[tostring(songOrId.id)]
        end
        if songOrId.hash ~= nil and songOrId.hash ~= "" then
            return state.installed.byHash[string.lower(tostring(songOrId.hash))]
        end
        return nil
    end

    local id = tonumber(songOrId)
    if id ~= nil then
        return state.installed.byId[tostring(id)]
    end
    if songOrId ~= nil and tostring(songOrId) ~= "" then
        return state.installed.byHash[string.lower(tostring(songOrId))]
    end
    return nil
end

function Api.isInstalled(songOrId, options)
    local song, err = Api.getInstalledSong(songOrId, options)
    if err then
        return nil, err
    end
    return song ~= nil, song
end

function Api.compareInstalledWithUpdates(options)
    options = options or {}
    local installed, installErr = Api.scanInstalledSongs(options)
    if installErr then
        return nil, installErr
    end
    local updates = options.updates
    if updates == nil then
        local updateErr = nil
        updates, updateErr = Api.checkUpdates()
        if updateErr then
            return nil, updateErr
        end
    end

    local missing = {}
    local changed = {}
    local unchanged = {}
    for _, remote in ipairs(updates or {}) do
        local localSong = Api.getInstalledSong(remote)
        if localSong == nil then
            table.insert(missing, remote)
        elseif remote.hash ~= nil and localSong.hash ~= nil and string.lower(tostring(remote.hash)) ~= string.lower(tostring(localSong.hash)) then
            table.insert(changed, {
                remote = remote,
                installed = localSong,
            })
        else
            table.insert(unchanged, {
                remote = remote,
                installed = localSong,
            })
        end
    end

    local result = {
        installed = installed,
        remote = updates or {},
        missing = missing,
        changed = changed,
        unchanged = unchanged,
    }
    emit("installed.compare.completed", result)
    return result
end

function Api.getSong(songOrId, options)
    options = options or {}
    local seed = nil
    if type(songOrId) == "table" then
        seed = songOrId
    else
        seed = state.cache.byId[tostring(songOrId)] or state.cache.bySlug[tostring(songOrId)]
    end
    if seed == nil and tonumber(songOrId) ~= nil then
        seed = { id = tonumber(songOrId) }
    end
    if seed == nil then
        return setError("song is not cached; call search/preload first or pass a song table with detailUrl")
    end
    if not options.refresh and seed.description ~= nil then
        return seed
    end

    local url = seed.detailUrl
    if url == nil and seed.slug ~= nil then
        url = joinUrl(state.config.baseUrl, "/song/" .. seed.slug)
    end
    if state.config.preferApi and not options.html and seed.id ~= nil then
        emit("song.started", {
            song = seed,
            url = joinUrl(state.config.apiBaseUrl, "/api/song/" .. tostring(seed.id)),
        })
        local apiSongs, apiErr = fetchApiSongs("/api/song/" .. tostring(seed.id))
        if apiSongs ~= nil and apiSongs[1] ~= nil then
            local detail = mergeSong(seed, apiSongs[1])
            state.cache.byId[tostring(detail.id)] = detail
            emit("song.completed", {
                song = detail,
            })
            return detail
        elseif apiErr ~= nil then
            state.lastError = apiErr
        end
    end
    if url == nil then
        return setError("song detail URL is unavailable for id " .. tostring(seed.id))
    end
    emit("song.started", {
        song = seed,
        url = url,
    })
    local html, err = httpGet(url)
    if err then
        emit("song.failed", {
            song = seed,
            url = url,
            error = err,
        })
        return nil, err
    end
    local detail = parseSongDetail(html, seed)
    if detail.id ~= nil then
        state.cache.byId[tostring(detail.id)] = detail
    end
    if detail.slug ~= nil then
        state.cache.bySlug[tostring(detail.slug)] = detail
    end
    emit("song.completed", {
        song = detail,
    })
    return detail
end

function Api.openOneClick(songOrId)
    local urls = Api.urlsFor(songOrId)
    if urls == nil then
        return setError("missing song id")
    end
    if type(state.config.openUrl) == "function" then
        local result, err = state.config.openUrl(urls.oneClick, state.config)
        if err then
            emit("install.failed", {
                url = urls.oneClick,
                error = err,
            })
            return nil, err
        end
        emit("install.opened", {
            url = urls.oneClick,
            result = result,
        })
        return result
    end
    emit("install.opened", {
        url = urls.oneClick,
        result = urls.oneClick,
    })
    return urls.oneClick
end

function Api.installSong(songOrId, options)
    options = options or {}
    local method = tostring(options.method or "oneClick")
    if method == "oneClick" or method == "one-click" or method == "ragnac" then
        local urls = Api.urlsFor(songOrId)
        if urls == nil then
            return setError("missing song id")
        end
        local openResult, err = Api.openOneClick(songOrId)
        if err then
            return nil, err
        end
        return {
            id = type(songOrId) == "table" and songOrId.id or songOrId,
            method = "oneClick",
            url = urls.oneClick,
            openResult = openResult,
        }
    end
    if method == "zip" or method == "download" then
        return Api.downloadSong(songOrId, options)
    end
    return setError("unknown install method: " .. method)
end

function Api.downloadSong(songOrId, options)
    options = options or {}
    if options.method == "oneClick" or options.method == "one-click" or options.method == "ragnac" then
        return Api.installSong(songOrId, { method = "oneClick" })
    end
    local id = type(songOrId) == "table" and songOrId.id or songOrId
    if id == nil then
        return setError("missing song id")
    end
    local songFolder = options.songFolder or Api.resolveSongFolder()
    if songFolder == nil or songFolder == "" then
        return setError("songFolder is required; use configure({ songFolder = '.../Ragnarock/CustomSongs' })")
    end

    local targetDir = songFolder
    if options.subfolder ~= false then
        targetDir = joinPath(songFolder, options.subfolder or state.config.downloadSubfolder or tostring(id))
    end
    if type(state.config.mkdirs) == "function" then
        local ok, err = state.config.mkdirs(targetDir, state.config)
        if ok == nil or ok == false then
            return nil, err or "failed to create target directory"
        end
    end

    local zipPath = joinPath(targetDir, tostring(id) .. ".zip")
    local urls = Api.urlsFor(id)
    if state.config.apiKey ~= nil and state.config.apiKey ~= "" then
        urls.zip = joinUrl(state.config.apiBaseUrl, "/songs/download/" .. tostring(id) .. "/" .. tostring(state.config.apiKey))
    end
    local downloaded, err
    if type(state.config.downloadFile) == "function" then
        downloaded, err = state.config.downloadFile(urls.zip, zipPath, state.config)
    else
        downloaded, err = defaultDownloadFile(urls.zip, zipPath)
    end
    if err then
        emit("download.failed", {
            id = id,
            url = urls.zip,
            zipPath = zipPath,
            error = err,
        })
        return nil, err
    end

    if options.extract == false then
        local result = {
            id = tonumber(id) or id,
            zipPath = downloaded or zipPath,
            targetDir = targetDir,
            extracted = false,
        }
        recordInstalledMetadata(targetDir, songOrId)
        emit("download.completed", result)
        return result
    end

    local extracted, unzipErr
    if type(state.config.unzipFile) == "function" then
        extracted, unzipErr = state.config.unzipFile(downloaded or zipPath, targetDir, state.config)
    else
        extracted, unzipErr = defaultUnzipFile(downloaded or zipPath, targetDir)
    end
    if unzipErr then
        emit("download.failed", {
            id = id,
            url = urls.zip,
            zipPath = downloaded or zipPath,
            error = unzipErr,
        })
        return nil, unzipErr
    end
    local result = {
        id = tonumber(id) or id,
        zipPath = downloaded or zipPath,
        targetDir = extracted or targetDir,
        extracted = true,
    }
    recordInstalledMetadata(targetDir, songOrId)
    emit("download.completed", result)
    return result
end

local function completeVoteCallback(callback, payload)
    if type(callback) == "function" then
        safeCall(callback, payload)
    end
end

local function resolveVoteScoreEndpoint(options)
    options = options or {}
    if options.useWanApi == true or state.config.useWanApi == true then
        return discoverWanApiScoreEndpoint()
    end
    return nil, "WanApi voting is disabled; configure useWanApi=true"
end

local function performVoteRequest(method, beatmap, direction, callback, options)
    options = options or {}
    local cleanBeatmap = trim(beatmap)
    if cleanBeatmap == "" then
        return setError("beatmap hash is required")
    end
    if direction ~= nil and direction ~= "up" and direction ~= "down" then
        return setError("vote direction must be 'up', 'down', or nil")
    end

    local scoreEndpoint, scoreEndpointError = resolveVoteScoreEndpoint(options)
    if scoreEndpoint == nil then
        return setError(scoreEndpointError or Api.lastError())
    end
    local voteEndpoint, endpointError = deriveVoteEndpoint(scoreEndpoint)
    if voteEndpoint == nil then
        return setError(endpointError)
    end

    state.requestSerial = state.requestSerial + 1
    local generation = state.requestSerial
    state.voteGenerations[cleanBeatmap] = generation
    local url = voteEndpoint
    local body = nil
    if method == "GET" then
        url = url .. "?beatmap=" .. urlEncode(cleanBeatmap)
    else
        body = '{"beatmap":"' .. jsonEscape(cleanBeatmap) .. '","direction":'
            .. (direction == nil and "null" or ('"' .. direction .. '"')) .. "}"
    end

    emit("vote.started", {
        beatmap = cleanBeatmap,
        direction = direction,
        generation = generation,
    })
    local transportId = httpRequest(method, url, body, function(response, transportError)
        if state.voteGenerations[cleanBeatmap] ~= generation then
            emit("vote.stale", { beatmap = cleanBeatmap, generation = generation })
            return
        end
        if transportError ~= nil then
            local failed = {
                ok = false,
                beatmap = cleanBeatmap,
                generation = generation,
                error = transportError,
            }
            state.lastError = transportError.message or transportError.code
            emit("vote.failed", failed)
            completeVoteCallback(callback, failed)
            return
        end

        local parsed, parseError = parseVoteResponse(response and response.body or "")
        local status = tonumber(response and response.status) or 0
        if status < 200 or status >= 300 or parsed == nil then
            local failed = {
                ok = false,
                beatmap = cleanBeatmap,
                generation = generation,
                status = status,
                error = parseError or { code = "http_error", message = "vote server rejected the request" },
            }
            state.lastError = failed.error.message or failed.error.code
            emit("vote.failed", failed)
            completeVoteCallback(callback, failed)
            return
        end
        if parsed.beatmap ~= nil and parsed.beatmap ~= cleanBeatmap then
            local failed = {
                ok = false,
                beatmap = cleanBeatmap,
                generation = generation,
                status = status,
                error = { code = "mismatched_response", message = "vote response belongs to another beatmap" },
            }
            emit("vote.failed", failed)
            completeVoteCallback(callback, failed)
            return
        end

        local completed = {
            ok = true,
            beatmap = cleanBeatmap,
            generation = generation,
            status = status,
            state = parsed,
        }
        state.lastError = nil
        emit("vote.completed", completed)
        completeVoteCallback(callback, completed)
    end)
    if transportId == nil then
        return nil, "vote transport could not start"
    end
    return generation
end

function Api.getWanApiVote(beatmap, callback, options)
    return performVoteRequest("GET", beatmap, nil, callback, options)
end

function Api.setWanApiVote(beatmap, direction, callback, options)
    return performVoteRequest("PUT", beatmap, direction, callback, options)
end

function Api.clearWanApiVote(beatmap, callback, options)
    return Api.setWanApiVote(beatmap, nil, callback, options)
end

function Api.vote(songOrId, direction, options)
    options = options or {}
    local id = type(songOrId) == "table" and songOrId.id or songOrId
    if id == nil or trim(id) == "" then
        return setError("missing song id")
    end
    local cleanDirection = tostring(direction or ""):lower()
    if cleanDirection ~= "up" and cleanDirection ~= "down" then
        return setError("vote direction must be 'up' or 'down'")
    end
    local path = cleanDirection == "up" and "/song-vote/upvote/" or "/song-vote/downvote/"
    emit("vote.started", { id = id, direction = cleanDirection })
    local response, err = httpPost(joinUrl(state.config.baseUrl, path .. urlEncode(id)), "")
    if err then
        emit("vote.failed", { id = id, direction = cleanDirection, error = err })
        return nil, err
    end
    emit("vote.completed", { id = id, direction = cleanDirection, response = response })
    return response
end

function Api.upvote(songOrId, options)
    return Api.vote(songOrId, "up", options)
end

function Api.downvote(songOrId, options)
    return Api.vote(songOrId, "down", options)
end

Api._internals = {
    parseLibrary = parseLibrary,
    parseSongDetail = parseSongDetail,
    urlEncode = urlEncode,
    stripTags = stripTags,
    deriveVoteEndpoint = deriveVoteEndpoint,
    parseVoteResponse = parseVoteResponse,
    redactEndpoint = redactEndpoint,
    archivePathIsSafe = archivePathIsSafe,
}

return Api
