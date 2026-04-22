 -- =========================================================
-- Refined Storage Dashboard V5 Stable
-- Single page / clean layout / anti-flicker
-- CC:Tweaked + rs_bridge
-- =========================================================

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/debug.lua",
    AUTO_UPDATE_ENABLED = true,

    TITLE = "Refined Storage - Dashboard v5",
    TEXT_SCALE = 0.5,
    REFRESH_INTERVAL = 1.0,
    SLOW_REFRESH_INTERVAL = 8,
    ETA_SMOOTHING = 0.35,
    USE_CUSTOM_PALETTE = true,
    SHOW_FOOTER = true,

    SHOW_ALERTS = true,
    SHOW_TOPS = true,

    ITEMS_WARN_PERCENT = 80,
    ITEMS_DANGER_PERCENT = 95,

    FLUIDS_WARN_PERCENT = 80,
    FLUIDS_DANGER_PERCENT = 95,

    ENERGY_WARN_LOW_PERCENT = 20,
    ENERGY_DANGER_LOW_PERCENT = 5,

    MAX_TOP_FLUIDS = 3,
    MAX_TOP_TASKS = 2,
}

-- =========================
-- AUTO UPDATE
-- =========================
local function getCurrentFile()
    if shell and shell.getRunningProgram then
        local p = shell.getRunningProgram()
        if p and p ~= "" then
            return p
        end
    end
    return "rs_storage.lua"
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local c = h.readAll()
    h.close()
    return c
end

local function writeFile(path, content)
    local h = fs.open(path, "w")
    if not h then return false end
    h.write(content or "")
    h.close()
    return true
end

local function fetchUrl(url, tmpPath)
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
        if fs.exists(tmpPath) then
            fs.delete(tmpPath)
        end

        local ok = pcall(function()
            shell.run("wget", url, tmpPath)
        end)

        if ok and fs.exists(tmpPath) then
            local content = readFile(tmpPath)
            fs.delete(tmpPath)
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

    local currentFile = getCurrentFile()
    local tmpFile = currentFile .. ".tmp"

    local remote = fetchUrl(CONFIG.AUTO_UPDATE_URL, tmpFile)
    if not remote then
        print("Auto-update: impossible de verifier la version distante.")
        return
    end

    local localContent = readFile(currentFile)
    if localContent == remote then
        print("Auto-update: aucune mise a jour.")
        return
    end

    if writeFile(tmpFile, remote) then
        if fs.exists(currentFile) then
            fs.delete(currentFile)
        end
        fs.move(tmpFile, currentFile)
        print("Auto-update: mise a jour appliquee, reboot...")
        sleep(1)
        os.reboot()
    else
        print("Auto-update: echec d'ecriture.")
    end
end

autoUpdate()

-- =========================
-- HELPERS
-- =========================
local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function safe(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
end

local function nowSec()
    return os.epoch("utc") / 1000
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if maxLen <= 0 then return "" end
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function toNumber(v, default)
    v = tonumber(v)
    if v == nil then return default or 0 end
    return v
end

local function percent(used, total)
    used = tonumber(used) or 0
    total = tonumber(total) or 0
    if total <= 0 then return 0 end
    return clamp(math.floor((used / total) * 100 + 0.5), 0, 100)
end

local function formatNumber(n)
    n = tonumber(n) or 0
    local sign = ""
    if n < 0 then
        sign = "-"
        n = math.abs(n)
    end

    if n >= 1000000000000 then
        return sign .. string.format("%.2fT", n / 1000000000000)
    elseif n >= 1000000000 then
        return sign .. string.format("%.2fG", n / 1000000000)
    elseif n >= 1000000 then
        return sign .. string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then
        return sign .. string.format("%.2fk", n / 1000)
    else
        return sign .. tostring(math.floor(n + 0.5))
    end
end

local function formatRate(n)
    n = tonumber(n) or 0
    local sign = ""
    if n > 0 then sign = "+" end
    return sign .. formatNumber(n) .. "/s"
end

local function pushHistory(tbl, value)
    tbl[#tbl + 1] = tonumber(value) or 0
    while #tbl > (CONFIG.historySize or 48) do
        table.remove(tbl, 1)
    end
end

local function formatTime(seconds)
    if not seconds or seconds < 0 or seconds == math.huge then
        return "--"
    end

    if seconds > 30 * 24 * 3600 then
        return "long"
    end

    seconds = math.floor(seconds + 0.5)
    local d = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local h = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local m = math.floor(seconds / 60)
    local s = seconds % 60

    if d > 0 then
        return string.format("%dj%02dh", d, h)
    elseif h > 0 then
        return string.format("%dh%02dm", h, m)
    elseif m > 0 then
        return string.format("%dm%02ds", m, s)
    else
        return string.format("%ds", s)
    end
end

local function getPercentColor(p)
    if p >= 95 then
        return colors.red
    elseif p >= 80 then
        return colors.orange
    elseif p >= 60 then
        return colors.yellow
    else
        return colors.lime
    end
end

local function firstExisting(tbl, keys, default)
    if type(tbl) ~= "table" then return default end
    for _, k in ipairs(keys) do
        if tbl[k] ~= nil then
            return tbl[k]
        end
    end
    return default
end

local function wrapText(text, width)
    text = tostring(text or "")
    width = math.max(1, width)

    local lines = {}
    if text == "" then
        return { "" }
    end

    while #text > width do
        local cut = width
        local space = text:sub(1, width):match("^.*() ")
        if space and space > math.floor(width * 0.5) then
            cut = space
        end

        local line = text:sub(1, cut):gsub("%s+$", "")
        lines[#lines + 1] = line
        text = text:sub(cut + 1):gsub("^%s+", "")
    end

    if text ~= "" then
        lines[#lines + 1] = text
    end

    return lines
end

-- =========================
-- UI HELPERS
-- =========================
local function fillLine(termObj, y, bg)
    local w = termObj.getSize()
    termObj.setCursorPos(1, y)
    termObj.setBackgroundColor(bg or colors.black)
    termObj.write(string.rep(" ", w))
end

local function fillRect(termObj, x, y, w, h, bg)
    termObj.setBackgroundColor(bg or colors.black)
    for yy = y, y + h - 1 do
        termObj.setCursorPos(x, yy)
        termObj.write(string.rep(" ", w))
    end
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

local function drawButton(termObj, x, y, label, isActive)
    local bg = isActive and colors.blue or colors.gray
    local fg = colors.white
    local text = " " .. label .. " "
    writeAt(termObj, x, y, text, fg, bg)
    return #text
end

local function drawProgressBar(termObj, x, y, w, ratio, fillColor, emptyColor, label)
    ratio = clamp(ratio or 0, 0, 1)
    local filled = clamp(math.floor((w * ratio) + 0.5), 0, w)

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

-- =========================
-- PERIPHERALS
-- =========================
local bridge = peripheral.find("rs_bridge") or peripheral.find("rsBridge")
if not bridge then
    error("rs_bridge / rsBridge non detecte")
end

local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

mon.setTextScale(CONFIG.TEXT_SCALE)
local monitorName = peripheral.getName(mon)

-- =========================
-- STATE
-- =========================
local state = {
    showAlerts = CONFIG.SHOW_ALERTS,
    showTops = CONFIG.SHOW_TOPS,
}

local cache = {
    slowLastRefresh = 0,
    itemTypes = 0,
    fluidTypes = 0,
    cells = {},
    items = {},
    fluids = {},
    tasks = {},
}

local energyStats = {
    lastStored = nil,
    lastTime = nil,
    deltaPerSec = 0,
    avgInput = 0,
}

local history = {
    items = {},
    fluids = {},
    energy = {},
}

local backBuffer

-- =========================
-- EXTRACTION
-- =========================
local function getFluidName(f)
    return firstExisting(f, {
        "displayName", "display_name", "name"
    }, firstExisting(f.fluidType, {
        "displayName", "display_name", "name"
    }, "Fluide inconnu"))
end

local function getFluidAmount(f)
    return toNumber(firstExisting(f, {
        "amount", "count", "stored"
    }, firstExisting(f.fluidType, {
        "amount", "count", "stored"
    }, 0)), 0)
end

local function getTaskName(task)
    local res = firstExisting(task, { "resource" }, {})
    return firstExisting(res, {
        "displayName", "display_name", "name"
    }, "Craft inconnu")
end

local function getTaskTotal(task)
    local res = firstExisting(task, { "resource" }, {})
    return toNumber(firstExisting(task, {
        "quantity", "count", "amount"
    }, firstExisting(res, {
        "count", "amount"
    }, 0)), 0)
end

local function getTaskCompletion(task)
    return clamp(toNumber(firstExisting(task, { "completion" }, 0), 0), 0, 1)
end

local function getTaskStatus(task)
    local c = getTaskCompletion(task)
    if c >= 1 then
        return "TERMINE", colors.lime
    elseif c > 0 then
        return "EN COURS", colors.yellow
    else
        return "ATTENTE", colors.lightGray
    end
end

-- =========================
-- ALERTS
-- =========================
local function buildMainAlert(name, p, warn, danger, inverse, charging)
    if inverse then
        if p <= danger then
            if charging then
                return { text = name .. " LOW+", color = colors.orange, severity = 1 }
            end
            return { text = name .. " CRIT", color = colors.red, severity = 2 }
        elseif p <= warn then
            return { text = name .. " LOW", color = colors.orange, severity = 1 }
        else
            return { text = name .. " OK", color = colors.lime, severity = 0 }
        end
    else
        if p >= danger then
            return { text = name .. " CRIT", color = colors.red, severity = 2 }
        elseif p >= warn then
            return { text = name .. " WARN", color = colors.orange, severity = 1 }
        else
            return { text = name .. " OK", color = colors.lime, severity = 0 }
        end
    end
end

-- =========================
-- ENERGY
-- =========================
local function updateEnergyStats(storedEnergy, avgInput)
    local now = nowSec()

    storedEnergy = tonumber(storedEnergy) or 0
    avgInput = tonumber(avgInput) or 0

    if energyStats.lastStored ~= nil and energyStats.lastTime ~= nil then
        local dt = now - energyStats.lastTime
        if dt > 0 then
            local delta = storedEnergy - energyStats.lastStored
            local instantDeltaPerSec = delta / dt
            energyStats.deltaPerSec = (energyStats.deltaPerSec * (1 - CONFIG.ETA_SMOOTHING)) + (instantDeltaPerSec * CONFIG.ETA_SMOOTHING)
        end
    end

    energyStats.lastStored = storedEnergy
    energyStats.lastTime = now
    energyStats.avgInput = avgInput
end

-- =========================
-- SLOW CACHE
-- =========================
local function refreshSlowData(force)
    local now = nowSec()
    if not force and (now - cache.slowLastRefresh) < CONFIG.SLOW_REFRESH_INTERVAL then
        return
    end

    cache.items = safe(function() return bridge.getItems() end, {}) or {}
    cache.fluids = safe(function() return bridge.getFluids() end, {}) or {}
    cache.tasks = safe(function() return bridge.getCraftingTasks() end, {}) or {}
    cache.cells = safe(function() return bridge.getCells() end, {}) or {}

    cache.itemTypes = #cache.items
    cache.fluidTypes = #cache.fluids
    cache.slowLastRefresh = now
end

-- =========================
-- TOPS
-- =========================
local function getTopFluids()
    local list = {}

    for _, f in ipairs(cache.fluids) do
        list[#list + 1] = {
            name = getFluidName(f),
            amount = getFluidAmount(f),
        }
    end

    table.sort(list, function(a, b)
        return a.amount > b.amount
    end)

    local out = {}
    for i = 1, math.min(CONFIG.MAX_TOP_FLUIDS, #list) do
        out[#out + 1] = list[i]
    end
    return out
end

local function getTopTasks()
    local list = {}

    for _, t in ipairs(cache.tasks) do
        list[#list + 1] = {
            name = getTaskName(t),
            total = getTaskTotal(t),
            completion = getTaskCompletion(t),
            status, color = getTaskStatus(t),
        }
    end

    table.sort(list, function(a, b)
        if a.completion ~= b.completion then
            return a.completion > b.completion
        end
        return a.total > b.total
    end)

    local out = {}
    for i = 1, math.min(CONFIG.MAX_TOP_TASKS, #list) do
        out[#out + 1] = list[i]
    end
    return out
end

-- =========================
-- DATA
-- =========================
local function buildData()
    refreshSlowData(false)

    local usedItems = toNumber(safe(function() return bridge.getUsedItemStorage() end, 0), 0)
    local totalItems = toNumber(safe(function() return bridge.getTotalItemStorage() end, 0), 0)

    local usedFluids = toNumber(safe(function() return bridge.getUsedFluidStorage() end, 0), 0)
    local totalFluids = toNumber(safe(function() return bridge.getTotalFluidStorage() end, 0), 0)

    local storedEnergy = toNumber(safe(function() return bridge.getStoredEnergy() end, 0), 0)
    local energyTotal = toNumber(safe(function() return bridge.getEnergyCapacity() end, 0), 0)
    local energyUsage = toNumber(safe(function() return bridge.getEnergyUsage() end, 0), 0)
    local avgInput = toNumber(safe(function() return bridge.getAverageEnergyInput() end, 0), 0)

    local online = safe(function() return bridge.isOnline() end, nil)
    local connected = safe(function() return bridge.isConnected() end, nil)
    local crafting = safe(function() return bridge.isCrafting() end, nil)

    updateEnergyStats(storedEnergy, avgInput)

    local pItems = percent(usedItems, totalItems)
    local pFluids = percent(usedFluids, totalFluids)
    local pEnergy = percent(storedEnergy, energyTotal)

    local charging = energyStats.deltaPerSec > 1

    local itemAlert = buildMainAlert("ITM", pItems, CONFIG.ITEMS_WARN_PERCENT, CONFIG.ITEMS_DANGER_PERCENT, false, false)
    local fluidAlert = buildMainAlert("FLD", pFluids, CONFIG.FLUIDS_WARN_PERCENT, CONFIG.FLUIDS_DANGER_PERCENT, false, false)
    local energyAlert = buildMainAlert("NRG", pEnergy, CONFIG.ENERGY_WARN_LOW_PERCENT, CONFIG.ENERGY_DANGER_LOW_PERCENT, true, charging)

    local trend = "Stable"
    local eta = "--"

    if energyStats.deltaPerSec > 1 then
        trend = "Charge"
        local remaining = energyTotal - storedEnergy
        if remaining > 0 then
            eta = formatTime(remaining / energyStats.deltaPerSec)
        end
    elseif energyStats.deltaPerSec < -1 then
        trend = "Decharge"
        if storedEnergy > 0 then
            eta = formatTime(storedEnergy / math.abs(energyStats.deltaPerSec))
        end
    end

    return {
        items = {
            used = usedItems,
            total = totalItems,
            percent = pItems,
            types = cache.itemTypes,
            alert = itemAlert,
        },
        fluids = {
            used = usedFluids,
            total = totalFluids,
            percent = pFluids,
            types = cache.fluidTypes,
            alert = fluidAlert,
            top = getTopFluids(),
        },
        energy = {
            stored = storedEnergy,
            total = energyTotal,
            percent = pEnergy,
            usage = energyUsage,
            avgInput = avgInput,
            deltaPerSec = energyStats.deltaPerSec,
            trend = trend,
            eta = eta,
            alert = energyAlert,
        },
        craft = {
            count = #cache.tasks,
            active = crafting,
            top = getTopTasks(),
        },
        cells = {
            count = #cache.cells,
        },
        network = {
            online = online,
            connected = connected,
        }
    }
end

-- =========================
-- PALETTE
-- =========================
local function applyPalette()
    if not CONFIG.USE_CUSTOM_PALETTE then
        return
    end

    pcall(function()
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
end

-- =========================
-- BUFFER
-- =========================
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

-- =========================
-- DRAW
-- =========================
local function drawHeader(termObj, data, w)
    fillLine(termObj, 1, colors.gray)
    fillLine(termObj, 2, colors.black)
    fillLine(termObj, 3, colors.black)
    fillLine(termObj, 4, colors.black)

    local status = "ONLINE"
    if data.network.online == false then
        status = "OFFLINE"
    elseif data.network.connected == false then
        status = "DISCONNECT"
    end

    writeAt(termObj, 2, 1, trim(CONFIG.TITLE, math.max(1, w - #status - 4)), colors.white, colors.gray)
    writeAt(termObj, math.max(2, w - #status - 1), 1, status, colors.cyan, colors.gray)

    local meta = "Types I " .. tostring(data.items.types)
        .. " | Types F " .. tostring(data.fluids.types)
        .. " | Disques " .. tostring(data.cells.count)
        .. " | Crafts " .. tostring(data.craft.count)
    centerText(termObj, 2, trim(meta, w - 4), colors.lightGray, colors.black)

    local occ = math.max(data.items.percent, data.fluids.percent, data.energy.percent)
    drawProgressBar(termObj, 3, 3, math.max(10, w - 4), occ / 100, colors.green, colors.gray, "Occupation max " .. tostring(occ) .. "%")

    local alertLine = data.items.alert.text .. " | " .. data.fluids.alert.text .. " | " .. data.energy.alert.text
    writeAt(termObj, 2, 4, trim(alertLine, w - 18), colors.lightBlue, colors.black)

    local modeText = "TOP:" .. (state.showTops and "ON" or "OFF") .. " ALR:" .. (state.showAlerts and "ON" or "OFF")
    writeAt(termObj, math.max(2, w - #modeText - 1), 4, modeText, colors.lightBlue, colors.black)
end

local function drawMetricCard(termObj, title, used, total, pct, alert, extra1, x, y, w, unit)
    fillRect(termObj, x, y, w, 1, colors.gray)
    fillRect(termObj, x, y + 1, w, 3, colors.black)

    local innerX = x + 1
    local innerW = math.max(8, w - 2)

    local headRight = tostring(pct) .. "% " .. (alert and alert.text or "N/A")
    writeAt(termObj, innerX, y, title, colors.white, colors.gray, math.max(1, innerW - #headRight - 1))
    writeAt(termObj, x + w - #headRight, y, headRight, alert and alert.color or colors.lightGray, colors.gray)

    local main = formatNumber(used) .. " / " .. formatNumber(total)
    if unit and unit ~= "" then
        main = main .. " " .. unit
    end
    writeAt(termObj, innerX, y + 1, trim(main, innerW), colors.white, colors.black)
    drawProgressBar(termObj, innerX, y + 2, innerW, pct / 100, getPercentColor(pct), colors.gray, "")
    writeAt(termObj, innerX, y + 3, trim(extra1 or "", innerW), colors.lightGray, colors.black)
end

local function drawEnergyCard(termObj, data, x, y, w)
    fillRect(termObj, x, y, w, 1, colors.gray)
    fillRect(termObj, x, y + 1, w, 4, colors.black)

    local headRight = tostring(data.energy.percent) .. "% " .. data.energy.alert.text
    writeAt(termObj, x + 1, y, "Energie", colors.white, colors.gray, math.max(1, w - #headRight - 3))
    writeAt(termObj, x + w - #headRight, y, headRight, data.energy.alert.color, colors.gray)

    writeAt(termObj, x + 1, y + 1,
        trim(formatNumber(data.energy.stored) .. " / " .. formatNumber(data.energy.total) .. " FE", w - 2),
        colors.white, colors.black)

    drawProgressBar(termObj, x + 1, y + 2, w - 2, data.energy.percent / 100, getPercentColor(data.energy.percent), colors.gray, "")
    writeAt(termObj, x + 1, y + 3, trim("Net: " .. formatRate(data.energy.deltaPerSec) .. " | " .. data.energy.trend, w - 2), colors.lightBlue, colors.black)
    writeAt(termObj, x + 1, y + 4, trim("ETA: " .. data.energy.eta .. " | Usage: " .. formatRate(data.energy.usage), w - 2), colors.lightGray, colors.black)
end

local function drawCraftCard(termObj, data, x, y, w)
    fillRect(termObj, x, y, w, 1, colors.gray)
    fillRect(termObj, x, y + 1, w, 3, colors.black)

    local stateText = (data.craft.active == true and "ACTIF") or (data.craft.count > 0 and "FILE") or "CALME"
    local stateColor = (data.craft.active == true and colors.orange) or (data.craft.count > 0 and colors.yellow) or colors.lime
    local headRight = tostring(data.craft.count) .. " jobs"

    writeAt(termObj, x + 1, y, "Crafts", colors.white, colors.gray, math.max(1, w - #headRight - 3))
    writeAt(termObj, x + w - #headRight, y, headRight, colors.lightBlue, colors.gray)

    writeAt(termObj, x + 1, y + 1, "Etat: " .. stateText, stateColor, colors.black)

    if state.showTops and #data.craft.top > 0 then
        local lines = {}
        for i, t in ipairs(data.craft.top) do
            lines[#lines + 1] = "[" .. i .. "] " .. trim(t.name, 18) .. " " .. math.floor(t.completion * 100 + 0.5) .. "%"
        end
        writeAt(termObj, x + 1, y + 2, trim(table.concat(lines, " | "), w - 2), colors.lightGray, colors.black)
    else
        writeAt(termObj, x + 1, y + 2, "Top crafts masques", colors.lightGray, colors.black)
    end

    writeAt(termObj, x + 1, y + 3, "Disques: " .. tostring(data.cells.count), colors.lightGray, colors.black)
end

local function buildTopFluidsLine(data)
    if not state.showTops or #data.fluids.top == 0 then
        return "Top fluides masques"
    end

    local parts = {}
    for i, f in ipairs(data.fluids.top) do
        parts[#parts + 1] = "[" .. i .. "] " .. trim(f.name, 16) .. " " .. formatNumber(f.amount)
    end
    return "Top fluides: " .. table.concat(parts, " | ")
end

local function drawFooter(termObj, w, h)
    if not CONFIG.SHOW_FOOTER or h < 8 then
        return
    end

    fillLine(termObj, h - 1, colors.black)
    fillLine(termObj, h, colors.black)

    local left = 2
    left = left + drawButton(termObj, left, h, "TOP", state.showTops) + 2
    left = left + drawButton(termObj, left, h, "ALR", state.showAlerts) + 2
    left = left + drawButton(termObj, left, h, "REF", false) + 2

    writeAt(termObj, math.max(left, w - 9), h, "Synthese", colors.cyan, colors.black)
end

local function drawScreen(data)
    local termObj, w, h = getBuffer()

    drawHeader(termObj, data, w)

    local top = 5
    local gutter = 2
    local leftW = math.floor((w - gutter) / 2)
    local rightW = w - leftW - gutter

    drawMetricCard(
        termObj, "Items",
        data.items.used, data.items.total, data.items.percent, data.items.alert,
        "Types: " .. tostring(data.items.types),
        1, top, leftW, ""
    )

    drawMetricCard(
        termObj, "Fluides",
        data.fluids.used, data.fluids.total, data.fluids.percent, data.fluids.alert,
        "Types: " .. tostring(data.fluids.types),
        leftW + gutter + 1, top, rightW, "mB"
    )

    local energyY = top + 5
    drawEnergyCard(termObj, data, 1, energyY, w)
    local craftY = energyY + 6
    drawCraftCard(termObj, data, 1, craftY, w)

    local currentY = craftY + 5
    local maxBodyY = h - (CONFIG.SHOW_FOOTER and 2 or 0)

    for y = currentY, maxBodyY do
        fillLine(termObj, y, colors.black)
    end

    if state.showAlerts and currentY <= maxBodyY then
        local severity = math.max(
            data.items.alert.severity or 0,
            data.fluids.alert.severity or 0,
            data.energy.alert.severity or 0
        )

        local color = colors.lime
        if severity >= 2 then
            color = colors.red
        elseif severity >= 1 then
            color = colors.orange
        end

        local summary = "Synthese alertes: " .. data.items.alert.text .. " | " .. data.fluids.alert.text .. " | " .. data.energy.alert.text
        for _, line in ipairs(wrapText(summary, w - 2)) do
            if currentY > maxBodyY then break end
            writeAt(termObj, 2, currentY, line, color, colors.black)
            currentY = currentY + 1
        end
    end

    if currentY <= maxBodyY then
        for _, line in ipairs(wrapText(buildTopFluidsLine(data), w - 2)) do
            if currentY > maxBodyY then break end
            writeAt(termObj, 2, currentY, line, colors.lightGray, colors.black)
            currentY = currentY + 1
        end
    end

    drawFooter(termObj, w, h)
    backBuffer.setVisible(true)
end

-- =========================
-- PALETTE
-- =========================
applyPalette()

-- =========================
-- INTERACTION
-- =========================
local function handleTouch(x, y)
    local _, h = mon.getSize()

    if CONFIG.SHOW_FOOTER and y == h then
        if x >= 2 and x <= 7 then
            state.showTops = not state.showTops
            return
        elseif x >= 9 and x <= 14 then
            state.showAlerts = not state.showAlerts
            return
        elseif x >= 16 and x <= 21 then
            cache.slowLastRefresh = 0
            return
        end
    end

    cache.slowLastRefresh = 0
end

-- =========================
-- LOOP
-- =========================
local function render()
    bridge = peripheral.find("rs_bridge") or peripheral.find("rsBridge") or bridge
    mon = peripheral.find("monitor") or mon

    if not mon then
        error("monitor non detecte")
    end

    mon.setTextScale(CONFIG.TEXT_SCALE)
    monitorName = peripheral.getName(mon)
    applyPalette()

    if not bridge then
        local termObj, w, h = getBuffer()
        fillLine(termObj, 1, colors.gray)
        writeAt(termObj, 2, 1, CONFIG.TITLE, colors.white, colors.gray)
        centerText(termObj, math.floor(h / 2), "rs_bridge non detecte", colors.red, colors.black)
        drawFooter(termObj, w, h)
        backBuffer.setVisible(true)
        return
    end

    local data = buildData()

    pushHistory(history.items, data.items.used)
    pushHistory(history.fluids, data.fluids.used)
    pushHistory(history.energy, data.energy.stored)

    drawScreen(data)
end

render()
local timer = os.startTimer(CONFIG.REFRESH_INTERVAL)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
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
        bridge = peripheral.find("rs_bridge") or peripheral.find("rsBridge")
        mon = peripheral.find("monitor") or mon

        if mon then
            monitorName = peripheral.getName(mon)
            mon.setTextScale(CONFIG.TEXT_SCALE)
            applyPalette()
        end

        render()
    end
end
