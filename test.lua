-- startup.lua
-- Affiche les crafts Refined Storage en cours sur un monitor
-- Setup valide pour ton cas :
--   top   = rs_bridge
--   right = monitor

local bridge = peripheral.find("rs_bridge")
if not bridge then
    error("rs_bridge non detecte")
end

local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

mon.setTextScale(0.5)

local function safe(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

local function clear()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    return text:sub(1, math.max(1, maxLen - 3)) .. "..."
end

local function getRequestedName(task)
    local item = safe(function() return task.getRequestedItem() end)
    if type(item) == "table" then
        return item.displayName or item.display_name or item.name or item.id or "Item inconnu"
    end
    return "Item inconnu"
end

local function getStatus(task)
    if safe(function() return task.isCanceled() end) then
        return "Annule", colors.red
    end
    if safe(function() return task.hasErrorOccurred() end) then
        return "Erreur", colors.red
    end
    if safe(function() return task.isDone() end) then
        return "Termine", colors.lime
    end
    if safe(function() return task.isCraftingStarted() end) then
        return "En cours", colors.yellow
    end
    if safe(function() return task.isCalculationStarted() end) then
        return "Calcul", colors.orange
    end
    return "Attente", colors.lightGray
end

local function drawBar(x, y, width, value, total)
    value = tonumber(value) or 0
    total = tonumber(total) or 0

    if total <= 0 then
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(colors.gray)
        mon.write(string.rep(" ", width))
        mon.setBackgroundColor(colors.black)
        return
    end

    local filled = math.floor((value / total) * width + 0.5)
    if filled > width then filled = width end
    if filled < 0 then filled = 0 end

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ", width))

    if filled > 0 then
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(colors.green)
        mon.write(string.rep(" ", filled))
    end

    mon.setBackgroundColor(colors.black)
end

local scroll = 1

local function draw()
    clear()

    local w, h = mon.getSize()
    local tasks = safe(function() return bridge.getCraftingTasks() end) or {}

    mon.setTextColor(colors.cyan)
    mon.setCursorPos(1, 1)
    mon.write(trim("Refined Storage - Crafts en cours", w))

    mon.setTextColor(colors.gray)
    mon.setCursorPos(1, 2)
    mon.write(string.rep("-", w))

    if #tasks == 0 then
        mon.setTextColor(colors.lime)
        mon.setCursorPos(1, 4)
        mon.write(trim("Aucun craft en cours", w))
        return
    end

    local linesPerTask = 4
    local usableLines = h - 2
    local maxVisible = math.max(1, math.floor(usableLines / linesPerTask))

    if scroll > #tasks then scroll = 1 end
    local last = math.min(#tasks, scroll + maxVisible - 1)

    local y = 3
    for i = scroll, last do
        local task = tasks[i]

        local name = getRequestedName(task)
        local progress = safe(function() return task.getItemProgress() end) or 0
        local total = safe(function() return task.getTotalItems() end) or 0
        local status, statusColor = getStatus(task)

        mon.setCursorPos(1, y)
        mon.setTextColor(colors.yellow)
        mon.write(trim("[" .. i .. "] " .. name, w))
        y = y + 1

        mon.setCursorPos(2, y)
        mon.setTextColor(statusColor)
        mon.write(trim("Etat: " .. status, w - 1))
        y = y + 1

        local barWidth = math.max(10, w - 14)
        drawBar(2, y, barWidth, progress, total)
        mon.setCursorPos(math.min(w - 10, barWidth + 3), y)
        mon.setTextColor(colors.white)
        mon.write(trim(tostring(progress) .. "/" .. tostring(total), 10))
        y = y + 1

        mon.setCursorPos(1, y)
        mon.setTextColor(colors.gray)
        mon.write(string.rep("-", w))
        y = y + 1
    end

    mon.setCursorPos(1, h)
    mon.setTextColor(colors.lightGray)
    mon.write(trim("Jobs: " .. #tasks .. " | Page auto", w))
end

local function autoScrollLoop()
    while true do
        local tasks = safe(function() return bridge.getCraftingTasks() end) or {}
        local _, h = mon.getSize()
        local maxVisible = math.max(1, math.floor((h - 2) / 4))

        if #tasks > maxVisible then
            scroll = scroll + maxVisible
            if scroll > #tasks then
                scroll = 1
            end
        else
            scroll = 1
        end

        sleep(4)
    end
end

local function refreshLoop()
    while true do
        draw()
        sleep(1)
    end
end

parallel.waitForAny(refreshLoop, autoScrollLoop)
