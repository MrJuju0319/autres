
-- =========================================================
-- Refined Storage Autocraft Monitor v2
-- Plus joli, plus dynamique, moins de scintillement
-- ComputerCraft / CC:Tweaked + rs_bridge
-- =========================================================

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/rs_autocraft.lua",
    AUTO_UPDATE_ENABLED = true,
    AUTO_UPDATE_FILE = "startup.lua",
    AUTO_UPDATE_TMP = "startup.lua.tmp",

    TITLE = "Refined Storage - Autocraft v5",
    TEXT_SCALE = 0.5,
    SIDE_PADDING = 2,
    HEADER_HEIGHT = 4,
    REFRESH_INTERVAL = 0.75,
    PAGE_ROTATE_EVERY = 8,
    ETA_SMOOTHING = 0.35,
    USE_CUSTOM_PALETTE = true,
    SHOW_FOOTER = true,
}

-- =========================
-- AUTO UPDATE
-- =========================
local function readFile(path)
    if not fs.exists(path) then
        return nil
    end

    local handle = fs.open(path, "r")
    if not handle then
        return nil
    end

    local content = handle.readAll()
    handle.close()
    return content
end

local function writeFile(path, content)
    local handle = fs.open(path, "w")
    if not handle then
        return false
    end

    handle.write(content or "")
    handle.close()
    return true
end

local function fetchUrl(url)
    if http and http.get then
        local ok, response = pcall(http.get, url)
        if ok and response then
            local content = response.readAll()
            response.close()
            if content and content ~= "" then
                return content
            end
        end
    end

    if shell and shell.run then
        if fs.exists(CONFIG.AUTO_UPDATE_TMP) then
            fs.delete(CONFIG.AUTO_UPDATE_TMP)
        end

        local ok = pcall(function()
            shell.run("wget", url, CONFIG.AUTO_UPDATE_TMP)
        end)

        if ok and fs.exists(CONFIG.AUTO_UPDATE_TMP) then
            local content = readFile(CONFIG.AUTO_UPDATE_TMP)
            fs.delete(CONFIG.AUTO_UPDATE_TMP)
            if content and content ~= "" then
                return content
            end
        end
    end

    return nil
end

local function autoUpdate()
    if not CONFIG.AUTO_UPDATE_ENABLED then
        return
    end

    local remote = fetchUrl(CONFIG.AUTO_UPDATE_URL)
    if not remote then
        print("Auto-update: impossible de verifier la version distante.")
        return
    end

    local localContent = readFile(CONFIG.AUTO_UPDATE_FILE)
    if localContent == remote then
        print("Auto-update: aucune mise a jour.")
        return
    end

    if writeFile(CONFIG.AUTO_UPDATE_TMP, remote) then
        if fs.exists(CONFIG.AUTO_UPDATE_FILE) then
            fs.delete(CONFIG.AUTO_UPDATE_FILE)
        end

        fs.move(CONFIG.AUTO_UPDATE_TMP, CONFIG.AUTO_UPDATE_FILE)
        print("Auto-update: mise a jour appliquee, reboot...")
        sleep(1)
        os.reboot()
    else
        print("Auto-update: echec d'ecriture.")
    end
end

autoUpdate()

-- =========================
-- PERIPHERIQUES
-- =========================
local bridge = peripheral.find("rs_bridge")
if not bridge then
    error("rs_bridge non detecte")
end

local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

mon.setTextScale(CONFIG.TEXT_SCALE)

local monitorName = peripheral.getName(mon)

-- =========================
-- ETAT
-- =========================
local history = {}
local state = {
    page = 1,
    sortIndex = 1,
    viewIndex = 1,
    frame = 1,
    lastRotate = os.clock(),
    lastTasks = {},
    lastStats = {},
    lastError = nil,
}

local SORT_MODES = {
    { key = "status", label = "STATUT" },
    { key = "eta",    label = "ETA"    },
    { key = "name",   label = "NOM"    },
    { key = "qty",    label = "QTE"    },
    { key = "pct",    label = "%"      },
}

local VIEW_MODES = {
    { key = "detail",  label = "DETAIL"  },
    { key = "compact", label = "COMPACT" },
}

local SPINNER = { "|", "/", "-", "\\" }

-- =========================
-- OUTILS
-- =========================
local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if maxLen <= 0 then return "" end
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function fillLine(termObj, y, bg)
    local w = termObj.getSize()
    termObj.setCursorPos(1, y)
    termObj.setBackgroundColor(bg)
    termObj.write(string.rep(" ", w))
end

local function writeAt(termObj, x, y, text, fg, bg, maxLen)
    local w = termObj.getSize()
    if y < 1 then return end
    if x > w then return end

    text = tostring(text or "")
    if maxLen then
        text = trim(text, maxLen)
    end

    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end

    if text == "" then return end

    termObj.setCursorPos(x, y)
    if bg then termObj.setBackgroundColor(bg) end
    if fg then termObj.setTextColor(fg) end
    termObj.write(trim(text, w - x + 1))
end

local function centerText(termObj, y, text, fg, bg)
    local w = termObj.getSize()
    text = trim(text, w)
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    writeAt(termObj, x, y, text, fg, bg)
end

local function formatNumber(n)
    n = tonumber(n) or 0
    n = math.floor(n + 0.5)

    local s = tostring(n)
    local result = ""
    while #s > 3 do
        result = " " .. s:sub(-3) .. result
        s = s:sub(1, -4)
    end
    result = s .. result
    return result
end

local function formatTime(seconds)
    if not seconds or seconds < 0 or seconds == math.huge then
        return "--:--"
    end

    seconds = math.floor(seconds + 0.5)

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60

    if h > 0 then
        return string.format("%dh%02dm%02ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm%02ds", m, s)
    else
        return string.format("%ds", s)
    end
end

local function getTaskName(task)
    local res = task.resource or {}
    return res.displayName or res.name or "Inconnu"
end

local function getTaskRawName(task)
    local res = task.resource or {}
    return res.name or res.displayName or "unknown"
end

local function getTaskKey(task)
    local res = task.resource or {}

    if task.id ~= nil then
        return "id|" .. tostring(task.id)
    end

    return table.concat({
        tostring(res.name or res.displayName or "unknown"),
        tostring(task.quantity or res.count or 0)
    }, "|")
end

local function getProgress(task)
    local res = task.resource or {}
    local total = tonumber(task.quantity) or tonumber(res.count) or 0
    local completion = tonumber(task.completion) or 0

    completion = clamp(completion, 0, 1)

    local current = total * completion
    return current, total, completion
end

local function getStatus(task)
    local _, _, completion = getProgress(task)

    if completion >= 1 then
        return "TERMINE", colors.lime
    elseif completion > 0 then
        return "EN COURS", colors.yellow
    else
        return "ATTENTE", colors.lightGray
    end
end

local function getPercent(task)
    local _, _, completion = getProgress(task)
    return math.floor((completion * 100) + 0.5)
end

local function getTaskIcon(task)
    local raw = getTaskRawName(task)

    if raw:find("extrastorage:disk_") or raw:find("refinedstorage:") and raw:find("disk") then
        return "DSK"
    elseif raw:find("processor") then
        return "CPU"
    elseif raw:find("crafting") then
        return "CRF"
    elseif raw:find("storage") then
        return "STO"
    elseif raw:find("cable") then
        return "NET"
    end

    local pretty = getTaskName(task)
    local chars = {}
    for word in pretty:gmatch("[%w]+") do
        chars[#chars + 1] = word:sub(1, 1):upper()
        if #chars >= 3 then break end
    end

    if #chars == 0 then
        return "???"
    end

    return table.concat(chars)
end

local function estimateRemaining(task, current, total, completion)
    local key = getTaskKey(task)
    local now = os.epoch("utc") / 1000

    local entry = history[key]
    if not entry then
        history[key] = {
            lastProgress = current,
            lastTime = now,
            rate = nil,
        }
        return nil
    end

    local dt = now - entry.lastTime
    local dp = current - entry.lastProgress

    if dt > 0 and dp > 0 then
        local instantRate = dp / dt
        if entry.rate then
            entry.rate = (entry.rate * (1 - CONFIG.ETA_SMOOTHING)) + (instantRate * CONFIG.ETA_SMOOTHING)
        else
            entry.rate = instantRate
        end
    end

    entry.lastProgress = current
    entry.lastTime = now

    if completion >= 1 then
        return 0
    end

    if not entry.rate or entry.rate <= 0 then
        return nil
    end

    local remaining = total - current
    if remaining <= 0 then
        return 0
    end

    return remaining / entry.rate
end

local function cleanupHistory(tasks)
    local alive = {}

    for i, task in ipairs(tasks) do
        alive[getTaskKey(task)] = true
    end

    for key in pairs(history) do
        if not alive[key] then
            history[key] = nil
        end
    end
end

local function safeGetTasks()
    local ok, tasks = pcall(function()
        return bridge.getCraftingTasks()
    end)

    if ok and type(tasks) == "table" then
        return tasks, nil
    end

    return nil, "Impossible de lire getCraftingTasks()"
end

local function sortTasks(tasks)
    local mode = SORT_MODES[state.sortIndex].key

    table.sort(tasks, function(a, b)
        local ac, at, acomp = getProgress(a)
        local bc, bt, bcomp = getProgress(b)

        local aeta = math.huge
        local beta = math.huge

        do
            local key = getTaskKey(a)
            local entry = history[key]
            if acomp >= 1 then
                aeta = 0
            elseif entry and entry.rate and entry.rate > 0 then
                aeta = math.max(0, (at - ac) / entry.rate)
            end
        end

        do
            local key = getTaskKey(b)
            local entry = history[key]
            if bcomp >= 1 then
                beta = 0
            elseif entry and entry.rate and entry.rate > 0 then
                beta = math.max(0, (bt - bc) / entry.rate)
            end
        end

        if mode == "status" then
            local sa = (acomp >= 1 and 2) or (acomp > 0 and 1) or 0
            local sb = (bcomp >= 1 and 2) or (bcomp > 0 and 1) or 0
            if sa ~= sb then return sa > sb end
            if acomp ~= bcomp then return acomp > bcomp end
            return getTaskName(a) < getTaskName(b)
        elseif mode == "eta" then
            if aeta ~= beta then return aeta < beta end
            return getTaskName(a) < getTaskName(b)
        elseif mode == "name" then
            return getTaskName(a):lower() < getTaskName(b):lower()
        elseif mode == "qty" then
            if at ~= bt then return at > bt end
            return getTaskName(a) < getTaskName(b)
        elseif mode == "pct" then
            if acomp ~= bcomp then return acomp > bcomp end
            return getTaskName(a) < getTaskName(b)
        end

        return getTaskName(a) < getTaskName(b)
    end)
end

local function buildStats(tasks)
    local stats = {
        jobs = #tasks,
        waiting = 0,
        running = 0,
        done = 0,
        totalItems = 0,
        currentItems = 0,
    }

    for _, task in ipairs(tasks) do
        local current, total, completion = getProgress(task)
        stats.totalItems = stats.totalItems + total
        stats.currentItems = stats.currentItems + current

        if completion >= 1 then
            stats.done = stats.done + 1
        elseif completion > 0 then
            stats.running = stats.running + 1
        else
            stats.waiting = stats.waiting + 1
        end
    end

    if stats.totalItems > 0 then
        stats.percent = clamp(stats.currentItems / stats.totalItems, 0, 1)
    elseif stats.jobs > 0 then
        stats.percent = clamp(stats.done / stats.jobs, 0, 1)
    else
        stats.percent = 0
    end

    return stats
end

-- =========================
-- UI
-- =========================
local function applyPalette()
    if not CONFIG.USE_CUSTOM_PALETTE then
        return
    end

    local ok = pcall(function()
        mon.setPaletteColor(colors.black,      0x101218)
        mon.setPaletteColor(colors.gray,       0x2B3240)
        mon.setPaletteColor(colors.lightGray,  0x8E97A8)
        mon.setPaletteColor(colors.white,      0xF2F4F8)
        mon.setPaletteColor(colors.cyan,       0x38BDF8)
        mon.setPaletteColor(colors.blue,       0x2563EB)
        mon.setPaletteColor(colors.lightBlue,  0x60A5FA)
        mon.setPaletteColor(colors.green,      0x16A34A)
        mon.setPaletteColor(colors.lime,       0x84CC16)
        mon.setPaletteColor(colors.yellow,     0xEAB308)
        mon.setPaletteColor(colors.orange,     0xF97316)
        mon.setPaletteColor(colors.red,        0xEF4444)
    end)

    if not ok then
        -- Moniteur non avance ou palette non supportee
    end
end

applyPalette()

local backBuffer

local function getBuffer()
    local w, h = mon.getSize()

    if not backBuffer then
        backBuffer = window.create(mon, 1, 1, w, h, false)
    else
        local bw, bh = backBuffer.getSize()
        if bw ~= w or bh ~= h then
            backBuffer = window.create(mon, 1, 1, w, h, false)
        end
    end

    backBuffer.setVisible(false)
    backBuffer.setBackgroundColor(colors.black)
    backBuffer.setTextColor(colors.white)
    backBuffer.clear()
    backBuffer.setCursorPos(1, 1)

    return backBuffer, w, h
end

local function drawButton(termObj, x, y, label, isActive)
    local bg = isActive and colors.blue or colors.gray
    local fg = colors.white
    local text = " " .. label .. " "
    writeAt(termObj, x, y, text, fg, bg)
    return #text
end

local function drawProgressBar(termObj, x, y, w, ratio, fillColor, emptyColor, label)
    ratio = clamp(ratio or 0, 0, 1)

    local filled = math.floor((w * ratio) + 0.5)
    filled = clamp(filled, 0, w)

    termObj.setCursorPos(x, y)
    termObj.setBackgroundColor(emptyColor)
    termObj.write(string.rep(" ", w))

    if filled > 0 then
        termObj.setCursorPos(x, y)
        termObj.setBackgroundColor(fillColor)
        termObj.write(string.rep(" ", filled))
    end

    if label and #label > 0 then
        local tx = x + math.max(0, math.floor((w - #label) / 2))
        writeAt(termObj, tx, y, label, colors.white, nil)
    end
end

local function drawHeader(termObj, stats, w)
    fillLine(termObj, 1, colors.gray)
    fillLine(termObj, 2, colors.black)
    fillLine(termObj, 3, colors.black)
    fillLine(termObj, 4, colors.black)

    local spinner = SPINNER[((state.frame - 1) % #SPINNER) + 1]
    writeAt(termObj, 2, 1, spinner .. " " .. trim(CONFIG.TITLE, math.max(1, w - 22)), colors.white, colors.gray)

    local jobText = "Jobs " .. tostring(stats.jobs)
    writeAt(termObj, math.max(1, w - #jobText - 1), 1, jobText .. " ", colors.cyan, colors.gray)

    local summaryLeft = string.format("Actifs %d", stats.running)
    local summaryMid = string.format("Attente %d", stats.waiting)
    local summaryRight = string.format("Termines %d", stats.done)
    writeAt(termObj, 2, 2, summaryLeft, colors.orange, colors.black)
    centerText(termObj, 2, summaryMid, colors.lightGray, colors.black)
    writeAt(termObj, math.max(2, w - #summaryRight - 1), 2, summaryRight, colors.lime, colors.black)

    local barLabel = tostring(math.floor(stats.percent * 100 + 0.5)) .. "%"
    drawProgressBar(termObj, 3, 3, math.max(10, w - 4), stats.percent, colors.green, colors.gray, barLabel)

    local sortLabel = "Tri: " .. SORT_MODES[state.sortIndex].label
    local viewLabel = "Vue: " .. VIEW_MODES[state.viewIndex].label
    writeAt(termObj, 2, 4, sortLabel, colors.lightBlue, colors.black)
    writeAt(termObj, math.max(2, w - #viewLabel - 1), 4, viewLabel, colors.lightBlue, colors.black)
end

local function drawTaskCardDetail(termObj, task, index, x, y, w)
    local current, total, completion = getProgress(task)
    local name = getTaskName(task)
    local status, statusColor = getStatus(task)
    local eta = estimateRemaining(task, current, total, completion)
    local percent = math.floor(completion * 100 + 0.5)
    local icon = getTaskIcon(task)

    fillLine(termObj, y, colors.black)
    fillLine(termObj, y + 1, colors.gray)
    fillLine(termObj, y + 2, colors.black)
    fillLine(termObj, y + 3, colors.black)
    fillLine(termObj, y + 4, colors.black)
    fillLine(termObj, y + 5, colors.black)

    local innerX = x + CONFIG.SIDE_PADDING
    local innerW = math.max(10, w - (CONFIG.SIDE_PADDING * 2))

    local title = string.format(" %02d [%s] %s", index, icon, name)
    writeAt(termObj, innerX, y + 1, trim(title, innerW), colors.white, colors.gray)

    writeAt(termObj, innerX, y + 2, "Etat: " .. status, statusColor, colors.black, innerW)
    local etaText = "ETA " .. formatTime(eta)
    writeAt(termObj, math.max(innerX, innerX + innerW - #etaText), y + 2, etaText, colors.lightBlue, colors.black)

    drawProgressBar(
        termObj,
        innerX,
        y + 3,
        innerW,
        completion,
        (completion >= 1 and colors.lime) or (completion > 0 and colors.orange) or colors.gray,
        colors.gray,
        percent .. "%"
    )

    local info = string.format("Progression: %s / %s", formatNumber(current), formatNumber(total))
    writeAt(termObj, innerX, y + 4, trim(info, innerW), colors.white, colors.black)

    local raw = getTaskRawName(task)
    writeAt(termObj, innerX, y + 5, trim(raw, innerW), colors.lightGray, colors.black)
end

local function drawTaskCardCompact(termObj, task, index, x, y, w)
    local current, total, completion = getProgress(task)
    local name = getTaskName(task)
    local status, statusColor = getStatus(task)
    local eta = estimateRemaining(task, current, total, completion)
    local percent = math.floor(completion * 100 + 0.5)
    local icon = getTaskIcon(task)

    fillLine(termObj, y, colors.black)
    fillLine(termObj, y + 1, colors.gray)
    fillLine(termObj, y + 2, colors.black)
    fillLine(termObj, y + 3, colors.black)

    local innerX = x + CONFIG.SIDE_PADDING
    local innerW = math.max(10, w - (CONFIG.SIDE_PADDING * 2))

    local header = string.format(" %02d [%s] %s", index, icon, name)
    writeAt(termObj, innerX, y + 1, trim(header, innerW), colors.white, colors.gray)

    local bodyLeft = string.format("%s  %s/%s", status, formatNumber(current), formatNumber(total))
    writeAt(termObj, innerX, y + 2, trim(bodyLeft, innerW - 14), statusColor, colors.black)

    local bodyRight = percent .. "%  " .. formatTime(eta)
    writeAt(termObj, math.max(innerX, innerX + innerW - #bodyRight), y + 2, bodyRight, colors.lightBlue, colors.black)

    drawProgressBar(
        termObj,
        innerX,
        y + 3,
        innerW,
        completion,
        (completion >= 1 and colors.lime) or (completion > 0 and colors.orange) or colors.gray,
        colors.gray,
        ""
    )
end

local function drawEmptyState(termObj, w, h)
    fillLine(termObj, 5, colors.black)
    fillLine(termObj, 6, colors.black)
    fillLine(termObj, 7, colors.black)

    if state.lastError then
        centerText(termObj, math.floor(h / 2) - 1, "Source indisponible", colors.red, colors.black)
        centerText(termObj, math.floor(h / 2), trim(state.lastError, w - 6), colors.lightGray, colors.black)
    else
        centerText(termObj, math.floor(h / 2) - 1, "Aucun craft en cours", colors.lime, colors.black)
        centerText(termObj, math.floor(h / 2) + 1, "Le reseau est calme.", colors.lightGray, colors.black)
    end
end

local function drawFooter(termObj, w, h, totalPages)
    if not CONFIG.SHOW_FOOTER or h < 8 then
        return
    end

    fillLine(termObj, h - 1, colors.black)
    fillLine(termObj, h, colors.black)

    local left = 2
    left = left + drawButton(termObj, left, h, "TRI", false) + 2
    left = left + drawButton(termObj, left, h, "VUE", false) + 2

    local pageText = string.format("Page %d/%d", state.page, totalPages)
    writeAt(termObj, math.max(left, w - #pageText - 1), h, pageText, colors.cyan, colors.black)
end

local function getLayout(h)
    local top = CONFIG.HEADER_HEIGHT + 1
    local footer = (CONFIG.SHOW_FOOTER and h >= 9) and 2 or 0
    local usable = h - top - footer + 1

    if VIEW_MODES[state.viewIndex].key == "detail" then
        return {
            top = top,
            footer = footer,
            cardHeight = 6,
            perPage = math.max(1, math.floor(usable / 6))
        }
    else
        return {
            top = top,
            footer = footer,
            cardHeight = 4,
            perPage = math.max(1, math.floor(usable / 4))
        }
    end
end

local function drawScreen(tasks, stats)
    local termObj, w, h = getBuffer()
    drawHeader(termObj, stats, w)

    if #tasks == 0 then
        drawEmptyState(termObj, w, h)
        drawFooter(termObj, w, h, 1)
        backBuffer.setVisible(true)
        return
    end

    local layout = getLayout(h)
    local totalPages = math.max(1, math.ceil(#tasks / layout.perPage))

    state.page = clamp(state.page, 1, totalPages)

    local startIndex = ((state.page - 1) * layout.perPage) + 1
    local endIndex = math.min(#tasks, startIndex + layout.perPage - 1)

    local y = layout.top

    for i = startIndex, endIndex do
        if VIEW_MODES[state.viewIndex].key == "detail" then
            drawTaskCardDetail(termObj, tasks[i], i, 1, y, w)
        else
            drawTaskCardCompact(termObj, tasks[i], i, 1, y, w)
        end
        y = y + layout.cardHeight
    end

    while y <= h - layout.footer do
        fillLine(termObj, y, colors.black)
        y = y + 1
    end

    drawFooter(termObj, w, h, totalPages)
    backBuffer.setVisible(true)
end

-- =========================
-- INTERACTIONS
-- =========================
local function getTotalPages(taskCount)
    local _, h = mon.getSize()
    local layout = getLayout(h)
    return math.max(1, math.ceil(taskCount / layout.perPage))
end

local function cycleSort()
    state.sortIndex = state.sortIndex + 1
    if state.sortIndex > #SORT_MODES then
        state.sortIndex = 1
    end
end

local function cycleView()
    state.viewIndex = state.viewIndex + 1
    if state.viewIndex > #VIEW_MODES then
        state.viewIndex = 1
    end
end

local function nextPage()
    local totalPages = getTotalPages(#state.lastTasks)
    state.page = state.page + 1
    if state.page > totalPages then
        state.page = 1
    end
end

local function handleTouch(x, y)
    local w, h = mon.getSize()

    if CONFIG.SHOW_FOOTER and y == h then
        if x >= 2 and x <= 7 then
            cycleSort()
            state.page = 1
            return
        elseif x >= 9 and x <= 14 then
            cycleView()
            state.page = 1
            return
        else
            nextPage()
            return
        end
    end

    if y <= 3 then
        if x <= math.floor(w / 2) then
            cycleSort()
            state.page = 1
        else
            nextPage()
        end
        return
    end

    nextPage()
end

-- =========================
-- BOUCLE
-- =========================
local function refreshData()
    bridge = bridge or peripheral.find("rs_bridge")
    mon = mon or peripheral.find("monitor")

    if not mon then
        error("monitor non detecte")
    end

    mon.setTextScale(CONFIG.TEXT_SCALE)

    if not bridge then
        state.lastTasks = {}
        state.lastStats = buildStats({})
        state.lastError = "rs_bridge non detecte"
        return
    end

    local tasks, err = safeGetTasks()
    if not tasks then
        state.lastTasks = {}
        state.lastStats = buildStats({})
        state.lastError = err or "Erreur inconnue"
        return
    end

    state.lastError = nil
    cleanupHistory(tasks)
    sortTasks(tasks)

    state.lastTasks = tasks
    state.lastStats = buildStats(tasks)

    local now = os.clock()
    local totalPages = getTotalPages(#tasks)
    if totalPages > 1 and (now - state.lastRotate) >= CONFIG.PAGE_ROTATE_EVERY then
        state.page = (state.page % totalPages) + 1
        state.lastRotate = now
    elseif totalPages <= 1 then
        state.page = 1
        state.lastRotate = now
    end
end

local function render()
    state.frame = state.frame + 1
    drawScreen(state.lastTasks, state.lastStats)
end

refreshData()
render()

local timer = os.startTimer(CONFIG.REFRESH_INTERVAL)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
        refreshData()
        render()
        timer = os.startTimer(CONFIG.REFRESH_INTERVAL)

    elseif event == "monitor_touch" and p1 == monitorName then
        handleTouch(p2, p3)
        render()

    elseif event == "monitor_resize" and p1 == monitorName then
        mon.setTextScale(CONFIG.TEXT_SCALE)
        applyPalette()
        render()

    elseif event == "peripheral" or event == "peripheral_detach" then
        bridge = peripheral.find("rs_bridge")
        mon = peripheral.find("monitor") or mon

        if mon then
            monitorName = peripheral.getName(mon)
            mon.setTextScale(CONFIG.TEXT_SCALE)
            applyPalette()
        end

        refreshData()
        render()
    end
end
