-- =========================================================
-- Refined Storage Dashboard V5 - Single Page
-- Anti-flicker / Auto-update / Alerts / Disk category summary
-- =========================================================

-- =========================
-- AUTO UPDATE
-- =========================
local CURRENT_FILE = "startup"
if shell and shell.getRunningProgram then
    local p = shell.getRunningProgram()
    if p and p ~= "" then
        CURRENT_FILE = p
    end
end

local AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/rs_storage.lua"
local AUTO_UPDATE_ENABLED = true
local AUTO_UPDATE_FILE = CURRENT_FILE
local AUTO_UPDATE_TMP = CURRENT_FILE .. ".tmp"

local function autoUpdate()
    if not AUTO_UPDATE_ENABLED then
        return
    end

    if not http then
        print("HTTP indisponible, auto-update ignore.")
        return
    end

    if fs.exists(AUTO_UPDATE_TMP) then
        fs.delete(AUTO_UPDATE_TMP)
    end

    print("Verification mise a jour...")

    local ok = pcall(function()
        shell.run("wget", AUTO_UPDATE_URL, AUTO_UPDATE_TMP)
    end)

    if not ok or not fs.exists(AUTO_UPDATE_TMP) then
        print("Echec du telechargement.")
        return
    end

    local h = fs.open(AUTO_UPDATE_TMP, "r")
    local newContent = h and h.readAll() or nil
    if h then h.close() end

    if not newContent or newContent == "" then
        print("Fichier telecharge vide.")
        if fs.exists(AUTO_UPDATE_TMP) then
            fs.delete(AUTO_UPDATE_TMP)
        end
        return
    end

    local oldContent = nil
    if fs.exists(AUTO_UPDATE_FILE) then
        local old = fs.open(AUTO_UPDATE_FILE, "r")
        if old then
            oldContent = old.readAll()
            old.close()
        end
    end

    if oldContent == newContent then
        fs.delete(AUTO_UPDATE_TMP)
        return
    end

    if fs.exists(AUTO_UPDATE_FILE) then
        fs.delete(AUTO_UPDATE_FILE)
    end

    fs.move(AUTO_UPDATE_TMP, AUTO_UPDATE_FILE)
    print("Mise a jour appliquee, redemarrage...")
    sleep(1)
    os.reboot()
end

autoUpdate()

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    title = "Refined Storage Dashboard v5",
    monitorScale = 0.5,

    refreshInterval = 1,
    slowRefreshInterval = 10,

    historySize = 48,
    showGraph = false,

    showDiskCategorySummary = true,
    showEmptyCategories = false,

    categoryRules = {
        { key = "energy_disk", label = "Energie",   patterns = { "energy" } },
        { key = "source",      label = "Source",    patterns = { "source" } },
        { key = "fluid",       label = "Fluides",   patterns = { "fluid", "liquid" } },
        { key = "chemical",    label = "Chemical",  patterns = { "chemical" } },
        { key = "gas",         label = "Gas",       patterns = { "gas" } },
        { key = "infusion",    label = "Infusion",  patterns = { "infusion" } },
        { key = "pigment",     label = "Pigment",   patterns = { "pigment" } },
        { key = "slurry",      label = "Slurry",    patterns = { "slurry" } },
        { key = "item",        label = "Items",     patterns = { "storage disk", "item disk", "disk" } },
    },

    categoryOrder = {
        item = 1,
        fluid = 2,
        energy_disk = 3,
        source = 4,
        chemical = 5,
        gas = 6,
        infusion = 7,
        pigment = 8,
        slurry = 9,
        other = 99,
    },

    alerts = {
        enabled = {
            items = true,
            fluids = true,
            energy = true,

            item = true,
            fluid = true,
            energy_disk = true,
            source = true,
            chemical = true,
            gas = true,
            infusion = true,
            pigment = true,
            slurry = true,
            other = false,
        },

        thresholds = {
            items =       { warn = 80, danger = 95, inverse = false },
            fluids =      { warn = 80, danger = 95, inverse = false },
            energy =      { warn = 20, danger = 5,  inverse = true  },

            item =        { warn = 80, danger = 95, inverse = false },
            fluid =       { warn = 80, danger = 95, inverse = false },
            energy_disk = { warn = 20, danger = 5,  inverse = true  },
            source =      { warn = 80, danger = 95, inverse = false },
            chemical =    { warn = 80, danger = 95, inverse = false },
            gas =         { warn = 80, danger = 95, inverse = false },
            infusion =    { warn = 80, danger = 95, inverse = false },
            pigment =     { warn = 80, danger = 95, inverse = false },
            slurry =      { warn = 80, danger = 95, inverse = false },
            other =       { warn = 90, danger = 98, inverse = false },

            default =     { warn = 80, danger = 95, inverse = false },
        }
    },

    abbreviations = {
        item = "ITD",
        fluid = "FLD",
        energy_disk = "ENG",
        source = "SRC",
        chemical = "CHM",
        gas = "GAS",
        infusion = "INF",
        pigment = "PGM",
        slurry = "SLR",
        other = "OTH",
    }
}

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

mon.setTextScale(CONFIG.monitorScale)

-- =========================
-- STATE
-- =========================
local history = {
    items = {},
    fluids = {},
    energy = {},
}

local lastFrame = {}
local lastSizeX, lastSizeY = 0, 0

local energyStats = {
    lastStored = nil,
    lastTime = nil,
    deltaPerSec = 0,
    avgInput = 0,
}

local slowCache = {
    lastRefresh = 0,
    itemTypes = 0,
    fluidTypes = 0,
    cells = {},
    categories = {},
}

-- =========================
-- UTILS
-- =========================
local function nowSec()
    return os.epoch("utc") / 1000
end

local function safe(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
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

local function toNumber(v, default)
    v = tonumber(v)
    if v == nil then return default or 0 end
    return v
end

local function percent(used, total)
    used = tonumber(used) or 0
    total = tonumber(total) or 0
    if total <= 0 then return 0 end

    local p = math.floor((used / total) * 100 + 0.5)
    if p < 0 then p = 0 end
    if p > 100 then p = 100 end
    return p
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

local function formatDuration(seconds)
    seconds = tonumber(seconds)

    if not seconds or seconds == math.huge or seconds < 0 then
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

local function pushHistory(tbl, value)
    tbl[#tbl + 1] = tonumber(value) or 0
    while #tbl > CONFIG.historySize do
        table.remove(tbl, 1)
    end
end

local function graphString(width, values)
    width = math.max(1, width)

    local count = #values
    if count == 0 then
        return string.rep(".", width)
    end

    local startIndex = math.max(1, count - width + 1)
    local maxVal = 0

    for i = startIndex, count do
        if values[i] > maxVal then
            maxVal = values[i]
        end
    end

    if maxVal <= 0 then maxVal = 1 end

    local chars = {}
    for i = startIndex, count do
        local ratio = values[i] / maxVal
        if ratio >= 0.875 then
            chars[#chars + 1] = "#"
        elseif ratio >= 0.625 then
            chars[#chars + 1] = "="
        elseif ratio >= 0.375 then
            chars[#chars + 1] = "-"
        elseif ratio >= 0.125 then
            chars[#chars + 1] = "."
        else
            chars[#chars + 1] = " "
        end
    end

    while #chars < width do
        table.insert(chars, 1, " ")
    end

    return table.concat(chars)
end

local function barString(width, used, total)
    width = math.max(1, width)
    used = tonumber(used) or 0
    total = tonumber(total) or 0

    local filled = 0
    if total > 0 then
        filled = math.floor((used / total) * width + 0.5)
        if filled < 0 then filled = 0 end
        if filled > width then filled = width end
    end

    return string.rep("#", filled) .. string.rep("-", width - filled)
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

local function categoryOrderIndex(key)
    return CONFIG.categoryOrder[key] or 999
end

local function getAlertConfig(key)
    return CONFIG.alerts.thresholds[key] or CONFIG.alerts.thresholds.default
end

local function isAlertEnabled(key)
    local value = CONFIG.alerts.enabled[key]
    if value == nil then
        return true
    end
    return value
end

local function buildAlert(key, pct, context)
    if pct == nil then
        return { text = "N/A", color = colors.gray, severity = 0, enabled = false }
    end

    if not isAlertEnabled(key) then
        return { text = "OFF", color = colors.gray, severity = 0, enabled = false }
    end

    local cfg = getAlertConfig(key)
    local warn = cfg.warn or 80
    local danger = cfg.danger or 95
    local inverse = cfg.inverse == true

    if inverse then
        if pct <= danger then
            if context and context.charging then
                return { text = "LOW+", color = colors.orange, severity = 1, enabled = true }
            end
            return { text = "CRIT", color = colors.red, severity = 2, enabled = true }
        elseif pct <= warn then
            return { text = "LOW", color = colors.orange, severity = 1, enabled = true }
        else
            return { text = "OK", color = colors.lime, severity = 0, enabled = true }
        end
    else
        if pct >= danger then
            return { text = "CRIT", color = colors.red, severity = 2, enabled = true }
        elseif pct >= warn then
            return { text = "WARN", color = colors.orange, severity = 1, enabled = true }
        else
            return { text = "OK", color = colors.lime, severity = 0, enabled = true }
        end
    end
end

-- =========================
-- FRAME BUFFER
-- =========================
local function newFrame()
    local w, h = size()
    local frame = {}

    for y = 1, h do
        frame[y] = {
            text = string.rep(" ", w),
            fg = colors.white,
            bg = colors.black,
        }
    end

    return frame
end

local function writeLine(frame, y, text, fg, bg)
    local w, h = size()
    if y < 1 or y > h then return end

    text = trim(text or "", w)
    if #text < w then
        text = text .. string.rep(" ", w - #text)
    end

    frame[y] = {
        text = text,
        fg = fg or colors.white,
        bg = bg or colors.black,
    }
end

local function renderFrame(frame)
    local w, h = size()

    if w ~= lastSizeX or h ~= lastSizeY then
        mon.setBackgroundColor(colors.black)
        mon.clear()
        lastFrame = {}
        lastSizeX, lastSizeY = w, h
    end

    for y = 1, h do
        local old = lastFrame[y]
        local new = frame[y]

        local changed = (not old)
            or old.text ~= new.text
            or old.fg ~= new.fg
            or old.bg ~= new.bg

        if changed then
            mon.setCursorPos(1, y)
            mon.setTextColor(new.fg)
            mon.setBackgroundColor(new.bg)
            mon.write(new.text)
        end
    end

    mon.setBackgroundColor(colors.black)
    lastFrame = frame
end

-- =========================
-- ENERGY STATS
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
            energyStats.deltaPerSec = (energyStats.deltaPerSec * 0.7) + (instantDeltaPerSec * 0.3)
        end
    end

    energyStats.lastStored = storedEnergy
    energyStats.lastTime = now
    energyStats.avgInput = avgInput
end

-- =========================
-- CELLS / CATEGORIES
-- =========================
local function parseCapacityFromName(name, categoryKey)
    local lower = string.lower(name or "")

    if lower:find("infinite", 1, true) then
        return 0
    end

    if categoryKey == "item" then
        local n, suffix = lower:match("(%d+)%s*([kmgte])")
        if n and suffix then
            local powers = { k = 1, m = 2, g = 3, t = 4, e = 5 }
            return tonumber(n) * (1000 ^ (powers[suffix] or 0))
        end
    elseif categoryKey == "fluid" then
        local n = lower:match("(%d+)%s*[b]")
        if n then
            return tonumber(n) * 1000
        end
    elseif categoryKey == "source" then
        local n = lower:match("(%d+)%s*[b]")
        if n then
            return tonumber(n)
        end
    elseif categoryKey == "energy_disk" then
        local n, suffix = lower:match("(%d+)%s*([kmgte])")
        if n and suffix then
            local powers = { k = 1, m = 2, g = 3, t = 4, e = 5 }
            return tonumber(n) * (1000 ^ (powers[suffix] or 0))
        end
    end

    return 0
end

local function detectCategoryKey(name, tagsText)
    local blob = string.lower((name or "") .. " " .. (tagsText or ""))

    for _, rule in ipairs(CONFIG.categoryRules) do
        for _, pattern in ipairs(rule.patterns) do
            if blob:find(string.lower(pattern), 1, true) then
                return rule.key, rule.label
            end
        end
    end

    return "other", "Autres"
end

local function normalizeCell(cell)
    local nested = firstExisting(cell, {
        "resource", "item", "cell", "stack", "resourceStack"
    }, nil)

    local name = tostring(
        firstExisting(cell, { "displayName", "display_name", "name", "id", "item" }, nil)
        or firstExisting(nested, { "displayName", "display_name", "name", "id", "item" }, "Disque inconnu")
    )

    local tags = firstExisting(cell, { "tags" }, nil) or firstExisting(nested, { "tags" }, nil)
    local tagsText = ""
    if type(tags) == "table" then
        tagsText = table.concat(tags, " ")
    end

    local categoryKey, categoryLabel = detectCategoryKey(name, tagsText)

    local stored = toNumber(
        firstExisting(cell, { "stored", "used", "amount", "value", "count" }, nil)
        or firstExisting(nested, { "stored", "used", "amount", "value" }, 0),
        0
    )

    local capacity = toNumber(
        firstExisting(cell, { "capacity", "total", "max", "maxStorage", "size" }, nil)
        or firstExisting(nested, { "capacity", "total", "max", "maxStorage", "size" }, 0),
        0
    )

    if capacity <= 0 then
        capacity = parseCapacityFromName(name, categoryKey)
    end

    return {
        raw = cell,
        name = name,
        stored = stored,
        capacity = capacity,
        key = categoryKey,
        label = categoryLabel,
    }
end

local function getCellsData()
    local rawCells = safe(function() return bridge.getCells() end, {}) or {}
    local cells = {}

    if type(rawCells) ~= "table" then
        return cells
    end

    for _, cell in ipairs(rawCells) do
        if type(cell) == "table" then
            local c = normalizeCell(cell)
            if CONFIG.showEmptyCategories or c.stored > 0 or c.capacity > 0 or c.name ~= "Disque inconnu" then
                cells[#cells + 1] = c
            end
        end
    end

    table.sort(cells, function(a, b)
        local oa = categoryOrderIndex(a.key)
        local ob = categoryOrderIndex(b.key)
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)

    return cells
end

local function aggregateCategories(cells, charging)
    local map = {}

    for _, cell in ipairs(cells) do
        local key = cell.key or "other"
        if not map[key] then
            map[key] = {
                key = key,
                label = cell.label or key,
                used = 0,
                total = 0,
                count = 0,
            }
        end

        map[key].used = map[key].used + (cell.stored or 0)
        map[key].total = map[key].total + (cell.capacity or 0)
        map[key].count = map[key].count + 1
    end

    local categories = {}
    for _, cat in pairs(map) do
        if cat.total > 0 then
            cat.percent = percent(cat.used, cat.total)
        else
            cat.percent = nil
        end

        cat.alert = buildAlert(cat.key, cat.percent, { charging = charging })

        if CONFIG.showEmptyCategories or cat.used > 0 or cat.total > 0 then
            categories[#categories + 1] = cat
        end
    end

    table.sort(categories, function(a, b)
        local oa = categoryOrderIndex(a.key)
        local ob = categoryOrderIndex(b.key)
        if oa ~= ob then return oa < ob end
        return a.label < b.label
    end)

    return categories
end

local function refreshSlowData(charging)
    local t = nowSec()
    if (t - slowCache.lastRefresh) < CONFIG.slowRefreshInterval then
        -- on met juste a jour les alertes categories avec le contexte "charging"
        slowCache.categories = aggregateCategories(slowCache.cells, charging)
        return
    end

    local items = safe(function() return bridge.getItems() end, {}) or {}
    local fluids = safe(function() return bridge.getFluids() end, {}) or {}

    slowCache.itemTypes = #items
    slowCache.fluidTypes = #fluids
    slowCache.cells = getCellsData()
    slowCache.categories = aggregateCategories(slowCache.cells, charging)
    slowCache.lastRefresh = t
end

-- =========================
-- DATA
-- =========================
local function getData()
    local usedItems = toNumber(safe(function() return bridge.getUsedItemStorage() end, 0), 0)
    local totalItems = toNumber(safe(function() return bridge.getTotalItemStorage() end, 0), 0)

    local usedFluids = toNumber(safe(function() return bridge.getUsedFluidStorage() end, 0), 0)
    local totalFluids = toNumber(safe(function() return bridge.getTotalFluidStorage() end, 0), 0)

    local storedEnergy = toNumber(
        safe(function() return bridge.getStoredEnergy() end,
            safe(function() return bridge.getEnergyUsage() end, 0)
        ),
        0
    )

    local energyTotal = toNumber(safe(function() return bridge.getEnergyCapacity() end, 0), 0)
    local avgInput = toNumber(safe(function() return bridge.getAverageEnergyInput() end, 0), 0)

    local online = safe(function() return bridge.isOnline() end, nil)
    local connected = safe(function() return bridge.isConnected() end, nil)

    updateEnergyStats(storedEnergy, avgInput)

    local charging = energyStats.deltaPerSec > 1
    refreshSlowData(charging)

    local pItems = percent(usedItems, totalItems)
    local pFluids = percent(usedFluids, totalFluids)
    local pEnergy = percent(storedEnergy, energyTotal)

    local itemAlert = buildAlert("items", pItems, nil)
    local fluidAlert = buildAlert("fluids", pFluids, nil)
    local energyAlert = buildAlert("energy", pEnergy, { charging = charging })

    local trend = "Stable"
    local eta = "--"

    if energyStats.deltaPerSec > 1 then
        trend = "Charge"
        local remaining = energyTotal - storedEnergy
        if remaining > 0 then
            eta = formatDuration(remaining / energyStats.deltaPerSec)
        end
    elseif energyStats.deltaPerSec < -1 then
        trend = "Decharge"
        if storedEnergy > 0 then
            eta = formatDuration(storedEnergy / math.abs(energyStats.deltaPerSec))
        end
    end

    return {
        items = {
            used = usedItems,
            total = totalItems,
            types = slowCache.itemTypes,
            percent = pItems,
            alert = itemAlert,
        },
        fluids = {
            used = usedFluids,
            total = totalFluids,
            types = slowCache.fluidTypes,
            percent = pFluids,
            alert = fluidAlert,
        },
        energy = {
            stored = storedEnergy,
            total = energyTotal,
            percent = pEnergy,
            inputAvg = energyStats.avgInput,
            deltaPerSec = energyStats.deltaPerSec,
            trend = trend,
            eta = eta,
            charging = charging,
            alert = energyAlert,
        },
        categories = slowCache.categories,
        diskCount = #slowCache.cells,
        network = {
            online = online,
            connected = connected,
        }
    }
end

-- =========================
-- BUILD UI
-- =========================
local function buildHeader(frame, data)
    local w = size()

    local statusText = "ONLINE"
    if data.network.online == false then
        statusText = "OFFLINE"
    elseif data.network.connected == false then
        statusText = "DISCONNECT"
    end

    local right = statusText
    local left = trim(CONFIG.title, math.max(1, w - #right - 1))

    if #left < (w - #right) then
        left = left .. string.rep(" ", (w - #right) - #left)
    end

    writeLine(frame, 1, trim(left .. right, w), colors.cyan)
    writeLine(frame, 2, string.rep("-", w), colors.gray)
end

local function buildMetric(frame, y, title, used, total, unit, alert, graphData)
    local w, h = size()
    if y > h - 1 then return y end

    local p = percent(used, total)
    local color = getPercentColor(p)

    writeLine(frame, y, title, colors.cyan)
    y = y + 1
    if y > h - 1 then return y end

    local left = formatNumber(used) .. " / " .. formatNumber(total)
    if unit and unit ~= "" then
        left = left .. " " .. unit
    end

    local right = tostring(p) .. "% " .. (alert and alert.text or "N/A")
    local middleWidth = math.max(1, w - #right - 1)

    local line1 = trim(left, middleWidth)
    if #line1 < middleWidth then
        line1 = line1 .. string.rep(" ", middleWidth - #line1)
    end
    line1 = line1 .. right

    writeLine(frame, y, line1, alert and alert.color or color)
    y = y + 1
    if y > h - 1 then return y end

    writeLine(frame, y, barString(w, used, total > 0 and total or 1), color)
    y = y + 1

    if CONFIG.showGraph and y <= h - 2 then
        writeLine(frame, y, "Historique:", colors.lightGray)
        y = y + 1
        writeLine(frame, y, graphString(w, graphData), colors.lightBlue)
        y = y + 1
    end

    if y <= h - 1 then
        writeLine(frame, y, string.rep("-", w), colors.gray)
        y = y + 1
    end

    return y
end

local function buildEnergySection(frame, y, energy)
    local w, h = size()
    if y > h - 1 then return y end

    local color = getPercentColor(energy.percent)

    writeLine(frame, y, "Energie", colors.cyan)
    y = y + 1
    if y > h - 1 then return y end

    local left = formatNumber(energy.stored) .. " / " .. formatNumber(energy.total) .. " FE"
    local right = tostring(energy.percent) .. "% " .. energy.alert.text
    local middleWidth = math.max(1, w - #right - 1)

    local line1 = trim(left, middleWidth)
    if #line1 < middleWidth then
        line1 = line1 .. string.rep(" ", middleWidth - #line1)
    end
    line1 = line1 .. right
    writeLine(frame, y, line1, energy.alert.color)
    y = y + 1
    if y > h - 1 then return y end

    writeLine(frame, y, barString(w, energy.stored, energy.total > 0 and energy.total or 1), color)
    y = y + 1
    if y > h - 1 then return y end

    writeLine(frame, y, "Net: " .. formatRate(energy.deltaPerSec) .. " | " .. energy.trend, colors.lightBlue)
    y = y + 1
    if y > h - 1 then return y end

    writeLine(frame, y, "ETA: " .. energy.eta, colors.lightGray)
    y = y + 1

    if y <= h - 1 then
        writeLine(frame, y, string.rep("-", w), colors.gray)
        y = y + 1
    end

    return y
end

local function buildMainAlertLine(data)
    local sev = math.max(
        data.items.alert.severity or 0,
        data.fluids.alert.severity or 0,
        data.energy.alert.severity or 0
    )

    local color = colors.lime
    if sev >= 2 then
        color = colors.red
    elseif sev == 1 then
        color = colors.orange
    end

    return
        "ITM:" .. data.items.alert.text ..
        " | FLD:" .. data.fluids.alert.text ..
        " | NRG:" .. data.energy.alert.text,
        color
end

local function buildCategoryCountsLine(categories)
    local parts = {}
    local hidden = 0

    for _, cat in ipairs(categories) do
        local abbr = CONFIG.abbreviations[cat.key] or string.upper(string.sub(cat.key, 1, 3))
        local piece = abbr .. "x" .. tostring(cat.count)
        parts[#parts + 1] = piece
    end

    return "Cats: " .. table.concat(parts, " | ")
end

local function buildCategoryWarnLine(categories)
    local parts = {}
    local warningCount = 0

    for _, cat in ipairs(categories) do
        if cat.alert.enabled and (cat.alert.severity or 0) > 0 then
            local abbr = CONFIG.abbreviations[cat.key] or string.upper(string.sub(cat.key, 1, 3))
            parts[#parts + 1] = abbr .. ":" .. cat.alert.text
            warningCount = warningCount + 1
        end
    end

    if #parts == 0 then
        return "Cat warn: aucune", colors.lime
    end

    local color = colors.orange
    for _, cat in ipairs(categories) do
        if cat.alert.enabled and (cat.alert.severity or 0) >= 2 then
            color = colors.red
            break
        end
    end

    return "Cat warn: " .. table.concat(parts, " | "), color
end

local function buildFrame(data)
    local _, h = size()
    local frame = newFrame()

    buildHeader(frame, data)

    local y = 3
    y = buildMetric(frame, y, "Items", data.items.used, data.items.total, "", data.items.alert, history.items)
    y = buildMetric(frame, y, "Fluides", data.fluids.used, data.fluids.total, "mB", data.fluids.alert, history.fluids)
    y = buildEnergySection(frame, y, data.energy)

    if y <= h - 1 then
        local txt, color = buildMainAlertLine(data)
        writeLine(frame, y, txt, color)
        y = y + 1
    end

    if CONFIG.showDiskCategorySummary and y <= h - 1 then
        writeLine(frame, y, buildCategoryCountsLine(data.categories), colors.lightGray)
        y = y + 1
    end

    if CONFIG.showDiskCategorySummary and y <= h - 1 then
        local txt, color = buildCategoryWarnLine(data.categories)
        writeLine(frame, y, txt, color)
        y = y + 1
    end

    if y <= h - 1 then
        local footer = "Types items: " .. tostring(data.items.types)
            .. " | Types fluides: " .. tostring(data.fluids.types)
            .. " | Disques: " .. tostring(data.diskCount)
        writeLine(frame, y, footer, colors.lightGray)
    end

    return frame
end

-- =========================
-- LOOP
-- =========================
while true do
    local data = getData()

    pushHistory(history.items, data.items.used)
    pushHistory(history.fluids, data.fluids.used)
    pushHistory(history.energy, data.energy.stored)

    local frame = buildFrame(data)
    renderFrame(frame)

    sleep(CONFIG.refreshInterval)
end
