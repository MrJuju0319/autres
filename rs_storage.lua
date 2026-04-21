-- =========================================================
-- Refined Storage Dashboard V5
-- Anti-flicker / Auto-update / Multi-pages / Alerts by category
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

    -- rafraichissement visuel rapide
    refreshInterval = 1,

    -- donnees lourdes (getItems / getFluids / getCells)
    slowRefreshInterval = 10,

    -- historique
    historySize = 48,
    showGraph = false,

    -- pages
    autoCyclePages = true,
    autoCycleSeconds = 12,
    showDiskDetailsPage = true,

    -- categories vides
    showEmptyCategories = false,

    -- limite d'affichage sur page details disques
    maxDisksPerPage = 10,

    -- ordre d'affichage preferentiel
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

    -- detection des categories via nom / tags
    categoryRules = {
        { key = "energy_disk", label = "Disques energie", patterns = { "energy" } },
        { key = "source",      label = "Source",           patterns = { "source" } },
        { key = "fluid",       label = "Disques fluides",  patterns = { "fluid", "liquid" } },
        { key = "chemical",    label = "Chemical",         patterns = { "chemical" } },
        { key = "gas",         label = "Gas",              patterns = { "gas" } },
        { key = "infusion",    label = "Infusion",         patterns = { "infusion" } },
        { key = "pigment",     label = "Pigment",          patterns = { "pigment" } },
        { key = "slurry",      label = "Slurry",           patterns = { "slurry" } },
        { key = "item",        label = "Disques items",    patterns = { "storage disk", "item disk", "disk" } },
    },

    alerts = {
        enabled = {
            -- vue principale
            items = true,
            fluids = true,
            energy = true,

            -- categories de disques
            item = true,
            fluid = true,
            energy_disk = true,
            source = true,
            chemical = true,
            gas = true,
            infusion = true,
            pigment = true,
            slurry = true,
            other = false, -- change a true si tu veux aussi surveiller "other"
        },

        thresholds = {
            -- vue principale
            items =      { warn = 80, danger = 95, inverse = false },
            fluids =     { warn = 80, danger = 95, inverse = false },
            energy =     { warn = 20, danger = 5,  inverse = true  },

            -- categories de disques
            item =       { warn = 80, danger = 95, inverse = false },
            fluid =      { warn = 80, danger = 95, inverse = false },
            energy_disk ={ warn = 20, danger = 5,  inverse = true  },
            source =     { warn = 80, danger = 95, inverse = false },
            chemical =   { warn = 80, danger = 95, inverse = false },
            gas =        { warn = 80, danger = 95, inverse = false },
            infusion =   { warn = 80, danger = 95, inverse = false },
            pigment =    { warn = 80, danger = 95, inverse = false },
            slurry =     { warn = 80, danger = 95, inverse = false },
            other =      { warn = 90, danger = 98, inverse = false },

            default =    { warn = 80, danger = 95, inverse = false },
        }
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

local monitorSide = peripheral.getName(mon)
mon.setTextScale(CONFIG.monitorScale)

-- =========================
-- STATE
-- =========================
local history = {
    items = {},
    fluids = {},
    energy = {},
}

local ui = {
    currentPage = 1,
    autoCycle = CONFIG.autoCyclePages,
}

local lastFrame = {}
local lastSizeX, lastSizeY = 0, 0
local latestData = nil
local latestPages = {}
local latestPageCount = 1

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
        return ">30j"
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

local function lowerContains(s, needle)
    return string.find(string.lower(s or ""), string.lower(needle), 1, true) ~= nil
end

local function getAlertConfig(key)
    return CONFIG.alerts.thresholds[key]
        or CONFIG.alerts.thresholds.default
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

local function categoryOrderIndex(key)
    return CONFIG.categoryOrder[key] or 999
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
    end

    if categoryKey == "fluid" then
        local n = lower:match("(%d+)%s*[b]")
        if n then
            -- buckets -> mB
            return tonumber(n) * 1000
        end
    end

    if categoryKey == "source" then
        local n = lower:match("(%d+)%s*[b]")
        if n then
            return tonumber(n)
        end
    end

    if categoryKey == "energy_disk" then
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

local function aggregateCategories(cells)
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
        cat.percent = percent(cat.used, cat.total)
        cat.alert = buildAlert(cat.key, cat.percent, nil)

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

local function refreshSlowData(force)
    local t = nowSec()
    if not force and (t - slowCache.lastRefresh) < CONFIG.slowRefreshInterval then
        return
    end

    local items = safe(function() return bridge.getItems() end, {}) or {}
    local fluids = safe(function() return bridge.getFluids() end, {}) or {}

    slowCache.itemTypes = #items
    slowCache.fluidTypes = #fluids
    slowCache.cells = getCellsData()
    slowCache.categories = aggregateCategories(slowCache.cells)
    slowCache.lastRefresh = t
end

-- =========================
-- DATA
-- =========================
local function getData()
    refreshSlowData(false)

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

    local pItems = percent(usedItems, totalItems)
    local pFluids = percent(usedFluids, totalFluids)
    local pEnergy = percent(storedEnergy, energyTotal)

    local charging = energyStats.deltaPerSec > 1

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
            if eta == ">30j" then
                eta = "long"
            end
        end
    elseif energyStats.deltaPerSec < -1 then
        trend = "Decharge"
        if storedEnergy > 0 then
            eta = formatDuration(storedEnergy / math.abs(energyStats.deltaPerSec))
            if eta == ">30j" then
                eta = "long"
            end
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
        cells = slowCache.cells,
        diskCount = #slowCache.cells,
        network = {
            online = online,
            connected = connected,
        }
    }
end

-- =========================
-- PAGES
-- =========================
local function buildPages(data)
    local _, h = size()
    local pages = {
        { kind = "overview", label = "Vue d'ensemble" }
    }

    if #data.categories > 0 then
        local perPage = math.max(1, h - 5)
        local start = 1
        while start <= #data.categories do
            pages[#pages + 1] = {
                kind = "categories",
                label = "Categories disques",
                start = start,
                count = perPage,
            }
            start = start + perPage
        end
    end

    if CONFIG.showDiskDetailsPage and #data.cells > 0 then
        local perPage = math.max(1, math.min(CONFIG.maxDisksPerPage, h - 5))
        local start = 1
        while start <= #data.cells do
            pages[#pages + 1] = {
                kind = "disks",
                label = "Details disques",
                start = start,
                count = perPage,
            }
            start = start + perPage
        end
    end

    return pages
end

-- =========================
-- BUILD UI
-- =========================
local function buildHeader(frame, titleText, statusText, pageNum, pageCount)
    local w = size()

    local right = statusText .. "  P" .. tostring(pageNum) .. "/" .. tostring(pageCount)
    local left = trim(CONFIG.title .. " - " .. titleText, math.max(1, w - #right - 1))

    if #left < (w - #right) then
        left = left .. string.rep(" ", (w - #right) - #left)
    end

    writeLine(frame, 1, trim(left .. right, w), colors.cyan)
    writeLine(frame, 2, string.rep("-", w), colors.gray)
end

local function buildFooter(frame, pageCount)
    local w, h = size()
    local autoTxt = ui.autoCycle and "AUTO ON" or "AUTO OFF"
    local footer = "[<] page | [A] " .. autoTxt .. " | [>] page"
    writeLine(frame, h, trim(footer, w), colors.lightGray)
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

    local alertText = alert and alert.text or "N/A"
    local right = tostring(p) .. "% " .. alertText
    local middleWidth = math.max(1, w - #right - 1)

    local line1 = trim(left, middleWidth)
    if #line1 < middleWidth then
        line1 = line1 .. string.rep(" ", middleWidth - #line1)
    end
    line1 = line1 .. right

    local lineColor = alert and alert.color or color
    writeLine(frame, y, line1, lineColor)
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

local function buildOverviewPage(frame, data, pageNum, pageCount, titleText)
    local statusText = "ONLINE"
    if data.network.online == false then
        statusText = "OFFLINE"
    elseif data.network.connected == false then
        statusText = "DISCONNECT"
    end

    buildHeader(frame, titleText, statusText, pageNum, pageCount)

    local y = 3
    y = buildMetric(frame, y, "Items", data.items.used, data.items.total, "", data.items.alert, history.items)
    y = buildMetric(frame, y, "Fluides", data.fluids.used, data.fluids.total, "mB", data.fluids.alert, history.fluids)
    y = buildEnergySection(frame, y, data.energy)

    local _, h = size()
    if y <= h - 2 then
        local summary = "ITM:" .. data.items.alert.text .. " | FLD:" .. data.fluids.alert.text .. " | NRG:" .. data.energy.alert.text
        local sev = math.max(data.items.alert.severity or 0, data.fluids.alert.severity or 0, data.energy.alert.severity or 0)
        local summaryColor = colors.lime
        if sev >= 2 then
            summaryColor = colors.red
        elseif sev == 1 then
            summaryColor = colors.orange
        elseif (not data.items.alert.enabled) and (not data.fluids.alert.enabled) and (not data.energy.alert.enabled) then
            summaryColor = colors.gray
        end
        writeLine(frame, y, summary, summaryColor)
        y = y + 1
    end

    if y <= h - 2 then
        local footerInfo = "Types items: " .. tostring(data.items.types) .. " | Types fluides: " .. tostring(data.fluids.types) .. " | Disques: " .. tostring(data.diskCount)
        writeLine(frame, y, footerInfo, colors.lightGray)
    end

    buildFooter(frame, pageCount)
end

local function buildCategoriesPage(frame, data, page, pageNum, pageCount)
    local statusText = "CATS"
    buildHeader(frame, page.label, statusText, pageNum, pageCount)

    local _, h = size()
    local y = 3

    writeLine(frame, y, "Categories detectees via getCells()", colors.cyan)
    y = y + 1
    writeLine(frame, y, string.rep("-", size()), colors.gray)
    y = y + 1

    local startIndex = page.start
    local endIndex = math.min(#data.categories, startIndex + page.count - 1)

    for i = startIndex, endIndex do
        if y > h - 2 then break end
        local cat = data.categories[i]
        local pctText = (cat.total > 0) and (tostring(cat.percent) .. "%") or "n/a"
        local alertText = cat.alert.text
        local left = cat.label .. " x" .. tostring(cat.count)
        local mid = formatNumber(cat.used) .. "/" .. formatNumber(cat.total)
        local right = pctText .. " " .. alertText

        local line = left .. " | " .. mid .. " | " .. right
        writeLine(frame, y, line, cat.alert.color)
        y = y + 1
    end

    if y <= h - 2 then
        local info = "Categories: " .. tostring(#data.categories) .. " | Cells: " .. tostring(#data.cells)
        writeLine(frame, y, info, colors.lightGray)
    end

    buildFooter(frame, pageCount)
end

local function buildDisksPage(frame, data, page, pageNum, pageCount)
    local statusText = "DISKS"
    buildHeader(frame, page.label, statusText, pageNum, pageCount)

    local _, h = size()
    local y = 3

    writeLine(frame, y, "Details disques detectes", colors.cyan)
    y = y + 1
    writeLine(frame, y, string.rep("-", size()), colors.gray)
    y = y + 1

    local startIndex = page.start
    local endIndex = math.min(#data.cells, startIndex + page.count - 1)

    for i = startIndex, endIndex do
        if y > h - 2 then break end
        local c = data.cells[i]
        local line = "[" .. i .. "] " .. c.name
            .. " | " .. formatNumber(c.stored) .. "/" .. formatNumber(c.capacity)
            .. " | " .. c.label
        writeLine(frame, y, line, colors.yellow)
        y = y + 1
    end

    if y <= h - 2 then
        local info = "Affiche " .. tostring(startIndex) .. "-" .. tostring(endIndex) .. " / " .. tostring(#data.cells)
        writeLine(frame, y, info, colors.lightGray)
    end

    buildFooter(frame, pageCount)
end

local function buildFrame(data, page, pageNum, pageCount)
    local frame = newFrame()

    if page.kind == "overview" then
        buildOverviewPage(frame, data, pageNum, pageCount, page.label)
    elseif page.kind == "categories" then
        buildCategoriesPage(frame, data, page, pageNum, pageCount)
    elseif page.kind == "disks" then
        buildDisksPage(frame, data, page, pageNum, pageCount)
    else
        buildOverviewPage(frame, data, pageNum, pageCount, "Vue d'ensemble")
    end

    return frame
end

-- =========================
-- NAVIGATION
-- =========================
local function clampPage()
    if ui.currentPage < 1 then ui.currentPage = 1 end
    if ui.currentPage > latestPageCount then ui.currentPage = latestPageCount end
end

local function nextPage()
    ui.currentPage = ui.currentPage + 1
    if ui.currentPage > latestPageCount then
        ui.currentPage = 1
    end
end

local function prevPage()
    ui.currentPage = ui.currentPage - 1
    if ui.currentPage < 1 then
        ui.currentPage = latestPageCount
    end
end

local function handleTouch(x, y)
    local w, h = size()
    if y ~= h then
        return
    end

    local third = math.floor(w / 3)
    if x <= third then
        ui.autoCycle = false
        prevPage()
    elseif x <= third * 2 then
        ui.autoCycle = not ui.autoCycle
    else
        ui.autoCycle = false
        nextPage()
    end
end

-- =========================
-- LOOPS
-- =========================
local function renderLoop()
    while true do
        latestData = getData()

        pushHistory(history.items, latestData.items.used)
        pushHistory(history.fluids, latestData.fluids.used)
        pushHistory(history.energy, latestData.energy.stored)

        latestPages = buildPages(latestData)
        latestPageCount = math.max(1, #latestPages)
        clampPage()

        local page = latestPages[ui.currentPage] or latestPages[1]
        local frame = buildFrame(latestData, page, ui.currentPage, latestPageCount)
        renderFrame(frame)

        sleep(CONFIG.refreshInterval)
    end
end

local function autoPageLoop()
    while true do
        sleep(CONFIG.autoCycleSeconds)
        if ui.autoCycle and latestPageCount > 1 then
            nextPage()
        end
    end
end

local function eventLoop()
    while true do
        local ev, side, x, y = os.pullEvent()

        if ev == "monitor_touch" and side == monitorSide then
            handleTouch(x, y)
        elseif ev == "monitor_resize" then
            slowCache.lastRefresh = 0
        end
    end
end

parallel.waitForAny(renderLoop, autoPageLoop, eventLoop)
