-- rs_debug_monitor.lua
-- Affiche les infos de debug du rs_bridge sur un monitor

local BRIDGE_TYPES = { "rs_bridge", "rsBridge" }
local MONITOR_TYPE = "monitor"

local function wrapPs(peripheralType)
    local periTab = {}
    local sideTab = {}

    if peripheralType == nil then
        return nil, nil
    end

    local peripherals = peripheral.getNames()
    local i2 = 1

    for i = 1, #peripherals do
        local pName = peripherals[i]
        if peripheral.getType(pName) == peripheralType then
            periTab[i2] = peripheral.wrap(pName)
            sideTab[i2] = pName
            i2 = i2 + 1
        end
    end

    if #periTab > 0 then
        return periTab, sideTab
    end

    return nil, nil
end

local function findBridge()
    for _, t in ipairs(BRIDGE_TYPES) do
        local tabs, sides = wrapPs(t)
        if tabs and tabs[1] then
            return tabs[1], sides[1], t
        end
    end
    return nil, nil, nil
end

local bridge, bridgeSide, bridgeType = findBridge()
if not bridge then
    error("Aucun rs_bridge / rsBridge detecte")
end

local mons, monSides = wrapPs(MONITOR_TYPE)
if not mons or not mons[1] then
    error("Aucun monitor detecte")
end

local mon = mons[1]
local monitorSide = monSides[1]

mon.setTextScale(0.5)

local pages = {}
local currentPage = 1

local function safeCall(fn)
    local ok, a, b, c, d, e = pcall(fn)
    if ok then
        return true, { a, b, c, d, e }
    end
    return false, { a }
end

local function clearMonitor()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function monSize()
    return mon.getSize()
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if maxLen <= 0 then return "" end
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function serializeLines(value)
    local s = textutils.serialize(value, { compact = false }) or tostring(value)
    local lines = {}
    for line in s:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines == 0 then
        table.insert(lines, tostring(value))
    end
    return lines
end

local function addPage(title, lines)
    pages[#pages + 1] = {
        title = title or "Sans titre",
        lines = lines or {}
    }
end

local function addSectionPage(title)
    addPage(title, {})
end

local function appendLine(pageIndex, text)
    if not pages[pageIndex] then return end
    table.insert(pages[pageIndex].lines, tostring(text or ""))
end

local function appendSerialized(pageIndex, label, value)
    appendLine(pageIndex, label)
    local lines = serializeLines(value)
    for _, line in ipairs(lines) do
        appendLine(pageIndex, line)
    end
end

local function paginateLongLines(title, lines, linesPerPage)
    local chunk = {}
    local count = 0

    for _, line in ipairs(lines) do
        table.insert(chunk, line)
        count = count + 1

        if count >= linesPerPage then
            addPage(title, chunk)
            chunk = {}
            count = 0
        end
    end

    if #chunk > 0 then
        addPage(title, chunk)
    end
end

local function buildPages()
    pages = {}
    currentPage = 1

    local w, h = monSize()
    local usableLines = math.max(1, h - 3)

    -- Page résumé
    local p = #pages + 1
    addSectionPage("Resume")
    appendLine(p, "Bridge type : " .. tostring(bridgeType))
    appendLine(p, "Bridge side : " .. tostring(bridgeSide))
    appendLine(p, "Monitor side: " .. tostring(monitorSide))
    appendLine(p, "")
    appendLine(p, "Peripheriques detectes :")
    for _, name in ipairs(peripheral.getNames()) do
        appendLine(p, "- " .. name .. " -> " .. tostring(peripheral.getType(name)))
    end

    -- Page méthodes bridge
    local methods = peripheral.getMethods(bridgeSide) or {}
    table.sort(methods)
    paginateLongLines("Methodes rs_bridge", methods, usableLines)

    -- Test getCraftingTasks
    local okTasks, resTasks = safeCall(function()
        return bridge.getCraftingTasks()
    end)

    local tasks = nil
    local taskLines = {}

    if okTasks then
        tasks = resTasks[1]
        table.insert(taskLines, "Appel getCraftingTasks() : OK")
        local lines = serializeLines(tasks)
        for _, line in ipairs(lines) do
            table.insert(taskLines, line)
        end
    else
        table.insert(taskLines, "Appel getCraftingTasks() : ERREUR")
        table.insert(taskLines, tostring(resTasks[1]))
    end

    paginateLongLines("getCraftingTasks()", taskLines, usableLines)

    -- Détail des tasks
    if type(tasks) == "table" then
        for i, task in ipairs(tasks) do
            local lines = {}
            table.insert(lines, "Task #" .. tostring(i))
            table.insert(lines, "")
            table.insert(lines, "RAW:")
            local rawLines = serializeLines(task)
            for _, line in ipairs(rawLines) do
                table.insert(lines, line)
            end

            if type(task) == "table" then
                local keys = {}
                for k, _ in pairs(task) do
                    table.insert(keys, tostring(k))
                end
                table.sort(keys)

                table.insert(lines, "")
                table.insert(lines, "Cles:")
                for _, k in ipairs(keys) do
                    table.insert(lines, "- " .. k .. " (" .. type(task[k]) .. ")")
                end

                for _, k in ipairs(keys) do
                    if type(task[k]) == "function" then
                        table.insert(lines, "")
                        table.insert(lines, "task." .. k .. "() :")
                        local ok, res = safeCall(function()
                            return task[k]()
                        end)
                        if ok then
                            local methodLines = serializeLines(res[1])
                            for _, line in ipairs(methodLines) do
                                table.insert(lines, line)
                            end
                        else
                            table.insert(lines, "ERREUR: " .. tostring(res[1]))
                        end
                    end
                end
            end

            paginateLongLines("Task " .. tostring(i), lines, usableLines)
        end
    end
end

local function renderPage()
    clearMonitor()

    local w, h = monSize()
    local page = pages[currentPage]
    if not page then
        mon.setCursorPos(1, 1)
        mon.write("Aucune page")
        return
    end

    mon.setTextColor(colors.cyan)
    mon.setCursorPos(1, 1)
    mon.write(trim(page.title, w))

    local pageInfo = "Page " .. tostring(currentPage) .. "/" .. tostring(#pages)
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(math.max(1, w - #pageInfo + 1), 1)
    mon.write(pageInfo)

    mon.setTextColor(colors.gray)
    mon.setCursorPos(1, 2)
    mon.write(string.rep("-", w))

    mon.setTextColor(colors.white)
    local maxBody = h - 3
    for i = 1, maxBody do
        local line = page.lines[i]
        if not line then break end
        mon.setCursorPos(1, i + 2)
        mon.write(trim(line, w))
    end

    mon.setTextColor(colors.gray)
    mon.setCursorPos(1, h)
    mon.write(trim("[<] prec   [R] refresh   [>] suiv", w))
end

local function nextPage()
    if #pages == 0 then return end
    currentPage = currentPage + 1
    if currentPage > #pages then
        currentPage = 1
    end
end

local function prevPage()
    if #pages == 0 then return end
    currentPage = currentPage - 1
    if currentPage < 1 then
        currentPage = #pages
    end
end

local function refresh()
    buildPages()
    renderPage()
end

refresh()

while true do
    local ev, side, x, y = os.pullEvent()

    if ev == "monitor_touch" and side == monitorSide then
        local w, h = monSize()

        if y == h then
            if x <= math.floor(w / 3) then
                prevPage()
            elseif x <= math.floor((w / 3) * 2) then
                refresh()
            else
                nextPage()
            end
            renderPage()
        end
    elseif ev == "monitor_resize" then
        refresh()
    elseif ev == "rs_crafting" then
        refresh()
    end
end
