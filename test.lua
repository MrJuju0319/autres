-- ================================
-- Refined Storage Craft Monitor
-- Version avancee pour CC:Tweaked
-- Compatible setup avec rs_bridge + monitor
-- ================================

-- ========= CONFIG =========
local CONFIG = {
    monitorTextScale = 0.5,
    refreshInterval = 1.0,     -- refresh visuel
    autoPageInterval = 5.0,    -- changement auto de page
    linesPerTask = 5,          -- nombre de lignes par craft
    showDebugLine = true,      -- affiche message debug si dispo
    enableTouchControls = true,
    title = "Refined Storage - Crafts en cours",
}

-- ========= DETECTION =========
local bridge = peripheral.find("rs_bridge")
if not bridge then
    error("rs_bridge non detecte")
end

local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

mon.setTextScale(CONFIG.monitorTextScale)

-- ========= ETAT =========
local state = {
    page = 1,
    autoPage = true,
    lastPageSwitch = os.clock(),
    lastRefresh = 0,
    selectedPage = 1,
}

-- ========= UTILS =========
local function safe(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function clear()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function size()
    return mon.getSize()
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if maxLen <= 0 then return "" end
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function centerText(y, text, color)
    local w = size()
    text = tostring(text or "")
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    mon.setCursorPos(x, y)
    mon.setTextColor(color or colors.white)
    mon.write(trim(text, w))
end

local function writeAt(x, y, text, color, bg)
    local w, h = size()
    if y < 1 or y > h then return end
    if x < 1 then x = 1 end
    if bg then mon.setBackgroundColor(bg) end
    mon.setCursorPos(x, y)
    mon.setTextColor(color or colors.white)
    mon.write(trim(text, w - x + 1))
    mon.setBackgroundColor(colors.black)
end

local function fillLine(y, bg)
    local w = size()
    mon.setCursorPos(1, y)
    mon.setBackgroundColor(bg or colors.black)
    mon.write(string.rep(" ", w))
    mon.setBackgroundColor(colors.black)
end

local function drawSeparator(y)
    local w = size()
    writeAt(1, y, string.rep("-", w), colors.gray)
end

local function percent(a, b)
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    if b <= 0 then return 0 end
    local p = math.floor((a / b) * 100 + 0.5)
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end
    return p
end

local function drawBar(x, y, width, value, total, fillColor, emptyColor)
    width = math.max(1, width)
    value = tonumber(value) or 0
    total = tonumber(total) or 0
    fillColor = fillColor or colors.green
    emptyColor = emptyColor or colors.gray

    local filled = 0
    if total > 0 then
        filled = math.floor((value / total) * width + 0.5)
        if filled < 0 then filled = 0 end
        if filled > width then filled = width end
    end

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(emptyColor)
    mon.write(string.rep(" ", width))

    if filled > 0 then
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(fillColor)
        mon.write(string.rep(" ", filled))
    end

    mon.setBackgroundColor(colors.black)
end

local function shallowToString(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, val in pairs(v) do
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(val)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- ========= LECTURE DES DONNEES =========
local function getTasks()
    local tasks = safe(function() return bridge.getCraftingTasks() end)
    if type(tasks) ~= "table" then
        return {}
    end
    return tasks
end

local function callTask(task, methodName)
    if type(task) ~= "table" then return nil end
    if type(task[methodName]) ~= "function" then return nil end
    return safe(function() return task[methodName]() end)
end

local function getRequestedItem(task)
    local item = callTask(task, "getRequestedItem")
    if type(item) == "table" then return item end

    item = callTask(task, "getItem")
    if type(item) == "table" then return item end

    return nil
end

local function getItemName(task)
    local item = getRequestedItem(task)

    if type(item) == "table" then
        return item.displayName
            or item.display_name
            or item.name
            or item.id
            or item.item
            or item.fingerprint
            or shallowToString(item)
    end

    local dbg = callTask(task, "getDebugMessage")
    if dbg and dbg ~= "" then
        return tostring(dbg)
    end

    return "Item inconnu"
end

local function getProgress(task)
    local progress = callTask(task, "getItemProgress")
    if progress == nil then
        progress = callTask(task, "getProgress")
    end
    if progress == nil then
        progress = 0
    end

    local total = callTask(task, "getTotalItems")
    if total == nil then
        total = callTask(task, "getTotalItemCount")
    end
    if total == nil then
        total = callTask(task, "getTotal")
    end
    if total == nil then
        total = 0
    end

    return tonumber(progress) or 0, tonumber(total) or 0
end

local function getStatus(task)
    if callTask(task, "isCanceled") then
        return "Annule", colors.red
    end

    if callTask(task, "hasErrorOccurred") then
        return "Erreur", colors.red
    end

    if callTask(task, "isDone") then
        return "Termine", colors.lime
    end

    if callTask(task, "isCraftingStarted") then
        return "En cours", colors.yellow
    end

    if callTask(task, "isCalculationStarted") then
        return "Calcul", colors.orange
    end

    return "Attente", colors.lightGray
end

local function getDebug(task)
    local dbg = callTask(task, "getDebugMessage")
    if dbg == nil then return nil end
    dbg = tostring(dbg)
    if dbg == "" then return nil end
    return dbg
end

local function getTaskSummary(task, index)
    local name = getItemName(task)
    local progress, total = getProgress(task)
    local status, statusColor = getStatus(task)
    local dbg = getDebug(task)

    local pct = percent(progress, total)

    return {
        index = index,
        name = name,
        progress = progress,
        total = total,
        percent = pct,
        status = status,
        statusColor = statusColor,
        debug = dbg,
    }
end

-- ========= PAGINATION =========
local function getPageInfo(taskCount)
    local _, h = size()
    local usableLines = h - 3 -- titre + ligne + footer
    local perPage = math.max(1, math.floor(usableLines / CONFIG.linesPerTask))
    local totalPages = math.max(1, math.ceil(taskCount / perPage))
    if state.page > totalPages then state.page = totalPages end
    if state.page < 1 then state.page = 1 end
    return perPage, totalPages
end

local function nextPage(totalPages)
    state.page = state.page + 1
    if state.page > totalPages then
        state.page = 1
    end
end

local function prevPage(totalPages)
    state.page = state.page - 1
    if state.page < 1 then
        state.page = totalPages
    end
end

-- ========= RENDU =========
local function drawHeader(taskCount, totalPages)
    local w = size()
    fillLine(1, colors.black)
    writeAt(1, 1, CONFIG.title, colors.cyan)
    drawSeparator(2)

    local info = "Jobs: " .. tostring(taskCount) .. " | Page " .. tostring(state.page) .. "/" .. tostring(totalPages)
    writeAt(math.max(1, w - #info + 1), 1, info, colors.lightGray)
end

local function drawFooter()
    local w, h = size()
    fillLine(h, colors.black)

    local mode = state.autoPage and "AUTO" or "MANUEL"
    local footer = "[<] page prec   [>] page suiv   [A] auto:" .. mode
    writeAt(1, h, trim(footer, w), colors.gray)
end

local function drawTask(y, summary)
    local w = size()

    writeAt(1, y, "[" .. summary.index .. "] " .. tostring(summary.name), colors.yellow)
    y = y + 1

    writeAt(2, y, "Etat: " .. summary.status, summary.statusColor)
    y = y + 1

    local label = tostring(summary.progress) .. "/" .. tostring(summary.total) .. " (" .. tostring(summary.percent) .. "%)"
    local labelWidth = #label + 1
    local barWidth = math.max(10, w - 3 - labelWidth)

    drawBar(2, y, barWidth, summary.progress, summary.total, colors.green, colors.gray)
    writeAt(3 + barWidth, y, label, colors.white)
    y = y + 1

    if CONFIG.showDebugLine then
        local dbg = summary.debug or "-"
        writeAt(2, y, "Debug: " .. dbg, colors.lightGray)
        y = y + 1
    end

    drawSeparator(y)
    return y + 1
end

local function drawNoTasks()
    local _, h = size()
    centerText(math.max(4, math.floor(h / 2)), "Aucun craft en cours", colors.lime)
end

local function render()
    clear()

    local tasks = getTasks()
    local taskCount = #tasks
    local perPage, totalPages = getPageInfo(taskCount)

    drawHeader(taskCount, totalPages)
    drawFooter()

    if taskCount == 0 then
        drawNoTasks()
        return
    end

    local startIndex = ((state.page - 1) * perPage) + 1
    local endIndex = math.min(taskCount, startIndex + perPage - 1)

    local y = 3
    for i = startIndex, endIndex do
        local summary = getTaskSummary(tasks[i], i)
        y = drawTask(y, summary)
    end
end

-- ========= CONTROLES TACTILES =========
local function handleTouch(x, y)
    if not CONFIG.enableTouchControls then return end

    local w, h = size()
    if y ~= h then return end

    local tasks = getTasks()
    local _, totalPages = getPageInfo(#tasks)

    -- zones simples :
    -- gauche = page precedente
    -- centre = auto on/off
    -- droite = page suivante
    if x <= math.floor(w / 3) then
        state.autoPage = false
        prevPage(totalPages)
    elseif x <= math.floor((w / 3) * 2) then
        state.autoPage = not state.autoPage
    else
        state.autoPage = false
        nextPage(totalPages)
    end
end

-- ========= BOUCLES =========
local function renderLoop()
    while true do
        render()
        sleep(CONFIG.refreshInterval)
    end
end

local function autoPageLoop()
    while true do
        sleep(0.2)

        if state.autoPage and (os.clock() - state.lastPageSwitch >= CONFIG.autoPageInterval) then
            local tasks = getTasks()
            local _, totalPages = getPageInfo(#tasks)
            if totalPages > 1 then
                nextPage(totalPages)
            end
            state.lastPageSwitch = os.clock()
        end
    end
end

local function eventLoop()
    while true do
        local ev, side, x, y = os.pullEvent()

        if ev == "monitor_touch" then
            handleTouch(x, y)
            state.lastPageSwitch = os.clock()
        elseif ev == "rs_crafting" then
            state.lastPageSwitch = os.clock()
        elseif ev == "monitor_resize" then
            state.lastPageSwitch = os.clock()
        end
    end
end

parallel.waitForAny(renderLoop, autoPageLoop, eventLoop)
