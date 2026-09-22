local Api = {
    VERSION = "0.3.0",
}

local state = {
    config = {
        baseUrl = "https://ragnacustoms.com",
        apiBaseUrl = "https://ragnacustoms.com",
        downloadBaseUrl = "https://api.ragnacustoms.com",
        transport = "varest",
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

local stripTags

local function htmlParse(source)
    local root = { tag = "#root", attrs = {}, children = {}, text = "" }
    local stack = { root }
    local position = 1
    local function whitespace(character)
        return character == " " or character == "\t" or character == "\r" or character == "\n"
    end
    local function oneOf(character, values)
        return values:find(character, 1, true) ~= nil
    end
    local function addText(value)
        if value ~= "" then
            local node = stack[#stack]
            node.text = node.text .. value
        end
    end
    local function parseTag(value)
        local cursor, length = 1, #value
        while cursor <= length and whitespace(value:sub(cursor, cursor)) do cursor = cursor + 1 end
        local start = cursor
        while cursor <= length and not whitespace(value:sub(cursor, cursor)) and value:sub(cursor, cursor) ~= "/" do cursor = cursor + 1 end
        local name = value:sub(start, cursor - 1):lower()
        local attrs = {}
        while cursor <= length do
            while cursor <= length and (whitespace(value:sub(cursor, cursor)) or value:sub(cursor, cursor) == "/") do cursor = cursor + 1 end
            if cursor > length then break end
            local keyStart = cursor
            while cursor <= length and not whitespace(value:sub(cursor, cursor)) and not oneOf(value:sub(cursor, cursor), "=/>") do cursor = cursor + 1 end
            local key = value:sub(keyStart, cursor - 1):lower()
            while cursor <= length and whitespace(value:sub(cursor, cursor)) do cursor = cursor + 1 end
            local attrValue = ""
            if value:sub(cursor, cursor) == "=" then
                cursor = cursor + 1
                while cursor <= length and whitespace(value:sub(cursor, cursor)) do cursor = cursor + 1 end
                local quote = value:sub(cursor, cursor)
                if quote == '"' or quote == "'" then
                    cursor = cursor + 1
                    local valueStart = cursor
                    while cursor <= length and value:sub(cursor, cursor) ~= quote do cursor = cursor + 1 end
                    attrValue = value:sub(valueStart, cursor - 1)
                    cursor = cursor + 1
                else
                    local valueStart = cursor
                    while cursor <= length and not whitespace(value:sub(cursor, cursor)) and value:sub(cursor, cursor) ~= ">" do cursor = cursor + 1 end
                    attrValue = value:sub(valueStart, cursor - 1)
                end
            end
            if key ~= "" then attrs[key] = htmlDecode(attrValue) end
        end
        return name, attrs
    end
    while position <= #source do
        local start = source:find("<", position, true)
        if start == nil then addText(source:sub(position)); break end
        addText(source:sub(position, start - 1))
        local finish = source:find(">", start + 1, true)
        if finish == nil then addText(source:sub(start)); break end
        local token = source:sub(start + 1, finish - 1)
        if token:sub(1, 3) == "!--" then
            position = (source:find("-->", finish + 1, true) or #source - 2) + 3
        elseif token:sub(1, 1) == "/" then
            local closing = token:sub(2)
            local closeStart = 1
            while closeStart <= #closing and whitespace(closing:sub(closeStart, closeStart)) do closeStart = closeStart + 1 end
            local closeEnd = closeStart
            while closeEnd <= #closing and not whitespace(closing:sub(closeEnd, closeEnd)) and closing:sub(closeEnd, closeEnd) ~= ">" do closeEnd = closeEnd + 1 end
            closing = closing:sub(closeStart, closeEnd - 1)
            for index = #stack, 2, -1 do
                if stack[index].tag == string.lower(closing or "") then
                    for _ = #stack, index, -1 do table.remove(stack) end
                    break
                end
            end
            position = finish + 1
        elseif token:sub(1, 1) == "!" or token:sub(1, 1) == "?" then
            position = finish + 1
        else
            local selfClosing = token:sub(-1) == "/"
            local name, attrs = parseTag(selfClosing and token:sub(1, -2) or token)
            local node = { tag = name, attrs = attrs, children = {}, text = "", parent = stack[#stack] }
            table.insert(stack[#stack].children, node)
            if not selfClosing and name ~= "meta" and name ~= "link" and name ~= "img" and name ~= "br" and name ~= "input" then
                table.insert(stack, node)
            end
            position = finish + 1
        end
    end
    return root
end

local function htmlText(node)
    local text = node.text or ""
    for _, child in ipairs(node.children or {}) do text = text .. htmlText(child) end
    return stripTags(text)
end

local function htmlFind(node, tag, className)
    local result = {}
    if node.tag == tag and (className == nil or (node.attrs.class or ""):find(className, 1, true) ~= nil) then
        table.insert(result, node)
    end
    for _, child in ipairs(node.children or {}) do
        for _, match in ipairs(htmlFind(child, tag, className)) do table.insert(result, match) end
    end
    return result
end

stripTags = function(value)
    local source, text, position = tostring(value or ""), {}, 1
    local inside = false
    while position <= #source do
        local character = source:sub(position, position)
        if character == "<" then inside = true
        elseif character == ">" then inside = false
        elseif not inside then table.insert(text, character) end
        position = position + 1
    end
    return normalizeSpace(htmlDecode(table.concat(text)))
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

local function hostPath(path)
    local normalized = tostring(path or ""):gsub("\\", "/")
    if normalized:sub(1, 3):lower() == "z:/" then
        return normalized:sub(3)
    end
    return normalized
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

-- VaRest exposes a JSON object while the shell transport exposes text. Keep
-- the public response contract transport-neutral by decoding the latter once
-- here instead of making each endpoint search the JSON with patterns.
local JSON_NULL = {}

local function decodeJson(text)
    local source, position = tostring(text or ""), 1

    local function skipWhitespace()
        local _, finish = source:find("^%s*", position)
        position = (finish or position - 1) + 1
    end

    local parseValue
    local function parseString()
        if source:sub(position, position) ~= '"' then return nil end
        position = position + 1
        local result = {}
        while position <= #source do
            local character = source:sub(position, position)
            position = position + 1
            if character == '"' then return table.concat(result) end
            if character ~= "\\" then
                table.insert(result, character)
            else
                local escaped = source:sub(position, position)
                position = position + 1
                local replacements = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if escaped == "u" then
                    local hex = source:sub(position, position + 3)
                    if not hex:match("^%x%x%x%x$") then return nil end
                    table.insert(result, "\\u" .. hex)
                    position = position + 4
                else
                    table.insert(result, replacements[escaped] or escaped)
                end
            end
        end
        return nil
    end

    local function parseNumber()
        local _, finish = source:find("^[%-]?%d+%.?%d*[eE]?[+%-]?%d*", position)
        if finish == nil or finish < position then return nil end
        local value = tonumber(source:sub(position, finish))
        if value == nil then return nil end
        position = finish + 1
        return value
    end

    local function parseArray()
        position = position + 1
        local result = {}
        skipWhitespace()
        if source:sub(position, position) == "]" then position = position + 1; return result end
        while position <= #source do
            local value = parseValue()
            if value == nil then return nil end
            table.insert(result, value)
            skipWhitespace()
            local separator = source:sub(position, position)
            position = position + 1
            if separator == "]" then return result end
            if separator ~= "," then return nil end
            skipWhitespace()
        end
        return nil
    end

    local function parseObject()
        position = position + 1
        local result = {}
        skipWhitespace()
        if source:sub(position, position) == "}" then position = position + 1; return result end
        while position <= #source do
            local key = parseString()
            if key == nil then return nil end
            skipWhitespace()
            if source:sub(position, position) ~= ":" then return nil end
            position = position + 1
            local value = parseValue()
            if value == nil then return nil end
            result[key] = value
            skipWhitespace()
            local separator = source:sub(position, position)
            position = position + 1
            if separator == "}" then return result end
            if separator ~= "," then return nil end
            skipWhitespace()
        end
        return nil
    end

    parseValue = function()
        skipWhitespace()
        local character = source:sub(position, position)
        if character == '"' then return parseString() end
        if character == "{" then return parseObject() end
        if character == "[" then return parseArray() end
        if source:sub(position, position + 3) == "true" then position = position + 4; return true end
        if source:sub(position, position + 4) == "false" then position = position + 5; return false end
        if source:sub(position, position + 3) == "null" then position = position + 4; return JSON_NULL end
        return parseNumber()
    end

    local value = parseValue()
    skipWhitespace()
    if value == nil or position <= #source then return nil end
    return value
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
    local quoted = shellQuote(hostPath(root))
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
    local resolvedPath = hostPath(path)
    local handle, err = io.open(resolvedPath, "rb")
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
    local resolvedPath = hostPath(path)
    local handle, err = io.open(resolvedPath, "wb")
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

local requestHeaders

local function defaultHttpGet(url)
    local headerArgs = ""
    for name, value in pairs(requestHeaders()) do
        headerArgs = headerArgs .. " -H " .. shellQuote(tostring(name) .. ": " .. tostring(value))
    end
    local command = string.format("%s -fsSL%s %s", shellQuote(state.config.curlPath), headerArgs, shellQuote(url))
    return readPipe(command)
end

requestHeaders = function()
    local headers = {}
    for name, value in pairs(state.config.headers or {}) do
        headers[tostring(name)] = tostring(value)
    end
    if state.config.apiKey ~= nil and state.config.apiKey ~= "" then
        headers["X-API-Key"] = tostring(state.config.apiKey)
    end
    return headers
end

local function defaultHttpPost(url, body)
    local contentType = tostring(body or ""):match("^%s*{") and "application/json" or "application/x-www-form-urlencoded"
    local headerArgs = " -H " .. shellQuote("Content-Type: " .. contentType)
    for name, value in pairs(requestHeaders()) do
        headerArgs = headerArgs .. " -H " .. shellQuote(tostring(name) .. ": " .. tostring(value))
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
    local headerArgs = ""
    for name, value in pairs(requestHeaders()) do
        headerArgs = headerArgs .. " -H " .. shellQuote(tostring(name) .. ": " .. tostring(value))
    end
    local command = string.format("%s -fL --create-dirs%s -o %s %s",
        shellQuote(state.config.curlPath), headerArgs, shellQuote(destination), shellQuote(url))
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
        return state.config.httpGet(url, state.config, requestHeaders())
    end
    return defaultHttpGet(url)
end

local function httpPost(url, body)
    if type(state.config.httpPost) == "function" then
        return state.config.httpPost(url, body, state.config, requestHeaders())
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

local function responseString(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    local valueType = safeObjectCall(function() return tostring(value:type()) end, "")
    if valueType == "RemoteUnrealParam" or valueType == "LocalUnrealParam" then
        local inner = safeObjectCall(function() return value:get() end, nil)
        if inner ~= nil and inner ~= value then
            return responseString(inner)
        end
    end
    if valueType == "FString" or valueType == "FText" then
        local rendered = safeObjectCall(function() return value:ToString() end, nil)
        if rendered ~= nil and not tostring(rendered):find("DEPRECATED", 1, true) then
            return tostring(rendered)
        end
    end
    local stringValue = safeObjectCall(function()
        return value:ToString()
    end, nil)
    if stringValue ~= nil then
        if type(stringValue) == "string" then return stringValue end
        local rendered = safeObjectCall(function() return stringValue:ToString() end, nil)
        if rendered ~= nil then return tostring(rendered) end
        return tostring(stringValue)
    end
    local unwrapped = unwrapRemoteValue(value)
    if type(unwrapped) == "string" then
        return unwrapped
    end
    if unwrapped ~= nil and unwrapped ~= value then
        local rendered = safeObjectCall(function() return unwrapped:ToString() end, nil)
        if rendered ~= nil then return tostring(rendered) end
    end
    return nil
end

local function responseBody(request)
    -- VaRest returns the response as an FString userdata on the UE4SS path.
    -- Reading ResponseContent after the call can expose only a stale/truncated
    -- reflected value, so prefer the value returned by the accessor itself.
    local returned = safeObjectCall(function()
        return request:GetResponseContentAsString(false)
    end, nil)
    local returnedText = responseString(returned)
    if returnedText ~= nil and returnedText ~= ""
        and not returnedText:find("DEPRECATED", 1, true) then
        return returnedText
    end

    local property = safeObjectCall(function()
        return request.ResponseContent
    end, nil)
    local propertyText = responseString(property)
    if propertyText ~= nil and propertyText ~= "" then return propertyText end
    return ""
end

local function completedResponseBody(request)
    local responseObject = safeObjectCall(function() return request.ResponseJsonObj end, nil)
    if responseObject == nil then
        responseObject = safeObjectCall(function() return request:GetPropertyValue("ResponseJsonObj") end, nil)
    end
    if type(StaticFindObject) == "function" and type(request.CallFunction) == "function" then
        local fn = safeObjectCall(function()
            return StaticFindObject("Function /Script/VaRest.VaRestRequestJSON:GetResponseObject")
        end, nil)
        if fn ~= nil then
            local reflectedObject = safeObjectCall(function() return request:CallFunction(fn) end, nil)
            if reflectedObject ~= nil then responseObject = reflectedObject end
        end
    end
    if responseObject ~= nil then
        local rawText = responseBody(request)
        if rawText ~= nil and rawText:find('"Results"', 1, true) ~= nil then
            return rawText
        end
        local function jsonFieldFunction(name)
            if type(StaticFindObject) ~= "function" then return nil end
            return safeObjectCall(function()
                return StaticFindObject("Function /Script/VaRest.VaRestJsonObject:" .. name)
            end, nil)
        end
        local function jsonField(object, functionName, fieldName, fallback)
            local fn = jsonFieldFunction(functionName)
            if fn == nil or object == nil or type(object.CallFunction) ~= "function" then
                return fallback
            end
            local field = safeObjectCall(function()
                return FName(fieldName, EFindName.FNAME_Find)
            end, fieldName)
            return unwrapRemoteValue(safeObjectCall(function()
                return object:CallFunction(fn, { FieldName = field })
            end, fallback))
        end
        local resultObjects = unwrapRemoteValue(jsonField(responseObject, "GetObjectArrayField", "Results", nil))
        if resultObjects == nil then
            resultObjects = unwrapRemoteValue(safeObjectCall(function()
                return responseObject:GetObjectArrayField("Results")
            end, nil))
        end
        if type(resultObjects) == "table" and #resultObjects > 0 then
            local encodedItems = {}
            for _, item in ipairs(resultObjects) do
                item = unwrapRemoteValue(item)
                local id = unwrapRemoteValue(jsonField(item, "GetIntegerField", "Id", nil))
                    or unwrapRemoteValue(jsonField(item, "GetNumberField", "Id", nil))
                    or unwrapRemoteValue(safeObjectCall(function() return item:GetIntegerField("Id") end, nil))
                local function stringField(name)
                    local direct = unwrapRemoteValue(safeObjectCall(function()
                        return item:GetStringField(name)
                    end, nil))
                    local directText = responseString(direct)
                    if directText ~= nil and directText ~= "" then return directText end
                    local reflected = unwrapRemoteValue(jsonField(item, "GetStringField", name, nil))
                    return responseString(reflected) or tostring(reflected or "")
                end
                local name = stringField("Name")
                local author = stringField("Author")
                local mapper = stringField("Mapper")
                local difficulties = stringField("Difficulties")
                if id ~= nil then
                    table.insert(encodedItems, string.format(
                        "{\"Id\":%s,\"Name\":\"%s\",\"Author\":\"%s\",\"Mapper\":\"%s\",\"Difficulties\":\"%s\"}",
                        tostring(id), jsonEscape(name), jsonEscape(author), jsonEscape(mapper), jsonEscape(difficulties)))
                end
            end
            if #encodedItems > 0 then return "[" .. table.concat(encodedItems, ",") .. "]" end
        end
        local encoded = nil
        if type(StaticFindObject) == "function" and type(responseObject.CallFunction) == "function" then
            local fn = safeObjectCall(function()
                return StaticFindObject("Function /Script/VaRest.VaRestJsonObject:EncodeJson")
            end, nil)
            if fn ~= nil then
                encoded = safeObjectCall(function() return responseObject:CallFunction(fn) end, nil)
            end
        end
        if encoded == nil then
            encoded = safeObjectCall(function() return responseObject:EncodeJson() end, nil)
        end
        local encodedText = responseString(encoded)
        if encodedText ~= nil and encodedText ~= "" then return encodedText end
    end
    return responseBody(request, true)
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
    print("[RagnaCustomsApi] HTTP transport stage=construct method=" .. tostring(method) .. "\n")
    local request, constructError = constructVaRestRequest()
    if request == nil then
        callback(nil, { code = "transport_unavailable", message = constructError })
        return nil
    end

    state.requestSerial = state.requestSerial + 1
    local requestId = state.requestSerial
    state.activeRequests[requestId] = request
    if type(ExecuteWithDelay) ~= "function" then
        state.activeRequests[requestId] = nil
        callback(nil, { code = "scheduler_unavailable", message = "UE4SS delayed execution is unavailable" })
        return nil
    end

    local completed = false
    local timedOut = false
    local function releaseRequest()
        state.activeRequests[requestId] = nil
    end
    local function finish(response, err, retainUntilTransportEnds)
        if completed then
            return
        end
        completed = true
        if not retainUntilTransportEnds then
            releaseRequest()
        end
        callback(response, err)
    end

    local function bindDelegate(name, handler)
        local delegate = safeObjectCall(function()
            return request[name]
        end, nil)
        if delegate == nil then
            delegate = safeObjectCall(function()
                return request:GetPropertyValue(name)
            end, nil)
        end
        if delegate == nil then
            return false
        end
        return safeObjectCall(function()
            delegate:Add(handler)
            return true
        end, false)
    end

    local completeBound = bindDelegate("OnRequestComplete", function()
        if timedOut then
            releaseRequest()
            return
        end
        local responseCode = safeObjectCall(function()
            return tonumber(unwrapRemoteValue(request:GetResponseCode()))
        end, 0)
        local content = responseBody(request)
        print("[RagnaCustomsApi] HTTP transport stage=complete code=" .. tostring(responseCode)
            .. " bytes=" .. tostring(#tostring(content)) .. "\n")
        if responseCode > 0 then
            finish({ status = responseCode, body = content }, nil)
        else
            finish(nil, { code = "transport_error", message = "HTTP request failed" })
        end
    end)
    local failBound = bindDelegate("OnRequestFail", function()
        if timedOut then
            releaseRequest()
            return
        end
        print("[RagnaCustomsApi] HTTP transport stage=failed error=request_failed\n")
        finish(nil, { code = "transport_error", message = "HTTP request failed" })
    end)
    if not completeBound and not failBound then
        print("[RagnaCustomsApi] HTTP transport events unavailable; using status fallback\n")
    end

    local configured, configuredError = pcall(function()
        -- VaRest uses 0=GET, 1=POST, 2=PUT. Preserve the caller's method;
        -- mapping every non-GET request to PUT breaks catalog vote/review POSTs.
        local verb = method == "GET" and 0 or method == "POST" and 1 or method == "PUT" and 2 or 1
        request:SetVerb(verb)
        request:SetContentType(2)
        for name, value in pairs(requestHeaders()) do
            request:SetHeader(tostring(name), tostring(value))
        end
        if method ~= "GET" then
            local requestObject = unwrapRemoteValue(request:GetRequestObject())
            requestObject:DecodeJson(body or "{}", true)
        end
        request:ProcessURL(url)
    end)
    if not configured then
        print("[RagnaCustomsApi] HTTP transport stage=failed error=" .. tostring(configuredError) .. "\n")
        finish(nil, { code = "transport_start_failed", message = "VaRest could not start the request" })
        return nil
    end

    if not completeBound and not failBound then
        local attempts = 0
        local function pollStatus()
            if completed then
                return
            end
            attempts = attempts + 1
            local status = safeObjectCall(function()
                return tonumber(unwrapRemoteValue(request:GetStatus()))
            end, 1)
            local responseCode = safeObjectCall(function()
                return tonumber(unwrapRemoteValue(request:GetResponseCode()))
            end, 0)
            if responseCode > 0 then
                local content = completedResponseBody(request)
                finish({ status = responseCode, body = content }, nil)
                return
            end
            if status == 2 then
                finish(nil, { code = "transport_error", message = "HTTP request failed" })
                return
            end
            if status == 3 then
                local content = completedResponseBody(request)
                if responseCode > 0 then
                    finish({ status = responseCode, body = content }, nil)
                else
                    finish(nil, { code = "transport_error", message = "HTTP request failed" })
                end
                return
            end
            if attempts >= 60 then
                finish(nil, { code = "timeout", message = "HTTP request timed out" })
                return
            end
            ExecuteWithDelay(500, pollStatus)
        end
        pcall(ExecuteWithDelay, 500, pollStatus)
    end

    ExecuteWithDelay(30000, function()
        if completed then
            return
        end
        timedOut = true
        print("[RagnaCustomsApi] HTTP transport stage=timeout\n")
        finish(nil, {
            code = "timeout",
            message = "HTTP request timed out",
        }, true)
    end)
    return requestId
end

local function httpRequest(method, url, body, callback)
    if type(state.config.httpRequest) == "function" then
        return state.config.httpRequest(method, url, body, callback, state.config, requestHeaders())
    end
    return defaultHttpRequest(method, url, body, callback)
end

local function vaRestAvailable()
    return type(state.config.httpRequest) == "function"
        or (type(StaticFindObject) == "function" and type(StaticConstructObject) == "function" and type(ExecuteWithDelay) == "function")
end

local function usesVaRest()
    return state.config.transport == "varest"
end

local function apiRequest(method, path, body, callback)
    local url = joinUrl(state.config.apiBaseUrl, path)
    local function complete(response, err)
        if err ~= nil then
            return callback(nil, err)
        end
        local status = tonumber(response and response.status)
        if status ~= nil and (status < 200 or status >= 300) then
            return callback(nil, {
                code = "http_error",
                status = status,
                message = "API returned HTTP " .. tostring(status),
            })
        end
        return callback(response, nil)
    end
    if usesVaRest() then
        if not vaRestAvailable() then
            return complete(nil, { code = "transport_unavailable", message = "VaRest transport is selected but unavailable" })
        end
        return httpRequest(method, url, body, complete)
    end

    local responseBody, err
    if method == "GET" then
        responseBody, err = httpGet(url)
    else
        responseBody, err = httpPost(url, body)
    end
    if err ~= nil then
        return complete(nil, err)
    end
    return complete({ status = 200, body = responseBody }, nil)
end

local function parseSongRow(row)
    local function trailingNumber(value)
        local source = tostring(value or "")
        local digits = ""
        for index = #source, 1, -1 do
            local character = source:sub(index, index)
            if character < "0" or character > "9" then break end
            digits = character .. digits
        end
        return tonumber(digits)
    end
    local idSource
    local function visit(node)
        local value = node.attrs["data-song-id"] or node.attrs.href
        if value ~= nil and idSource == nil then idSource = value end
        for _, child in ipairs(node.children or {}) do visit(child) end
    end
    visit(row)
    local id = trailingNumber(idSource)
    if id == nil then
        return nil
    end

    local title, slug, author, mapper, cover
    local difficulties, upvotes, downvotes, bpm = {}, 0, 0, nil
    local function inspect(node)
        local className = node.attrs.class or ""
        if node.tag == "div" and className:find("title", 1, true) ~= nil then
            title = htmlText(node)
            for _, anchor in ipairs(htmlFind(node, "a")) do
                local href = anchor.attrs.href or ""
                local slash = href:find("/song/", 1, true)
                if slash ~= nil then
                    slug = href:sub(slash + 6)
                    local query = slug:find("?", 1, true) or slug:find("#", 1, true)
                    if query ~= nil then slug = slug:sub(1, query - 1) end
                end
            end
        elseif node.tag == "div" and className:find("author", 1, true) ~= nil then
            author = htmlText(node)
        elseif node.tag == "div" and className:find("mapper", 1, true) ~= nil then
            mapper = htmlText(node)
        elseif node.tag == "img" and node.attrs.src ~= nil then
            cover = node.attrs.src
        elseif node.tag == "div" and className:find("level-list", 1, true) ~= nil then
            for _, span in ipairs(htmlFind(node, "span")) do table.insert(difficulties, tonumber(htmlText(span))) end
        elseif node.tag == "div" and className:find("up_down_vote", 1, true) ~= nil then
            local numbers = {}
            for _, child in ipairs(htmlFind(node, "i")) do
                local text = htmlText(child)
                if text ~= "" then table.insert(numbers, tonumber(text)) end
            end
            upvotes, downvotes = numbers[1] or 0, numbers[2] or 0
        end
        for _, child in ipairs(node.children or {}) do inspect(child) end
    end
    inspect(row)

    local installText = "Unknown"
    if installed == true then
        installText = "Installed"
    elseif installed == false then
        installText = "Not installed"
    end

    return {
        id = id,
        slug = slug,
        title = title or "",
        artists = splitCsv(author),
        mapper = mapper or "",
        difficulties = difficulties,
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
    for _, row in ipairs(htmlFind(htmlParse(html), "tr")) do
        local song = parseSongRow(row)
        if song ~= nil then
            table.insert(songs, song)
        end
    end
    return songs
end

local function parseApiSongObject(payload)
    if type(payload) ~= "table" then return nil end
    local id = payload.Id or payload.id
    if id == nil then
        return nil
    end

    local author = payload.Author or payload.author
    local ragnabeat = payload.Ragnabeat or payload.ragnabeat
    return {
        id = id,
        title = payload.Name or payload.name or "",
        artists = splitCsv(author),
        author = author,
        mapper = payload.Mapper or payload.mapper or "",
        difficulties = splitDifficulties(payload.Difficulties or payload.difficulties),
        hash = payload.Hash or payload.hash,
        isRanked = payload.IsRanked,
        ragnabeat = ragnabeat,
        infoDatUrl = ragnabeat and joinUrl(state.config.baseUrl, ragnabeat) or nil,
        oneClickUrl = "ragnac://install/" .. tostring(id),
        zipUrl = joinUrl(state.config.downloadBaseUrl, "/songs/download/" .. tostring(id)),
        apiDetailUrl = joinUrl(state.config.apiBaseUrl, "/api/song/" .. tostring(id)),
        apiDownloadUrl = joinUrl(state.config.downloadBaseUrl, "/songs/download/" .. tostring(id)),
        coverImageExtension = payload.CoverImageExtension,
        twitchCode = "!rc " .. tostring(id),
    }
end

local function parseApiSongs(json)
    local payload = decodeJson(json)
    local songs = {}
    if type(payload) ~= "table" then return songs end
    local items = payload.Results or payload
    for _, item in ipairs(items) do
        local song = parseApiSongObject(item)
        if song ~= nil then
            table.insert(songs, song)
        end
    end
    return songs
end

local function parseAccount(body)
    local payload = decodeJson(body)
    if type(payload) ~= "table" then
        return nil, { code = "invalid_response", message = "account response is not a JSON object" }
    end
    local account = {
        username = payload.username,
        isPremium = payload.isPremium,
        premiumUntil = payload.premiumUntil == JSON_NULL and nil or payload.premiumUntil,
    }
    if account.username == nil and account.isPremium == nil and account.premiumUntil == nil then
        return nil, { code = "invalid_response", message = "account response has no recognized fields" }
    end
    return account, nil
end

local function parsePlaylistSummary(payload)
    if type(payload) ~= "table" then return nil end
    local id, name = payload.id, payload.name
    if id == nil or name == nil then
        return nil
    end
    return {
        id = id,
        name = name,
        description = payload.description == JSON_NULL and nil or payload.description,
        owner = payload.owner == JSON_NULL and nil or payload.owner,
        songCount = payload.songCount == JSON_NULL and nil or payload.songCount,
        isPublic = payload.isPublic == JSON_NULL and nil or payload.isPublic,
    }
end

local function parsePlaylistSearch(body)
    local payload = decodeJson(body)
    if type(payload) ~= "table" then
        return nil, { code = "invalid_response", message = "playlist search response is not a JSON object" }
    end
    local result = {
        page = payload.page == JSON_NULL and nil or payload.page,
        pageSize = payload.pageSize == JSON_NULL and nil or payload.pageSize,
        total = payload.total == JSON_NULL and nil or payload.total,
        results = {},
    }
    for _, item in ipairs(payload.results or {}) do
        local playlist = parsePlaylistSummary(item)
        if playlist ~= nil then
            table.insert(result.results, playlist)
        end
    end
    if result.page == nil and result.pageSize == nil and result.total == nil and #result.results == 0 then
        return nil, { code = "invalid_response", message = "playlist search response has no recognized fields" }
    end
    return result, nil
end

local function parsePlaylistDetail(body)
    local payload = decodeJson(body)
    if type(payload) ~= "table" then
        return nil, { code = "invalid_response", message = "playlist response is not a JSON object" }
    end
    local playlist = parsePlaylistSummary(payload) or {
        id = payload.id,
        name = payload.name,
        description = payload.description,
        owner = payload.owner,
        songCount = payload.songCount,
        isPublic = payload.isPublic,
    }
    playlist.songs = {}
    for _, rawSong in ipairs(payload.songs or {}) do
        if type(rawSong) == "table" and rawSong.Id ~= nil then
            table.insert(playlist.songs, {
                id = rawSong.Id,
                title = rawSong.Name or "",
                mapper = rawSong.Mapper or "",
                hash = rawSong.Hash,
                isRanked = rawSong.IsRanked,
                author = rawSong.Author,
            })
        end
    end
    if playlist.id == nil and playlist.name == nil then
        return nil, { code = "invalid_response", message = "playlist response has no recognized fields" }
    end
    return playlist, nil
end

local function fetchApiSongs(path, callback)
    return apiRequest("GET", path, nil, function(response, err)
        if err ~= nil then
            if type(callback) == "function" then
                return callback(nil, err)
            end
            return nil, err
        end
        local status = tonumber(response and response.status) or 0
        if status < 200 or status >= 300 then
            local responseError = { code = "http_error", message = "API returned HTTP " .. tostring(status) }
            if type(callback) == "function" then
                return callback(nil, responseError)
            end
            return nil, responseError
        end
        local songs = parseApiSongs(response.body)
        if type(callback) == "function" then
            return callback(songs, nil)
        end
        return songs
    end)
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
    local source = tostring(text or "")
    local separator = source:find(":", 1, true)
    if separator == nil then return nil end
    local minutes, seconds = tonumber(source:sub(1, separator - 1)), tonumber(source:sub(separator + 1))
    return minutes and seconds and minutes * 60 + seconds or nil
end

local function parseSongDetail(html, seed)
    local document = htmlParse(html)
    local id = seed and seed.id
    local detail = {
        id = id,
    }

    local function first(tag, className)
        return htmlFind(document, tag, className)[1]
    end
    local titleNode, artistNode = first("h1"), first("h2")
    detail.title = titleNode and htmlText(titleNode) or ""
    detail.artists = {}
    if artistNode then
        for _, anchor in ipairs(htmlFind(artistNode, "a")) do table.insert(detail.artists, htmlText(anchor)) end
    end
    local mapperNode, descriptionNode = first("div", "mapper"), first("div", "description")
    detail.mapper = mapperNode and htmlText(mapperNode) or ""
    detail.description = descriptionNode and htmlText(descriptionNode) or ""
    local imageNode = first("img")
    detail.coverUrl = joinUrl(state.config.baseUrl, imageNode and (imageNode.attrs.src or "") or "")
    if detail.coverUrl == state.config.baseUrl .. "/" then
        detail.coverUrl = nil
    end
    detail.zipUrl = id and joinUrl(state.config.baseUrl, "/songs/ddl/" .. tostring(id)) or nil
    detail.oneClickUrl = id and ("ragnac://install/" .. tostring(id)) or nil
    detail.twitchCode = id and ("!rc " .. tostring(id)) or nil
    local clockNode, drumNode = first("i", "fa-clock"), first("i", "fa-drum")
    detail.durationSeconds = parseDuration(clockNode and htmlText(clockNode.parent or clockNode) or "")
    detail.bpm = tonumber(drumNode and htmlText(drumNode.parent or drumNode) or "")
    local infoNode = first("a", nil)
    detail.infoDatUrl = joinUrl(state.config.baseUrl, infoNode and (infoNode.attrs["data-file"] or "") or "")
    if detail.infoDatUrl == state.config.baseUrl .. "/" then
        detail.infoDatUrl = nil
    end
    detail.previewUrl = id and joinUrl(state.config.baseUrl, "/song/partial/preview/" .. tostring(id)) or nil

    local levelBlock = first("div", "level-list")
    detail.difficulties = {}
    if levelBlock then
        for _, span in ipairs(htmlFind(levelBlock, "span")) do table.insert(detail.difficulties, tonumber(htmlText(span))) end
    end

    local genres = {}
    for _, anchor in ipairs(htmlFind(document, "a")) do
        local href = anchor.attrs.href or ""
        if href:find("song-library?search=genre:", 1, true) ~= nil then table.insert(genres, htmlText(anchor)) end
    end
    detail.genres = genres

    local voteNode = first("div", "up_down_vote")
    detail.upvotes, detail.downvotes = 0, 0
    if voteNode then
        local numbers = {}
        for _, child in ipairs(htmlFind(voteNode, "i")) do
            local value = tonumber(htmlText(child))
            if value then table.insert(numbers, value) end
        end
        detail.upvotes, detail.downvotes = numbers[1] or 0, numbers[2] or 0
    end

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

function Api.setRuntimePaths(paths)
    paths = paths or {}
    for _, key in ipairs({ "scriptPath", "scriptDir", "win64Dir", "gameDir" }) do
        if paths[key] ~= nil then
            state.config[key] = paths[key]
        end
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
    local hasApiKey = state.config.apiKey ~= nil and state.config.apiKey ~= ""

    return {
        version = Api.VERSION,
        baseUrl = state.config.baseUrl,
        apiBaseUrl = state.config.apiBaseUrl,
        transport = state.config.transport,
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
        canFetch = state.config.transport == "varest" and hasHttpRequest or hasHttpGet,
        canSearch = state.config.transport == "varest" and hasHttpRequest or hasHttpGet,
        canPreload = state.config.transport == "varest" and hasHttpRequest or hasHttpGet,
        canOpenOneClick = hasOpenUrl,
        canReturnOneClick = true,
        canDownloadZip = hasSongFolder and hasDownload,
        canExtractZip = hasSongFolder and hasDownload and hasUnzip,
        canScanInstalled = hasSongFolder and hasListFiles,
        canWriteInstallMetadata = hasSongFolder and (type(state.config.writeFile) == "function" or io ~= nil),
        canAsyncFetch = hasHttpRequest,
        canVote = hasApiKey and (state.config.transport == "varest" and hasHttpRequest or hasHttpPost),
        voteConfigured = hasApiKey and (state.config.transport == "varest" and hasHttpRequest or hasHttpPost),
        apiKeyConfigured = hasApiKey,
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
        zip = joinUrl(state.config.downloadBaseUrl, "/songs/download/" .. tostring(id)),
        apiDownload = joinUrl(state.config.downloadBaseUrl, "/songs/download/" .. tostring(id)),
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
    local function loadWebSongs()
        local songs = {}
        for page = 1, pageCount do
            local pageSongs, err = fetchLibraryPage(nil, page)
            if err then
                return nil, err
            end
            if #pageSongs == 0 then
                break
            end
            appendSongs(songs, pageSongs)
        end
        return songs
    end

    local function finishPreload(songs, err)
        state.status.loading = false
        if err ~= nil then
            state.lastError = err.message or err
            emit("preload.failed", { error = err, status = Api.getStatus() })
            return nil, err
        end
        state.cache.songs = songs or {}
        state.cache.songsAt = now()
        state.status.ready = true
        state.status.lastRefreshAt = state.cache.songsAt
        rememberSongs(state.cache.songs)
        emit("preload.completed", { songs = state.cache.songs, status = Api.getStatus() })
        emit("ready", Api.getStatus())
        return state.cache.songs
    end

    if state.config.preferApi then
        return fetchApiSongs("/api/song/check-updates", function(songs, err)
            if (err ~= nil or songs == nil or #songs == 0) and not usesVaRest() then
                songs, err = loadWebSongs()
            end
            return finishPreload(songs, err)
        end)
    end
    if usesVaRest() then
        return finishPreload(nil, { code = "transport_configuration", message = "VaRest transport requires preferApi=true" })
    end
    local songs, err = loadWebSongs()
    return finishPreload(songs, err)
end

function Api.refreshSongs()
    return Api.preloadSongs({ force = true })
end

function Api.preloadAllSongs(maxPages)
    return Api.preloadSongs({ force = true, pages = maxPages or 9999 })
end

function Api.checkUpdates(options)
    options = options or {}
    return fetchApiSongs("/api/song/check-updates", function(songs, err)
        if err ~= nil then
            emit("updates.failed", { error = err })
            if type(options.callback) == "function" then
                return options.callback(nil, err)
            end
            return nil, err
        end
        rememberSongs(songs)
        emit("updates.completed", { songs = songs })
        if type(options.callback) == "function" then
            return options.callback(songs, nil)
        end
        return songs
    end)
end

function Api.getSongList(listId, options)
    options = options or {}
    if listId == nil or tostring(listId) == "" then
        return setError("song list id is required")
    end
    return fetchApiSongs("/api/song-list/" .. urlEncode(listId), function(songs, err)
        if err ~= nil then
            emit("songlist.failed", { id = listId, error = err })
            if type(options.callback) == "function" then
                return options.callback(nil, err)
            end
            return nil, err
        end
        rememberSongs(songs)
        emit("songlist.completed", { id = listId, songs = songs })
        if type(options.callback) == "function" then
            return options.callback(songs, nil)
        end
        return songs
    end)
end

function Api.getLastPlayed(results, options)
    options = options or {}
    results = tonumber(results) or 10
    return fetchApiSongs("/api/songs/last-played/" .. tostring(results), function(songs, err)
        emit(err and "catalog.failed" or "catalog.completed", { endpoint = "last-played", songs = songs, error = err })
        if type(options.callback) == "function" then
            return options.callback(songs, err)
        end
        return songs, err
    end)
end

function Api.getLastUploaded(results, options)
    options = options or {}
    results = tonumber(results) or 10
    return fetchApiSongs("/api/songs/last-uploaded/" .. tostring(results), function(songs, err)
        emit(err and "catalog.failed" or "catalog.completed", { endpoint = "last-uploaded", songs = songs, error = err })
        if type(options.callback) == "function" then
            return options.callback(songs, err)
        end
        return songs, err
    end)
end

function Api.getTopRated(results, days, options)
    options = options or {}
    results = tonumber(results) or 10
    days = tonumber(days) or 30
    return fetchApiSongs("/api/songs/top-rated/" .. tostring(results) .. "/" .. tostring(days), function(songs, err)
        emit(err and "catalog.failed" or "catalog.completed", { endpoint = "top-rated", songs = songs, error = err })
        if type(options.callback) == "function" then
            return options.callback(songs, err)
        end
        return songs, err
    end)
end

function Api.getAccount(options)
    options = options or {}
    return apiRequest("GET", "/api/account/me", nil, function(response, err)
        if err ~= nil then
            if type(options.callback) == "function" then options.callback(nil, err) end
            return nil, err
        end
        local account, parseError = parseAccount(response.body)
        if parseError ~= nil then
            emit("account.failed", { error = parseError })
            if type(options.callback) == "function" then options.callback(nil, parseError) end
            return nil, parseError
        end
        emit("account.completed", { account = account })
        if type(options.callback) == "function" then options.callback(account, nil) end
        return account
    end)
end

function Api.searchPlaylists(query, page, pageSize, options)
    options = options or {}
    if type(page) == "table" then
        options = page
        page = nil
        pageSize = nil
    elseif type(pageSize) == "table" then
        options = pageSize
        pageSize = nil
    end
    local path = "/api/playlist/search?q=" .. urlEncode(query or "")
        .. "&page=" .. urlEncode(page or 1)
        .. "&pageSize=" .. urlEncode(pageSize or 20)
    return apiRequest("GET", path, nil, function(response, err)
        if err ~= nil then
            if type(options.callback) == "function" then options.callback(nil, err) end
            return nil, err
        end
        local playlists, parseError = parsePlaylistSearch(response.body)
        if parseError ~= nil then
            emit("playlists.failed", { query = query or "", error = parseError })
            if type(options.callback) == "function" then options.callback(nil, parseError) end
            return nil, parseError
        end
        emit("playlists.completed", { query = query or "", result = playlists })
        if type(options.callback) == "function" then options.callback(playlists, nil) end
        return playlists
    end)
end

function Api.getPlaylist(playlistId, options)
    options = options or {}
    if playlistId == nil or trim(playlistId) == "" then
        return setError("playlist id is required")
    end
    return apiRequest("GET", "/api/playlist/" .. urlEncode(playlistId), nil, function(response, err)
        if err ~= nil then
            if type(options.callback) == "function" then options.callback(nil, err) end
            return nil, err
        end
        local playlist, parseError = parsePlaylistDetail(response.body)
        if parseError ~= nil then
            emit("playlist.failed", { id = playlistId, error = parseError })
            if type(options.callback) == "function" then options.callback(nil, parseError) end
            return nil, parseError
        end
        emit("playlist.completed", { id = playlistId, playlist = playlist })
        if type(options.callback) == "function" then options.callback(playlist, nil) end
        return playlist
    end)
end

local function parseApiStringCollection(json, keys)
    local payload = decodeJson(json)
    local values, seen = {}, {}
    local function add(value)
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(values, value)
        end
    end
    local function visit(value)
        if type(value) ~= "table" then
            add(value)
            return
        end
        for _, key in ipairs(keys) do
            add(value[key])
        end
        for _, child in pairs(value) do
            if type(child) == "table" then visit(child) end
        end
    end
    visit(payload)
    return values
end

function Api.searchCategories(query)
    local path = "/api/song-categories?q=" .. urlEncode(query or "")
    return apiRequest("GET", path, nil, function(response, err)
        if err ~= nil then
            emit("categories.failed", { query = query or "", error = err })
            return nil, err
        end
        local values = parseApiStringCollection(response.body, { "name", "Name", "category", "Category" })
        emit("categories.completed", { query = query or "", values = values })
        return values
    end)
end

function Api.searchMappers(query)
    local path = "/api/mapper?q=" .. urlEncode(query or "")
    return apiRequest("GET", path, nil, function(response, err)
        if err ~= nil then
            emit("mappers.failed", { query = query or "", error = err })
            return nil, err
        end
        local values = parseApiStringCollection(response.body, { "name", "Name", "mapper", "Mapper" })
        emit("mappers.completed", { query = query or "", values = values })
        return values
    end)
end

local function parseVoteState(body)
    local payload = decodeJson(body)
    if type(payload) ~= "table" then
        return nil, { code = "invalid_response", message = "vote response is not a JSON object" }
    end
    local upvotes, downvotes = payload.upvotes, payload.downvotes
    if upvotes == nil or downvotes == nil then
        return nil, { code = "invalid_response", message = "vote response is missing counts" }
    end
    local currentVote = payload.currentVote == JSON_NULL and nil or payload.currentVote
    if currentVote ~= nil and currentVote ~= "up" and currentVote ~= "down" then
        return nil, { code = "invalid_response", message = "vote response contains an invalid selection" }
    end
    local state = {
        id = payload.id == JSON_NULL and nil or payload.id,
        currentVote = currentVote,
        upvotes = upvotes,
        downvotes = downvotes,
    }
    local rating = payload.rating
    if type(rating) == "table" then
        state.rating = {
            average = rating.average,
            count = rating.count,
        }
    end
    if type(payload.review) == "table" then
        local review = payload.review
        state.review = {
            funFactor = review.funFactor,
            rhythm = review.rhythm,
            patternQuality = review.patternQuality,
            readability = review.readability,
            flow = review.flow,
            levelQuality = review.levelQuality,
            feedback = review.feedback == JSON_NULL and nil or review.feedback,
        }
    end
    return state, nil
end

function Api.getSongVote(songOrId)
    local id = type(songOrId) == "table" and songOrId.id or songOrId
    if id == nil or trim(id) == "" then return setError("missing song id") end
    return apiRequest("GET", "/api/song/" .. urlEncode(id) .. "/vote", nil, function(response, err)
        if err ~= nil then
            emit("vote.details.failed", { id = id, error = err })
            return nil, err
        end
        local state, parseError = parseVoteState(response.body)
        if parseError ~= nil then
            emit("vote.details.failed", { id = id, error = parseError })
            return nil, parseError
        end
        emit("vote.details.completed", { id = id, response = state })
        return state
    end)
end

function Api.reviewSong(songOrId, review)
    local id = type(songOrId) == "table" and songOrId.id or songOrId
    if id == nil or trim(id) == "" then return setError("missing song id") end
    review = review or {}
    local fields, encoded = { "funFactor", "rhythm", "patternQuality", "readability", "flow", "levelQuality", "feedback" }, {}
    for _, field in ipairs(fields) do
        if review[field] ~= nil then
            local value = review[field]
            table.insert(encoded, jsonEscape(field) .. ":" .. (type(value) == "number" and tostring(value) or jsonEscape(value)))
        end
    end
    local path = "/api/song/" .. urlEncode(id) .. "/review"
    local body = "{" .. table.concat(encoded, ",") .. "}"
    return apiRequest("POST", path, body, function(response, err)
        if err ~= nil then
            emit("review.failed", { id = id, error = err })
            return nil, err
        end
        local state, parseError = parseVoteState(response.body)
        if parseError ~= nil then
            emit("review.failed", { id = id, error = parseError })
            return nil, parseError
        end
        emit("review.completed", { id = id, response = state })
        return state
    end)
end

function Api.search(query, options)
    options = options or {}
    local page = tonumber(options.page or 1) or 1
    emit("search.started", {
        query = query or "",
        page = page,
    })
    if usesVaRest() and (not state.config.preferApi or options.html) then
        return setError("VaRest transport requires preferApi=true and API search")
    end

    if state.config.preferApi and not options.html then
        return fetchApiSongs("/api/search/" .. urlEncode(query or ""), function(songs, err)
            if err ~= nil and not usesVaRest() then
                songs, err = fetchLibraryPage(query or "", page)
            end
            if err ~= nil then
                emit("search.failed", { query = query or "", page = page, error = err })
                if type(options._onResult) == "function" then options._onResult(nil, err) end
                return nil, err
            end
            rememberSongs(songs)
            emit("search.completed", { query = query or "", page = page, songs = songs })
            if type(options._onResult) == "function" then options._onResult(songs, nil) end
            return songs
        end)
    end

    local songs, err = fetchLibraryPage(query or "", page)
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
    if usesVaRest() and not options.cached then
        return Api.search(query, {
            page = options.page,
            html = options.html,
            _onResult = function(songs, err)
                if err ~= nil then
                    emit("search.ui.failed", { query = query or "", error = err })
                    return
                end
                emit("search.ui.completed", { query = query or "", songs = Api.toUiSongs(songs, options) })
            end,
        })
    end
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
    if usesVaRest() then
        local result = Api.getSong(songOrId, {
            refresh = options.refresh,
            details = options.details,
            _onResult = function(detail, err)
                if err ~= nil then
                    emit("song.ui.failed", { song = songOrId, error = err })
                    return
                end
                emit("song.ui.completed", { song = Api.toUiSong(detail, options) })
            end,
        })
        if type(result) == "table" then
            emit("song.ui.completed", { song = Api.toUiSong(result, options) })
        end
        return result
    end
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

-- Read/write the catalog marker for one already-loaded custom-song folder.
-- This intentionally does not scan CustomSongs: callers that know the loaded
-- folder can use the marker without touching unrelated installations.
function Api.readInstalledSongId(songFolder)
    if songFolder == nil or trim(songFolder) == "" then
        return nil, "songFolder is required"
    end
    local path = joinPath(songFolder, ".id")
    local value, err = readTextFile(path)
    if value == nil then
        return nil, err
    end
    local trimmed = trim(value)
    local id = tonumber(tostring(trimmed):match("^%s*(%d+)%s*$"))
    if id == nil or id <= 0 then
        return nil, "invalid catalog id in " .. path
    end
    return math.floor(id), nil, path
end

function Api.writeInstalledSongId(songFolder, songId)
    local id = tonumber(songId)
    if songFolder == nil or trim(songFolder) == "" then
        return nil, "songFolder is required"
    end
    if id == nil or id <= 0 then
        return nil, "songId must be a positive number"
    end
    local path = joinPath(songFolder, ".id")
    local result, err = writeTextFile(path, tostring(math.floor(id)) .. "\n")
    if result == nil and err ~= nil then
        return nil, err
    end
    emit("installed.id.written", { path = path, id = math.floor(id), songFolder = songFolder })
    return math.floor(id), nil, path
end

local function normalizedCatalogText(value)
    return trim(tostring(value or "")):lower():gsub("[%p%c]", " "):gsub("%s+", " ")
end

local function catalogValueMatches(value, candidates)
    local needle = normalizedCatalogText(value)
    if needle == "" then return true end
    for _, candidate in ipairs(candidates or {}) do
        local normalized = normalizedCatalogText(candidate)
        if normalized ~= "" and (needle == normalized
            or normalized:find(needle, 1, true)
            or needle:find(normalized, 1, true)) then
            return true
        end
    end
    return false
end

local function catalogSongMatchesMetadata(song, metadata)
    if type(song) ~= "table" or type(metadata) ~= "table" then return false end
    if metadata.title == nil or not catalogValueMatches(metadata.title, { song.title, song.name }) then
        return false
    end
    local artists = song.artists or splitCsv(song.author)
    if metadata.artist ~= nil and metadata.artist ~= "" and not catalogValueMatches(metadata.artist, artists) then
        return false
    end
    if metadata.mapper ~= nil and metadata.mapper ~= ""
        and normalizedCatalogText(metadata.mapper) ~= normalizedCatalogText(song.mapper) then
        return false
    end
    local requiredDifficulties = metadata.difficulties or {}
    if #requiredDifficulties > 0 then
        local available = song.difficulties or {}
        for _, required in ipairs(requiredDifficulties) do
            local found = false
            for _, candidate in ipairs(available) do
                if tonumber(required) ~= nil and tonumber(candidate) == tonumber(required) then
                    found = true
                    break
                end
            end
            if not found then return false end
        end
    end
    return true
end

function Api.discoverInstalledSongId(songFolder, metadata, options)
    options = options or {}
    if songFolder == nil or trim(songFolder) == "" then
        return setError("songFolder is required")
    end
    if type(metadata) ~= "table" or trim(metadata.title) == "" then
        return setError("song metadata with title is required")
    end

    local query = tostring(metadata.artist or "") .. " " .. tostring(metadata.title or "")
    local completed = false
    local function finish(id, err, result)
        if completed then return end
        completed = true
        if type(options.callback) == "function" then
            return options.callback(id, err, result)
        end
        return id, err, result
    end
    local function handleResults(songs, err)
        if err ~= nil then
            emit("installed.id.discovery.failed", { songFolder = songFolder, metadata = metadata, error = err })
            return finish(nil, err)
        end
        local matches = {}
        for _, song in ipairs(songs or {}) do
            if catalogSongMatchesMetadata(song, metadata) then
                table.insert(matches, song)
            end
        end
        if #matches ~= 1 then
            local discoveryError = {
                code = "song_id_unresolved",
                message = "catalog search did not uniquely resolve the loaded song",
                matches = #matches,
            }
            emit("installed.id.discovery.failed", {
                songFolder = songFolder,
                metadata = metadata,
                error = discoveryError,
            })
            return finish(nil, discoveryError)
        end
        local song = matches[1]
        local id = tonumber(song.id)
        local existingId = tonumber(options.existingId)
        local status = existingId ~= nil and existingId == id and "validated"
            or existingId ~= nil and "replaced"
            or "resolved"
        local writePath = joinPath(songFolder, ".id")
        if status ~= "validated" then
            local written, writeError
            written, writeError, writePath = Api.writeInstalledSongId(songFolder, id)
            if written == nil then
                local discoveryError = { code = "marker_write_failed", message = writeError, path = writePath }
                emit("installed.id.discovery.failed", {
                    songFolder = songFolder,
                    metadata = metadata,
                    error = discoveryError,
                })
                return finish(nil, discoveryError)
            end
        end
        local result = {
            id = id,
            previousId = existingId,
            path = writePath,
            song = song,
            metadata = metadata,
            status = status,
        }
        emit("installed.id.discovered", result)
        return finish(id, nil, result)
    end

    local request = Api.search(query, {
        page = options.page or 1,
        _onResult = handleResults,
    })
    if type(request) == "table" and not completed then
        handleResults(request, nil)
    end
    return request
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
        return Api.checkUpdates({ callback = function(remote, updateErr)
            if updateErr ~= nil then
                emit("installed.compare.failed", { error = updateErr })
                return nil, updateErr
            end
            local result = Api.compareInstalledWithUpdates({ updates = remote, songFolder = options.songFolder })
            emit("installed.compare.completed", result)
            return result
        end })
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

    local function loadHtmlDetail()
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

    if usesVaRest() and (not state.config.preferApi or options.html or seed.id == nil) then
        return setError("VaRest transport requires API song details")
    end
    if state.config.preferApi and not options.html and seed.id ~= nil then
        local detailPath = options.details and "/api/song/details/" or "/api/song/"
        emit("song.started", {
            song = seed,
            url = joinUrl(state.config.apiBaseUrl, detailPath .. tostring(seed.id)),
        })
        return fetchApiSongs(detailPath .. tostring(seed.id), function(apiSongs, apiErr)
            if apiErr ~= nil or apiSongs == nil or apiSongs[1] == nil then
                local err = apiErr or { code = "invalid_response", message = "song detail response was empty" }
                if not usesVaRest() then
                    state.lastError = err
                    return loadHtmlDetail()
                end
                emit("song.failed", { song = seed, error = err })
                if type(options._onResult) == "function" then options._onResult(nil, err) end
                return nil, err
            end
            local detail = mergeSong(seed, apiSongs[1])
            state.cache.byId[tostring(detail.id)] = detail
            emit("song.completed", { song = detail })
            if type(options._onResult) == "function" then options._onResult(detail, nil) end
            return detail
        end)
    end
    return loadHtmlDetail()
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
    local downloaded, err
    if type(state.config.downloadFile) == "function" then
        downloaded, err = state.config.downloadFile(urls.zip, zipPath, state.config, requestHeaders())
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
    local path = cleanDirection == "up" and "/api/song/" .. urlEncode(id) .. "/vote/up" or "/api/song/" .. urlEncode(id) .. "/vote/down"
    emit("vote.started", { id = id, direction = cleanDirection })
    return apiRequest("POST", path, "", function(response, err)
        if err ~= nil then
            emit("vote.failed", { id = id, direction = cleanDirection, error = err })
            return nil, err
        end
        local state, parseError = parseVoteState(response.body)
        if parseError ~= nil then
            emit("vote.failed", { id = id, direction = cleanDirection, error = parseError })
            return nil, parseError
        end
        emit("vote.completed", { id = id, direction = cleanDirection, response = state })
        return state
    end)
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
    archivePathIsSafe = archivePathIsSafe,
    parseAccount = parseAccount,
    parsePlaylistSearch = parsePlaylistSearch,
    parsePlaylistDetail = parsePlaylistDetail,
    parseVoteState = parseVoteState,
}

return Api
