local function log(message)
    local line = "[RagnaCustomsApi] " .. tostring(message)
    if print then
        print(line .. "\n")
    end
end

local function normalizeSlashes(path)
    return tostring(path or ""):gsub("\\", "/")
end

local function dirname(path)
    return normalizeSlashes(path):match("^(.*)/[^/]*$") or "."
end

local scriptPath = nil
local scriptDir = nil
local win64Dir = nil
local gameDir = nil

local function writeLoadMarker(api)
    if scriptDir == nil or io == nil or type(io.open) ~= "function" then
        return
    end
    local markerPath = scriptDir .. "/RagnaCustomsApi.loaded"
    local handle = io.open(markerPath, "w")
    if handle == nil then
        return
    end
    handle:write("version=" .. tostring(api.VERSION) .. "\n")
    handle:write("scriptPath=" .. tostring(scriptPath) .. "\n")
    handle:write("scriptDir=" .. tostring(scriptDir) .. "\n")
    handle:write("win64Dir=" .. tostring(win64Dir) .. "\n")
    handle:write("gameDir=" .. tostring(gameDir) .. "\n")
    handle:close()
end

local candidates = {
    "Mods/RagnaCustomsApi/Scripts/ragnacustoms_api.lua",
    "ragnacustoms_api.lua",
}

if debug and debug.getinfo then
    local source = debug.getinfo(1, "S").source
    if type(source) == "string" and source:sub(1, 1) == "@" then
        scriptPath = normalizeSlashes(source:sub(2))
        scriptDir = dirname(scriptPath)
        win64Dir = scriptPath:match("^(.*)/ue4ss/[Mm]ods/RagnaCustomsApi/[Ss]cripts/main%.lua$")
            or scriptPath:match("^(.*)/[Mm]ods/RagnaCustomsApi/[Ss]cripts/main%.lua$")
        gameDir = scriptPath:match("^(.*)/Ragnarock/Binaries/Win64/ue4ss/[Mm]ods/RagnaCustomsApi/[Ss]cripts/main%.lua$")
            or scriptPath:match("^(.*)/Ragnarock/Binaries/Win64/[Mm]ods/RagnaCustomsApi/[Ss]cripts/main%.lua$")
        table.insert(candidates, scriptDir .. "/ragnacustoms_api.lua")
    end
end

local ok = false
local apiOrError = nil
for _, candidate in ipairs(candidates) do
    ok, apiOrError = pcall(dofile, candidate)
    if ok then
        break
    end
end

if not ok then
    log("failed to load library: " .. tostring(apiOrError))
    return
end

_G.RagnaCustomsApi = apiOrError
_G.RagnaCustoms = apiOrError

if type(apiOrError.setRuntimePaths) == "function" then
    apiOrError.setRuntimePaths({
        scriptPath = scriptPath,
        scriptDir = scriptDir,
        win64Dir = win64Dir,
        gameDir = gameDir,
    })
end

writeLoadMarker(apiOrError)
log("loaded " .. tostring(apiOrError.VERSION))
