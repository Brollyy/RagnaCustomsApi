local MOD_NAME = "RagnaCustomsVote"
local Api = _G.RagnaCustomsApi or _G.RagnaCustoms

local function log(level, message)
    local line = string.format("[%s] [%s] %s", MOD_NAME, tostring(level), tostring(message))
    if type(_G.Ragna) == "table" and type(_G.Ragna.log) == "function" then
        _G.Ragna.log(level, message)
    elseif print then
        print(line .. "\n")
    end
end

if type(Api) ~= "table" or type(Api.getVote) ~= "function" or type(Api.setVote) ~= "function" then
    log("error", "RagnaCustomsApi >= 0.2.0 is required")
    return
end

local state = _G.__ragnaCustomsVoteState or {
    hooksInstalled = false,
    beatmap = nil,
    custom = nil,
    panelPath = nil,
    mode = nil,
    widgets = nil,
    phase = "hidden",
    currentVote = nil,
    upvotes = 0,
    downvotes = 0,
    error = nil,
    pressed = { up = false, down = false },
}
_G.__ragnaCustomsVoteState = state

local function safeCall(callback, fallback)
    local ok, result = pcall(callback)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

local function unwrap(value)
    if value ~= nil and type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" then
        local ok, getter = pcall(function()
            return value.get
        end)
        if ok and type(getter) == "function" then
            return safeCall(function()
                return value:get()
            end, value)
        end
    end
    return value
end

local function valid(object)
    if object == nil then
        return false
    end
    return safeCall(function()
        return object:IsValid()
    end, true)
end

local function fullName(object)
    return safeCall(function()
        return object:GetFullName()
    end, tostring(object))
end

local function visible(object)
    return valid(object) and safeCall(function()
        return object:IsVisible()
    end, true)
end

local function findActiveResultsPanel()
    if type(FindAllOf) ~= "function" then
        return nil
    end
    local objects = safeCall(function()
        return FindAllOf("UserWidget")
    end, {})
    for _, object in ipairs(objects or {}) do
        local name = fullName(object)
        local isFlat = name:find("FlatInGameEndPanel_C_", 1, true) ~= nil
        local isVr = not isFlat and (
            name:find("VRInGameEnd", 1, true) ~= nil
            or name:find("InGameEndPanel_C_", 1, true) ~= nil
            or name:find("InGameEndMenu_C_", 1, true) ~= nil
        )
        if (isFlat or isVr) and visible(object) then
            return object, name, isFlat and "flat" or "vr"
        end
    end
    return nil
end

local function rootPath(panelName)
    return tostring(panelName or ""):match("(/Engine/Transient%..-InGameEnd.-_C_%d+)")
        or tostring(panelName or ""):match("(/Engine/Transient%..-EndPanel_C_%d+)")
        or tostring(panelName or "")
end

local function findCanvas(panelPath, mode)
    local canvases = safeCall(function()
        return FindAllOf("CanvasPanel")
    end, {})
    local fallback = nil
    for _, canvas in ipairs(canvases or {}) do
        if valid(canvas) then
            local name = fullName(canvas)
            if name:find(panelPath, 1, true) ~= nil and name:find("Leaderboard", 1, true) == nil then
                if mode == "flat" and name:find("FlatItem_PlayerStats_C_0", 1, true) ~= nil then
                    return canvas
                end
                fallback = fallback or canvas
            end
        end
    end
    return fallback
end

local function construct(classPath, outer)
    if type(StaticFindObject) ~= "function" or type(StaticConstructObject) ~= "function" then
        return nil
    end
    local class = safeCall(function()
        return StaticFindObject(classPath)
    end, nil)
    if class == nil then
        return nil
    end
    return safeCall(function()
        return StaticConstructObject(class, outer, 0, 0, 0, nil, false, false, nil)
    end, nil)
end

local function setText(widget, value)
    if not valid(widget) then
        return
    end
    local text = tostring(value or "")
    local applied = false
    if type(FText) == "function" then
        applied = safeCall(function()
            widget:SetText(FText(text))
            return true
        end, false)
    end
    if not applied then
        safeCall(function()
            widget:SetText(text)
        end, nil)
    end
    safeCall(function()
        widget:SynchronizeProperties()
        widget:InvalidateLayoutAndVolatility()
    end, nil)
end

local function setColor(widget, color)
    safeCall(function()
        widget:SetColorAndOpacity(color)
    end, nil)
    safeCall(function()
        widget:SetBackgroundColor(color)
    end, nil)
end

local function addToCanvas(canvas, widget, geometry)
    local slot = safeCall(function()
        return canvas:AddChildToCanvas(widget)
    end, nil)
    if not valid(slot) then
        return false
    end
    safeCall(function()
        slot:SetAutoSize(false)
        slot:SetPosition({ X = geometry.x, Y = geometry.y })
        slot:SetSize({ X = geometry.width, Y = geometry.height })
        slot:SetZOrder(geometry.z or 9000)
    end, nil)
    return true
end

local function makeButton(canvas, label, geometry)
    local button = construct("/Script/UMG.Button", canvas)
    local text = construct("/Script/UMG.TextBlock", button)
    if not valid(button) or not valid(text) or not addToCanvas(canvas, button, geometry) then
        return nil
    end
    safeCall(function()
        button:AddChild(text)
        button:SetIsEnabled(true)
        button:SetVisibility(0)
        text:SetJustification(1)
        text:SetMinDesiredWidth(geometry.width - 12)
    end, nil)
    setText(text, label)
    return { button = button, text = text }
end

local function removeWidgets()
    local widgets = state.widgets
    if widgets ~= nil then
        for _, entry in pairs(widgets) do
            local widget = type(entry) == "table" and (entry.button or entry.text) or entry
            if valid(widget) then
                safeCall(function()
                    widget:RemoveFromParent()
                end, nil)
            end
        end
    end
    state.widgets = nil
    state.panelPath = nil
    state.phase = "hidden"
    state.pressed = { up = false, down = false }
end

local COLORS = {
    normal = { R = 0.82, G = 0.86, B = 0.92, A = 1.0 },
    up = { R = 0.25, G = 1.0, B = 0.42, A = 1.0 },
    down = { R = 1.0, G = 0.32, B = 0.32, A = 1.0 },
    disabled = { R = 0.52, G = 0.56, B = 0.62, A = 1.0 },
}

local function render()
    local widgets = state.widgets
    if widgets == nil then
        return
    end
    setText(widgets.up.text, string.format("UP  %d", tonumber(state.upvotes) or 0))
    setText(widgets.down.text, string.format("DOWN  %d", tonumber(state.downvotes) or 0))
    local enabled = state.phase == "ready" or state.phase == "error"
    safeCall(function()
        widgets.up.button:SetIsEnabled(enabled)
        widgets.down.button:SetIsEnabled(enabled)
    end, nil)
    setColor(widgets.up.text, state.currentVote == "up" and COLORS.up or (enabled and COLORS.normal or COLORS.disabled))
    setColor(widgets.down.text, state.currentVote == "down" and COLORS.down or (enabled and COLORS.normal or COLORS.disabled))
    local status = "Vote for this custom song"
    if state.phase == "loading" then
        status = "Loading votes..."
    elseif state.phase == "submitting" then
        status = "Saving vote..."
    elseif state.phase == "error" then
        status = "Vote unavailable - press to retry"
    end
    setText(widgets.status, status)
end

local function applyResponse(result)
    if state.widgets == nil then
        return
    end
    if result == nil or result.ok ~= true then
        state.phase = "error"
        state.error = result and result.error or { code = "unknown_error" }
        render()
        return
    end
    state.phase = "ready"
    state.error = nil
    state.currentVote = result.state.currentVote
    state.upvotes = result.state.upvotes
    state.downvotes = result.state.downvotes
    render()
end

local function loadVote()
    state.phase = "loading"
    render()
    local _, err = Api.getVote(state.beatmap, applyResponse)
    if err ~= nil then
        applyResponse({ ok = false, error = { code = "start_failed", message = err } })
    end
end

local function submit(direction)
    if state.phase ~= "ready" and state.phase ~= "error" then
        return
    end
    local desired = state.currentVote == direction and nil or direction
    state.phase = "submitting"
    render()
    local _, err = Api.setVote(state.beatmap, desired, applyResponse)
    if err ~= nil then
        applyResponse({ ok = false, error = { code = "start_failed", message = err } })
    end
end

local function createWidgets(panelPath, mode)
    local canvas = findCanvas(panelPath, mode)
    if not valid(canvas) then
        return false
    end
    local y = mode == "vr" and 360 or 206
    local status = construct("/Script/UMG.TextBlock", canvas)
    if not valid(status) or not addToCanvas(canvas, status, { x = 22, y = y, width = 390, height = 34 }) then
        return false
    end
    local up = makeButton(canvas, "UP", { x = 22, y = y + 38, width = 185, height = 52 })
    local down = makeButton(canvas, "DOWN", { x = 218, y = y + 38, width = 185, height = 52 })
    if up == nil or down == nil then
        safeCall(function()
            status:RemoveFromParent()
        end, nil)
        return false
    end
    state.widgets = { status = status, up = up, down = down }
    state.panelPath = panelPath
    state.mode = mode
    state.currentVote = nil
    state.upvotes = 0
    state.downvotes = 0
    loadVote()
    log("info", "created " .. mode .. " Results vote controls")
    return true
end

local function extractHash(...)
    for index = 1, select("#", ...) do
        local value = unwrap(select(index, ...))
        local text = tostring(value or "")
        local hash = text:match("^([0-9a-fA-F][0-9a-fA-F]+)$")
        if hash ~= nil and #hash >= 16 and #hash <= 64 then
            return string.lower(hash)
        end
    end
    return nil
end

local function extractBoolean(...)
    for index = select("#", ...), 1, -1 do
        local value = unwrap(select(index, ...))
        if type(value) == "boolean" then
            return value
        end
        if type(value) == "number" and (value == 0 or value == 1) then
            return value == 1
        end
    end
    return nil
end

local function installHook(name, pre, post)
    if type(RegisterHook) ~= "function" then
        return false
    end
    local ok
    if post ~= nil then
        ok = pcall(RegisterHook, name, pre, post)
    else
        ok = pcall(RegisterHook, name, pre)
    end
    return ok
end

local function installHooks()
    if state.hooksInstalled then
        return
    end
    state.hooksInstalled = true
    installHook("/Script/Ragnarock.Boat:OnStartSong", function()
        removeWidgets()
        state.beatmap = nil
        state.custom = nil
    end, nil)
    local hashPost = function(...)
        local hash = extractHash(...)
        if hash ~= nil then
            state.beatmap = hash
        end
    end
    local customPost = function(...)
        local custom = extractBoolean(...)
        if custom ~= nil then
            state.custom = custom
        end
    end
    local owners = { "RagnarockGameInstance", "RagnaGameInstance", "RagnarockBlueprintFunctionLibrary" }
    for _, owner in ipairs(owners) do
        installHook("/Script/Ragnarock." .. owner .. ":GetBeatMapHashFromCompositeId", function() end, hashPost)
        installHook("/Script/Ragnarock." .. owner .. ":IsCustomSong", function() end, customPost)
    end
end

_G.RagnaCustomsVoteSetBeatmapHash = function(hash, isCustom)
    state.beatmap = hash and string.lower(tostring(hash)) or nil
    state.custom = isCustom == true
end

local function poll()
    local panel, panelName, mode = findActiveResultsPanel()
    if panel == nil or state.custom ~= true or state.beatmap == nil then
        if state.widgets ~= nil and panel == nil then
            removeWidgets()
        end
        return
    end
    local path = rootPath(panelName)
    if state.widgets == nil or state.panelPath ~= path then
        removeWidgets()
        createWidgets(path, mode)
        return
    end
    for _, direction in ipairs({ "up", "down" }) do
        local button = state.widgets[direction].button
        local pressed = safeCall(function()
            return button:IsPressed()
        end, false) == true
        if pressed and not state.pressed[direction] then
            submit(direction)
        end
        state.pressed[direction] = pressed
    end
end

installHooks()
if type(LoopAsync) == "function" then
    LoopAsync(100, poll)
elseif type(ExecuteWithDelay) == "function" then
    local function delayedPoll()
        poll()
        ExecuteWithDelay(100, delayedPoll)
    end
    ExecuteWithDelay(100, delayedPoll)
else
    log("error", "UE4SS scheduler unavailable")
end

log("info", "loaded; waiting for a custom-song Results screen")
