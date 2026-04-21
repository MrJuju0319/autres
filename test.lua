-- =========================================================
-- Refined Storage Craft Monitor - Stoneblock 4
-- Pour CC:Tweaked + monitor + rs_bridge
-- =========================================================

local CONFIG = {
    monitorScale = 0.5,
    refreshInterval = 1,
    autoPageInterval = 5,
    title = "Refined Storage - Crafts en cours",
    showDebug = false,
    linesPerTask = 5
}

local bridge = peripheral.find("rs_bridge")
if not bridge then
    error("rs_bridge non detecte")
end

local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

mon.setTextScale(CONFIG.monitorScale)

local state = {
    page = 1,
    autoPage = true,
    lastAutoSwitch = os.clock()
}

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function monSize()
    return mon.getSize()
end

local function clear()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if maxLen <= 0 then return "" end
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function writeAt(x, y, text, fg, bg)
    local w, h = monSize()
    if y < 1 or y > h then return end
    if x < 1 then x = 1 end
    if bg then mon.setBackgroundColor(bg) else mon.setBackgroundColor(colors.black) end
    mon.setTextColor(fg or colors.white)
    mon.setCursorPos(x, y)
    mon.write(trim(text, w - x + 1))
    mon.setBackgroundColor(colors.black)
end

local function centerText(y, text, fg)
    local w = monSize()
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    writeAt(x, y, text, fg)
end

local function separator(y)
    local w = monSize()
    writeAt(1, y, string.rep("-", w), colors.gray)
end

local function callTask(task, method)
    if type(task) ~= "table" then return nil end
    if type(task[method]) ~= "function" then return nil end
    return safe(function() return task[method]() end)
end

local function getTasks()
    local tasks = safe(function() return bridge.getCraftingTasks() end)
    if type(tasks) ~= "table" then
        return {}
    end
    return tasks
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

local function getRequestedItem(task)
    local item = callTask(task, "getRequestedItem")
    if type(item) == "table" then return item end

    item = callTask(task, "getItem")
    if type(item) == "table" then return item end

    return nil
end

local function getDebug(task)
    local dbg = callTask(task, "getDebugMessage")
    if dbg == nil then return nil end
    dbg = tostring(dbg)
    if dbg == "" then return nil end
    return dbg
end

local function getItemName(task)
    local item = getRequestedItem(task)

    if type(item) == "table" then
        return item.displayName
            or item.display_name
            or item.name
            or item.id
            or item.item
            or "Item"
    end

    local status = select(1, getStatus(task))

    if status == "Attente" then
        return "[En attente de CPU]"
    elseif status == "Calcul" then
        return "[Calcul du craft]"
    elseif status == "Erreur" then
        return "[Craft en erreur]"
    elseif status == "Termine" then
        return "[Craft termine]"
    end

    local dbg = getDebug(task)
    if dbg then
        return "[" .. dbg .. "]"
    end

    return "[Item inconnu]"
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

local function percent(progress, total)
    if total <= 0 then return 0 end
    local p = math.floor((progress / total) * 100 + 0.5)
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end
    return p
end

local function drawBar(x, y, width, progress, total, fillColor, emptyColor)
    width = math.max(1, width)
    fillColor = fillColor or colors.green
    emptyColor = emptyColor or colors.gray

    local filled = 0
    if total > 0 then
        filled = math.floor((progress / total) * width + 0.5)
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

local function getPaging(taskCount)
    local _, h = monSize()
    local usable = h - 3
    local perPage = math.max(1, math.floor(usable / CONFIG.linesPerTask))
    local totalPages = math.max(1, math.ceil(taskCount / perPage))

    if state.page < 1 then state.page = 1 end
    if state.page > totalPages then state.page = totalPages end

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

local function drawHeader(taskCount, totalPages)
    local w = monSize()
    writeAt(1, 1, CONFIG.title, colors.cyan)

    local rightText = "Jobs: " .. taskCount .. " | Page " .. state.page .. "/" .. totalPages
    writeAt(math.max(1, w - #rightText + 1), 1, rightText, colors.lightGray)

    separator(2)
end

local function drawFooter()
    local w, h = monSize()
    local mode = state.autoPage and "AUTO" or "OFF"
    local footer = "[<] page prec   [>] page suiv   [A] auto:" .. mode
    writeAt(1, h, trim(footer, w), colors.gray)
end

local function drawEmpty()
    local _, h = monSize()
    centerText(math.max(4, math.floor(h / 2)), "Aucun craft en cours", colors.lime)
end

local function drawTask(y, idx, task)
    local w = monSize()

    local name = getItemName(task)
    local status, statusColor = getStatus(task)
    local progress, total = getProgress(task)
    local dbg = getDebug(task)
    local pct = percent(progress, total)

    writeAt(1, y, "[" .. idx .. "] " .. name, colors.yellow)
    y = y + 1

    writeAt(2, y, "Etat: " .. status, statusColor)
    y = y + 1

    local label
    if total <= 0 then
        label = "En attente"
    else
        label = progress .. "/" .. total .. " (" .. pct .. "%)"
    end

    local labelWidth = #label + 1
    local barWidth = math.max(10, w - 3 - labelWidth)

    if total <= 0 then
        drawBar(2, y, barWidth, 0, 1, colors.gray, colors.gray)
    else
        drawBar(2, y, barWidth, progress, total, colors.green, colors.gray)
    end

    writeAt(3 + barWidth, y, label, colors.white)
    y = y + 1

    if CONFIG.showDebug then
        writeAt(2, y, "Debug: " .. (dbg or "-"), colors.lightGray)
        y = y + 1
    end

    separator(y)
    return y + 1
end

local function render()
    clear()

    local tasks = getTasks()
    local perPage, totalPages = getPaging(#tasks)

    drawHeader(#tasks, totalPages)
    drawFooter()

    if #tasks == 0 then
        drawEmpty()
        return
    end

    local startIndex = ((state.page - 1) * perPage) + 1
    local endIndex = math.min(#tasks, startIndex + perPage - 1)

    local y = 3
    for i = startIndex, endIndex do
        y = drawTask(y, i, tasks[i])
    end
end

local function handleTouch(x, y)
    local w, h = monSize()
    if y ~= h then return end

    local tasks = getTasks()
    local _, totalPages = getPaging(#tasks)

    if x <= math.floor(w / 3) then
        state.autoPage = false
        prevPage(totalPages)
    elseif x <= math.floor((w / 3) * 2) then
        state.autoPage = not state.autoPage
    else
        state.autoPage = false
        nextPage(totalPages)
    end

    state.lastAutoSwitch = os.clock()
end

local function renderLoop()
    while true do
        render()
        sleep(CONFIG.refreshInterval)
    end
end

local function autoPageLoop()
    while true do
        sleep(0.2)

        if state.autoPage and (os.clock() - state.lastAutoSwitch >= CONFIG.autoPageInterval) then
            local tasks = getTasks()
            local _, totalPages = getPaging(#tasks)

            if totalPages > 1 then
                nextPage(totalPages)
            end

            state.lastAutoSwitch = os.clock()
        end
    end
end

local function eventLoop()
    while true do
        local ev, side, x, y = os.pullEvent()

        if ev == "monitor_touch" then
            handleTouch(x, y)
        elseif ev == "rs_crafting" then
            state.lastAutoSwitch = os.clock()
        elseif ev == "monitor_resize" then
            state.lastAutoSwitch = os.clock()
        end
    end
end

parallel.waitForAny(renderLoop, autoPageLoop, eventLoop)
