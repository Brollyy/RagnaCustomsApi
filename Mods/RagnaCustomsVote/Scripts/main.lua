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

local function loadApiDependency()
    if type(Api) == "table" and type(Api.getVote) == "function" and type(Api.setVote) == "function" then
        return Api
    end

    local lastError = nil
    for _, path in ipairs({
        "Mods/RagnaCustomsApi/scripts/ragnacustoms_api.lua",
        "Mods/RagnaCustomsApi/Scripts/ragnacustoms_api.lua",
        "../RagnaCustomsApi/scripts/ragnacustoms_api.lua",
        "../RagnaCustomsApi/Scripts/ragnacustoms_api.lua",
    }) do
        local ok, loaded = pcall(dofile, path)
        if ok and type(loaded) == "table" then
            return loaded
        end
        lastError = loaded
    end
    return nil, lastError
end

Api = loadApiDependency()
if type(Api) ~= "table" or type(Api.getVote) ~= "function" or type(Api.setVote) ~= "function" then
    log("error", "RagnaCustomsApi >= 0.2.0 is required")
    return
end

local state = _G.__ragnaCustomsVoteState or {
    hooksInstalled = false,
    buttonHooksInstalled = false,
    beatmap = nil,
    custom = nil,
    panelPath = nil,
    mode = nil,
    widgets = nil,
    phase = "hidden",
    currentVote = nil,
    upvotes = 0,
    downvotes = 0,
    customScoresAllowed = nil,
    error = nil,
    pressed = { up = false, down = false },
    localTestOverride = nil,
}
_G.__ragnaCustomsVoteState = state
state.diagnostics = state.diagnostics or {}

local function applyLocalTestOverride()
    if io == nil or type(io.open) ~= "function" then
        return
    end
    for _, path in ipairs({
        "Mods/RagnaCustomsVote/scripts/local_test_override.lua",
        "Mods/RagnaCustomsVote/Scripts/local_test_override.lua",
    }) do
        local handle = io.open(path, "r")
        if handle ~= nil then
            handle:close()
            local ok, override = pcall(dofile, path)
            if ok and type(override) == "table" then
                if override.scoreEndpoint ~= nil then
                    Api.configure({ scoreEndpoint = override.scoreEndpoint })
                end
                if override.beatmap ~= nil then
                    state.beatmap = string.lower(tostring(override.beatmap))
                    state.custom = override.isCustom == true
                end
                state.localTestOverride = override
                log("info", "applied local test override")
            else
                log("error", "local test override could not be loaded")
            end
            return
        end
    end
end

applyLocalTestOverride()

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

local function asBoolean(value)
    value = unwrap(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    local text = string.lower(tostring(value or ""))
    if text == "true" or text == "1" then return true end
    if text == "false" or text == "0" then return false end
    return nil
end

local function customScoreSendingAllowed()
    if type(FindFirstOf) ~= "function" then return false end
    local classes = { "RagnarockGameInstance", "RagnarockGameInstance_C", "BP_GameInstance_Retail_C", "GameInstance_C", "RRGameInstance", "RRGameInstance_C", "RagnarockSaveGameSubsystem" }
    local methods = { "GetAllowSendingCustomSongScores", "GetAllowSendCustomSongScores", "GetAllowCustomSongScores", "GetAllowCustomScores", "IsAllowSendingCustomSongScores", "IsCustomSongScoreSendingAllowed" }
    local properties = { "AllowSendingCustomSongScores", "AllowSendCustomSongScores", "AllowCustomSongScores", "AllowCustomScores", "bAllowSendingCustomSongScores", "bAllowCustomSongScores" }
    for _, className in ipairs(classes) do
        local object = safeCall(function() return FindFirstOf(className) end, nil)
        if valid(object) then
            for _, method in ipairs(methods) do
                local result = asBoolean(safeCall(function() return object[method](object) end, nil))
                if result ~= nil then return result end
            end
            for _, property in ipairs(properties) do
                local result = asBoolean(safeCall(function() return object:GetPropertyValue(property) end, nil))
                if result ~= nil then return result end
            end
        end
    end
    -- Older builds do not expose this preference through UE4SS reflection. Keep
    -- the panel available in that case; an explicitly exposed false value above
    -- always suppresses it.
    return true
end

local function findActiveResultsPanel()
    if type(FindFirstOf) ~= "function" then
        return nil
    end
    for _, candidate in ipairs({
        { className = "FlatInGameEndPanel_C", mode = "flat" },
        { className = "VRInGameEndPanel_C", mode = "vr" },
        { className = "InGameEndPanel_C", mode = "vr" },
        { className = "InGameEndMenu_C", mode = "vr" },
    }) do
        local object = safeCall(function()
            return FindFirstOf(candidate.className)
        end, nil)
        local objectName = fullName(object)
        if valid(object)
            and objectName:find("/Engine/Transient.", 1, true) ~= nil
            and objectName:find("Default__", 1, true) == nil
            and visible(object) then
            return object, objectName, candidate.mode
        end
    end
    return nil
end

local function rootPath(panelName)
    return tostring(panelName or ""):match("(/Engine/Transient%..-InGameEnd.-_C_%d+)")
        or tostring(panelName or ""):match("(/Engine/Transient%..-EndPanel_C_%d+)")
        or tostring(panelName or "")
end

local function findCanvas(panel, panelPath, mode)
    local tree = safeCall(function()
        return panel.WidgetTree
    end, nil)
    local root = tree and safeCall(function()
        return tree.RootWidget
    end, nil) or nil
    if valid(root) then
        if not state.diagnostics.resultsRoot then
            state.diagnostics.resultsRoot = true
            log("info", "Results root candidate " .. fullName(root))
        end
        return root, tree
    end
    return nil
end

local function construct(classPath, outer, name)
    if type(StaticFindObject) ~= "function" or type(StaticConstructObject) ~= "function" then
        return nil
    end
    local class = safeCall(function()
        return StaticFindObject(classPath)
    end, nil)
    if class == nil then
        return nil
    end
    local objectName = 0
    if name ~= nil and type(FName) == "function" then
        objectName = safeCall(function()
            return FName(name)
        end, 0)
    end
    return safeCall(function()
        return StaticConstructObject(class, outer, objectName, 0, 0, nil, false, false, nil)
    end, nil)
end

local function setText(widget, value)
    if not valid(widget) then
        return false
    end
    local text = tostring(value or "")
    return safeCall(function()
        widget:SetText(FText(text))
        return true
    end, false)
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

local function findPlayerController(context)
    local controller = nil
    if type(UEHelpers) == "table" and type(UEHelpers.GetPlayerController) == "function" then
        controller = safeCall(function()
            return UEHelpers.GetPlayerController()
        end, nil)
    end
    if not valid(controller) and valid(context) then
        controller = safeCall(function()
            return context:GetOwningPlayer()
        end, nil)
    end
    if valid(controller) then
        return controller
    end
    return nil
end

local function createUserWidget(classPath, context)
    if type(StaticFindObject) ~= "function" then
        return nil
    end
    local library = safeCall(function()
        return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    end, nil)
    local class = safeCall(function()
        return StaticFindObject(classPath)
    end, nil)
    if not valid(library) or not valid(class) then
        return nil
    end
    local owner = findPlayerController(context)
    if not valid(owner) then
        log("error", "cannot create Results button: player controller unavailable")
        return nil
    end
    local widget = safeCall(function()
        return library:Create(owner, class, owner)
    end, nil)
    if not valid(widget) then
        log("error", "failed to create Results button widget class=" .. tostring(classPath))
        return nil
    end
    return widget
end

local function objectPath(object)
    local name = fullName(object)
    return name:match("^[^ ]+ (.+)$") or name
end

local function makeButton(canvas, context, mode, label, geometry)
    local classPath = mode == "vr"
        and "/Game/VRKeyboards/Blueprints/Keyboards/BasicPointAndClick/WBP_Button_Basic.WBP_Button_Basic_C"
        or "/Game/Flat/Blueprints/UI/InGame/FlatInGameButton.FlatInGameButton_C"
    local root = createUserWidget(classPath, context)
    if not valid(root) then
        return nil
    end
    local textProperty = mode == "vr" and "ButtonText" or "Text_"
    local childOk, child = pcall(function()
        return root:GetPropertyValue(textProperty)
    end)
    if not childOk or not valid(child) or not setText(child, label) then
        log("error", "failed to label stock Results button label=" .. tostring(label))
    end
    if not addToCanvas(canvas, root, geometry) then
        log("error", "failed to attach Results button widget label=" .. tostring(label))
        return nil
    end
    return {
        root = root,
        label = label,
        button = root,
        text = child,
        objectPath = objectPath(root),
    }
end

local function removeWidgets()
    local widgets = state.widgets
    if widgets ~= nil then
        for _, entry in pairs(widgets) do
            local widget = type(entry) == "table" and (entry.root or entry.button or entry.text) or entry
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

local function makeCount(canvas, label, geometry)
    local text = construct("/Script/UMG.TextBlock", canvas)
    if not valid(text) or not setText(text, label) or not addToCanvas(canvas, text, geometry) then
        return nil
    end
    return text
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
    setText(widgets.up.text, "▲")
    setText(widgets.down.text, "▼")
    setText(widgets.upCount, tostring(state.upvotes or 0))
    setText(widgets.downCount, tostring(state.downvotes or 0))
    safeCall(function() widgets.up.button:SetColorAndOpacity(state.currentVote == "up" and COLORS.up or COLORS.normal) end, nil)
    safeCall(function() widgets.down.button:SetColorAndOpacity(state.currentVote == "down" and COLORS.down or COLORS.normal) end, nil)
    local enabled = state.phase == "ready" or state.phase == "error"
    safeCall(function()
        widgets.up.button:SetIsEnabled(enabled)
        widgets.down.button:SetIsEnabled(enabled)
    end, nil)
    local status = "Vote for this custom song"
    if state.phase == "loading" then
        status = "Loading votes..."
    elseif state.phase == "submitting" then
        status = "Saving vote..."
    elseif state.phase == "error" then
        status = "Vote unavailable - press to retry"
    end
    if widgets.status ~= nil then setText(widgets.status.text, status) end
end

local function applyResponse(result)
    if state.widgets == nil then
        return
    end
    if result == nil or result.ok ~= true then
        state.phase = "error"
        state.error = result and result.error or { code = "unknown_error" }
        log("error", "vote response failed code=" .. tostring(state.error.code)
            .. " message=" .. tostring(state.error.message))
        render()
        return
    end
    state.phase = "ready"
    state.error = nil
    state.currentVote = result.state.currentVote
    state.upvotes = result.state.upvotes
    state.downvotes = result.state.downvotes
    log("info", "vote response applied current=" .. tostring(state.currentVote)
        .. " up=" .. tostring(state.upvotes) .. " down=" .. tostring(state.downvotes))
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
    local desired = direction
    if state.currentVote == direction then
        desired = nil
    end
    log("info", "vote submit current=" .. tostring(state.currentVote)
        .. " requested=" .. tostring(direction) .. " desired=" .. tostring(desired))
    state.phase = "submitting"
    render()
    local _, err = Api.setVote(state.beatmap, desired, applyResponse)
    if err ~= nil then
        applyResponse({ ok = false, error = { code = "start_failed", message = err } })
    end
end

local BUTTON_HANDLER_PATHS = {
    flat = "/Game/Flat/Blueprints/UI/InGame/FlatInGameButton.FlatInGameButton_C:"
        .. "BndEvt__FlatInGameButton_Button_64_K2Node_ComponentBoundEvent_0_OnButtonPressedEvent__DelegateSignature",
    vr = "/Game/VRKeyboards/Blueprints/Keyboards/BasicPointAndClick/WBP_Button_Basic.WBP_Button_Basic_C:"
        .. "BndEvt__Button_0_K2Node_ComponentBoundEvent_0_OnButtonPressedEvent__DelegateSignature",
}

local function voteDirectionForClickedButton(...)
    local widgets = state.widgets
    if widgets == nil then
        return nil
    end
    for index = 1, select("#", ...) do
        local clicked = unwrap(select(index, ...))
        if valid(clicked) then
            local clickedPath = objectPath(clicked)
            for _, direction in ipairs({ "up", "down" }) do
                local entry = widgets[direction]
                if entry ~= nil and clickedPath == entry.objectPath then
                    return direction
                end
            end
        end
    end
    return nil
end

local function installButtonHooks()
    if state.buttonHooksInstalled or type(RegisterHook) ~= "function" then
        return
    end
    local installed = false
    local function onButtonPressed(...)
        local direction = voteDirectionForClickedButton(...)
        if direction ~= nil then
            log("info", "Results vote button pressed direction=" .. direction)
            submit(direction)
        end
    end
    for _, handlerPath in pairs(BUTTON_HANDLER_PATHS) do
        if pcall(RegisterHook, handlerPath, onButtonPressed) then
            installed = true
        end
    end
    state.buttonHooksInstalled = installed
    if installed then
        log("info", "installed exact-instance Results vote button hooks")
    else
        log("error", "could not install Results vote button hooks")
    end
end

local function createWidgets(panel, panelPath, mode)
    local canvas = findCanvas(panel, panelPath, mode)
    if not valid(canvas) then
        if not state.diagnostics.canvasMissing then
            state.diagnostics.canvasMissing = true
            log("error", "Results panel found but no compatible CanvasPanel was found")
        end
        return false
    end
    local geometry = mode == "vr"
        and { x = 900, y = 400, width = 120, height = 46 }
        or { x = 900, y = 400, width = 120, height = 46 }
    local container = construct("/Script/UMG.CanvasPanel", canvas)
    log("info", "vote panel construct container begin")
    if not valid(container) or not addToCanvas(canvas, container, geometry) then
        if not state.diagnostics.containerFailed then
            state.diagnostics.containerFailed = true
            log("error", "failed to construct or attach standalone Results vote panel")
        end
        return false
    end
    log("info", "vote panel construct container done")
    local background = construct("/Script/UMG.Border", container)
    if valid(background) and addToCanvas(container, background, { x = 0, y = 0, width = 120, height = 46, z = 0 }) then
        setColor(background, { R = 0.04, G = 0.03, B = 0.05, A = 0.88 })
    else
        background = nil
    end
    log("info", "vote panel construct up begin")
    local up = makeButton(container, panel, mode, "▲", { x = 4, y = 4, width = 30, height = 38, z = 2 })
    log("info", "vote panel construct up done")
    local down = makeButton(container, panel, mode, "▼", { x = 66, y = 4, width = 30, height = 38, z = 2 })
    log("info", "vote panel construct down done")
    local upCount = makeCount(container, "0", { x = 38, y = 10, width = 22, height = 26, z = 2 })
    log("info", "vote panel construct up count done")
    local downCount = makeCount(container, "0", { x = 100, y = 10, width = 22, height = 26, z = 2 })
    log("info", "vote panel construct down count done")
    if up == nil or down == nil or upCount == nil or downCount == nil then
        if not state.diagnostics.buttonsFailed then
            state.diagnostics.buttonsFailed = true
            log("error", "failed to construct or attach Results vote buttons")
        end
        safeCall(function()
            container:RemoveFromParent()
        end, nil)
        return false
    end
    safeCall(function()
        up.button:SetIsEnabled(false)
        down.button:SetIsEnabled(false)
    end, nil)
    state.widgets = {
        container = container,
        background = background,
        status = nil,
        up = up,
        down = down,
        upCount = upCount,
        downCount = downCount,
    }
    state.panelPath = panelPath
    state.mode = mode
    state.phase = "hidden"
    state.currentVote = nil
    state.upvotes = 0
    state.downvotes = 0
    log("info", "created standalone " .. mode .. " Results vote panel")
    installButtonHooks()
    loadVote()
    return true
end

local function extractHash(...)
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        local unwrapped = unwrap(source)
        local direct = safeCall(function()
            return source:get()
        end, nil)
        local values = {
            unwrapped,
            direct,
            safeCall(function()
                return unwrapped:ToString()
            end, nil),
            safeCall(function()
                return direct:ToString()
            end, nil),
            safeCall(function()
                return source:ToString()
            end, nil),
        }
        for valueIndex = 1, 5 do
            local value = values[valueIndex]
            local text = tostring(value or "")
            local decimal = text:match("^(-?%d+)$")
            if decimal ~= nil then
                local numeric = tonumber(decimal)
                if numeric ~= nil and numeric >= -2147483648 and numeric < 0 then
                    numeric = numeric + 4294967296
                end
                if numeric ~= nil and numeric >= 0 and numeric <= 4294967295 and numeric % 1 == 0 then
                    return string.format("%.0f", numeric)
                end
            end
            local hash = text:match("^([0-9a-fA-F][0-9a-fA-F]+)$")
            if hash ~= nil and #hash >= 16 and #hash <= 64 then
                return string.lower(hash)
            end
        end
    end
    return nil
end

local extractBoolean

local function findPlayedSongManager()
    if type(FindFirstOf) ~= "function" then
        return nil
    end
    for _, className in ipairs({ "FlatBeatManager_C", "BeatManager_C", "BeatManager" }) do
        local manager = safeCall(function()
            return FindFirstOf(className)
        end, nil)
        local managerName = fullName(manager)
        if valid(manager)
            and managerName:find("/Engine/Transient.", 1, true) ~= nil
            and managerName:find("Default__", 1, true) == nil
            and managerName:find("Latency", 1, true) == nil then
            return manager, managerName
        end
    end
    return nil
end

local function resolvePlayedSongState(manager)
    if not valid(manager) then
        return false
    end
    local song = safeCall(function()
        return manager:GetSong()
    end, safeCall(function()
        return manager.m_song
    end, nil))
    local beatMap = safeCall(function()
        return manager:GetBeatMap()
    end, safeCall(function()
        return manager.m_beatMap
    end, nil))
    local rawCustom = song and safeCall(function()
        return song:IsCustom()
    end, nil) or nil
    local custom = extractBoolean(rawCustom)
    if custom ~= nil then
        state.custom = custom
    end
    if beatMap ~= nil then
        safeCall(function()
            beatMap:GetHash()
            return true
        end, false)
    end
    if state.custom ~= nil and state.beatmap ~= nil then
        if not state.diagnostics.playedSongResolved then
            state.diagnostics.playedSongResolved = true
            log("info", "resolved played song from BeatManager custom=" .. tostring(state.custom)
                .. " beatmap=" .. state.beatmap)
        end
        return true
    end
    return false
end

extractBoolean = function(...)
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
    local owners = { "SongsManager" }
    for _, owner in ipairs(owners) do
        installHook("/Script/Ragnarock." .. owner .. ":GetBeatMapHashFromCompositeId", function() end, hashPost)
        installHook("/Script/Ragnarock." .. owner .. ":IsCustomSong", function() end, customPost)
    end
    installHook("/Script/Ragnarock.BeatMap:GetHash", function() end, hashPost)
end

_G.RagnaCustomsVoteSetBeatmapHash = function(hash, isCustom)
    state.beatmap = hash and extractHash(hash) or nil
    state.custom = isCustom == true
end

local function poll()
    if not state.diagnostics.pollStarted then
        state.diagnostics.pollStarted = true
        log("info", "Results UI polling started")
    end
    if type(state.localTestOverride) == "table" and state.localTestOverride.beatmap ~= nil then
        state.beatmap = string.lower(tostring(state.localTestOverride.beatmap))
        state.custom = state.localTestOverride.isCustom == true
    end
    local panel, panelName, mode = findActiveResultsPanel()
    local manager, managerName = nil, nil
    if panel ~= nil then
        manager, managerName = findPlayedSongManager()
    end
    if panel ~= nil and manager ~= nil and not state.captureQueued
        and (state.captureManagerPath ~= managerName or state.captureResolved ~= true) then
        state.captureQueued = true
        local function captureOnGameThread()
            state.captureManagerPath = managerName
            state.captureResolved = resolvePlayedSongState(manager)
            state.captureQueued = false
        end
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(captureOnGameThread)
        else
            captureOnGameThread()
        end
        return
    end
    -- Reflected GameInstance getters are game-thread calls. Do not invoke them
    -- on every 500 ms poll during gameplay; probe once initially and again only
    -- when a new Results panel instance is observed.
    local panelPathForProbe = panel ~= nil and rootPath(panelName) or nil
    if state.customScoresAllowed == nil or (panelPathForProbe ~= nil and state.lastSettingPanelPath ~= panelPathForProbe) then
        state.customScoresAllowed = customScoreSendingAllowed()
        state.lastSettingPanelPath = panelPathForProbe
    end
    if state.customScoresAllowed ~= state.lastLoggedCustomScoresAllowed then
        state.lastLoggedCustomScoresAllowed = state.customScoresAllowed
        log("info", "custom score sending allowed=" .. tostring(state.customScoresAllowed))
    end
    if panel == nil or state.custom ~= true or state.beatmap == nil or state.customScoresAllowed ~= true then
        local reason = panel == nil and "no_results_panel"
            or state.custom ~= true and "song_not_custom"
            or state.beatmap == nil and "beatmap_unresolved"
            or "custom_score_sending_disabled"
        if reason ~= state.lastSuppressionReason then
            state.lastSuppressionReason = reason
            log("info", "vote panel suppressed reason=" .. reason)
        end
        if state.widgets ~= nil and panel == nil then
            removeWidgets()
        end
        return
    end
    state.lastSuppressionReason = nil
    if not state.diagnostics.panelFound then
        state.diagnostics.panelFound = true
        log("info", "found active " .. tostring(mode) .. " Results panel")
    end
    local path = rootPath(panelName)
    if state.widgets == nil or state.panelPath ~= path then
        if state.createQueued then
            return
        end
        state.createQueued = true
        local function createOnGameThread()
            if valid(panel) then
                removeWidgets()
                createWidgets(panel, path, mode)
            end
            state.createQueued = false
        end
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(createOnGameThread)
        else
            createOnGameThread()
        end
        return
    end
end

installHooks()
local function protectedPoll()
    local ok, err = pcall(poll)
    if not ok and not state.diagnostics.pollError then
        state.diagnostics.pollError = true
        log("error", "Results UI poll failed: " .. tostring(err))
    end
end
if type(LoopAsync) == "function" then
    LoopAsync(500, protectedPoll)
elseif type(ExecuteWithDelay) == "function" then
    local function delayedPoll()
        protectedPoll()
        ExecuteWithDelay(100, delayedPoll)
    end
    ExecuteWithDelay(100, delayedPoll)
else
    log("error", "UE4SS scheduler unavailable")
end

log("info", "loaded; waiting for a custom-song Results screen")
