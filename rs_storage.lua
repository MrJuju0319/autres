-- =========================================================
-- Refined Storage Storage Dashboard v6
-- Style inspire de l'Autocraft Monitor v2
-- Une seule page / synthese / anti-scintillement
-- CC:Tweaked + rs_bridge
-- =========================================================

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/rs_storage.lua",
    AUTO_UPDATE_ENABLED = true,
    AUTO_UPDATE_FILE = "startup.lua",
    AUTO_UPDATE_TMP = "startup.lua.tmp",

    TITLE = "Refined Storage - Storage v6",
    TEXT_SCALE = 0.5,
    SIDE_PADDING = 2,
    HEADER_HEIGHT = 4,
    REFRESH_INTERVAL = 0.75,
    SLOW_REFRESH_INTERVAL = 10,
    ETA_SMOOTHING = 0.35,
    USE_CUSTOM_PALETTE = true,
    SHOW_FOOTER = true,

    SHOW_ALERT_SUMMARY = true,
    SHOW_CATEGORY_SUMMARY = true,
    SHOW_GRAPH = false,
    SHOW_EMPTY_CATEGORIES = false,

    CATEGORY_RULES = {
        { key = "energy_disk", label = "Energie",  patterns = { "energy" } },
        { key = "source",      label = "Source",   patterns = { "source" } },
        { key = "fluid",       label = "Fluides",  patterns = { "fluid", "liquid" } },
        { key = "chemical",    label = "Chemical", patterns = { "chemical" } },
        { key = "gas",         label = "Gas",      patterns = { "gas" } },
        { key = "infusion",    label = "Infusion", patterns = { "infusion" } },
        { key = "pigment",     label = "Pigment",  patterns = { "pigment" } },
        { key = "slurry",      label = "Slurry",   patterns = { "slurry" } },
        { key = "item",        label = "Items",    patterns = { "storage disk", "item disk", "disk" } },
    },

    CATEGORY_ORDER = {
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

    ABBR = {
        items = "ITM",
        fluids = "FLD",
        energy = "NRG",

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
    },

    ALERTS = {
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
            items       = { warn = 80, danger = 95, inverse = false },
            fluids      = { warn = 80, danger = 95, inverse = false },
            energy      = { warn = 20, danger = 5,  inverse = true  },

            item        = { warn = 80, danger = 95, inverse = false },
            fluid       = { warn = 80, danger = 95, inverse = false },
            energy_disk = { warn = 20, danger = 5,  inverse = true  },
            source      = { warn = 80, danger = 95, inverse = false },
            chemical    = { warn = 80, danger = 95, inverse = false },
            gas         = { warn = 80, danger = 95, inverse = false },
            infusion    = { warn = 80, danger = 95, inverse = false },
            pigment     = { warn = 80, danger = 95, inverse = false },
            slurry      = { warn = 80, danger = 95, inverse = false },
            other       = { warn = 90, danger = 98, inverse = false },

            default     = { warn = 80, danger = 95, inverse = false },
        }
    }
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
-- ETAT
-- =========================
local state = {
    frame = 1,
    lastError = nil,
    showAlertSummary = CONFIG.SHOW_ALERT_SUMMARY,
    showCategorySummary = CONFIG.SHOW_CATEGORY_SUMMARY,
}

local cache = {
    slowLastRefresh = 0,
    itemTypes = 0,
    fluidTypes = 0,
    cells = {},
    categories = {},
}

local history = {
    items = {},
    fluids = {},
    energy = {},
}

local energyStats = {
    lastStored = nil,
    lastTime = nil,
    deltaPerSec = 0,
    avgInput = 0,
}

local backBuffer

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

local function safe(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
end

local function nowSec()
    return os.epoch("utc") / 1000
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

local function formatRate(n)
    n = tonumber(n) or 0
    local sign = ""
    if n > 0 then sign = "+" end
    return sign .. formatNumber(n) .. "/s"
end

local function pushHistory(tbl, value)
    tbl[#tbl + 1] = tonumber(value) or 0
    while #tbl > 48 do
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

local function getAlertConfig(key)
    return CONFIG.ALERTS.thresholds[key] or CONFIG.ALERTS.thresholds.default
end

local function isAlertEnabled(key)
    local value = CONFIG.ALERTS.enabled[key]
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
    return CONFIG.CATEGORY_ORDER[key] or 999
end

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

    for _, rule in ipairs(CONFIG.CATEGORY_RULES) do
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
            if CONFIG.SHOW_EMPTY_CATEGORIES or c.stored > 0 or c.capacity > 0 or c.name ~= "Disque inconnu" then
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

        if CONFIG.SHOW_EMPTY_CATEGORIES or cat.used > 0 or cat.total > 0 then
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

local function refreshSlowData(charging, force)
    local now = nowSec()
    if not force and (now - cache.slowLastRefresh) < CONFIG.SLOW_REFRESH_INTERVAL then
        cache.categories = aggregateCategories(cache.cells, charging)
        return
    end

    local items = safe(function() return bridge.getItems() end, {}) or {}
    local fluids = safe(function() return bridge.getFluids() end, {}) or {}

    cache.itemTypes = #items
    cache.fluidTypes = #fluids
    cache.cells = getCellsData()
    cache.categories = aggregateCategories(cache.cells, charging)
    cache.slowLastRefresh = now
end

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

local function buildData()
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

    updateEnergyStats(storedEnergy, avgInput)

    local charging = energyStats.deltaPerSec > 1
    refreshSlowData(charging, false)

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
            eta = formatTime(remaining / energyStats.deltaPerSec)
        end
    elseif energyStats.deltaPerSec < -1 then
        trend = "Decharge"
        if storedEnergy > 0 then
            eta = formatTime(storedEnergy / math.abs(energyStats.deltaPerSec))
        end
    end

    local online = safe(function() return bridge.isOnline() end, nil)
    local connected = safe(function() return bridge.isConnected() end, nil)

    return {
        items = {
            used = usedItems,
            total = totalItems,
            types = cache.itemTypes,
            percent = pItems,
            alert = itemAlert,
        },
        fluids = {
            used = usedFluids,
            total = totalFluids,
            types = cache.fluidTypes,
            percent = pFluids,
            alert = fluidAlert,
        },
        energy = {
            stored = storedEnergy,
            total = energyTotal,
            percent = pEnergy,
            avgInput = avgInput,
            deltaPerSec = energyStats.deltaPerSec,
            trend = trend,
            eta = eta,
            alert = energyAlert,
        },
        categories = cache.categories,
        diskCount = #cache.cells,
        network = {
            online = online,
            connected = connected,
        }
    }
end

-- =========================
-- UI
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

applyPalette()

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

    local left = "Types I " .. tostring(data.items.types)
    local mid = "Disques " .. tostring(data.diskCount)
    local right = "Types F " .. tostring(data.fluids.types)

    writeAt(termObj, 2, 2, left, colors.lightBlue, colors.black)
    centerText(termObj, 2, mid, colors.lightGray, colors.black)
    writeAt(termObj, math.max(2, w - #right - 1), 2, right, colors.lightBlue, colors.black)

    local occ = math.max(data.items.percent or 0, data.fluids.percent or 0)
    local label = "Occupation max " .. tostring(occ) .. "%"
    drawProgressBar(termObj, 3, 3, math.max(10, w - 4), occ / 100, colors.green, colors.gray, label)

    local mainAlert = "ITM " .. data.items.alert.text .. " | FLD " .. data.fluids.alert.text .. " | NRG " .. data.energy.alert.text
    writeAt(termObj, 2, 4, trim(mainAlert, math.max(1, w - 18)), colors.lightBlue, colors.black)

    local modeText = "ALR:" .. (state.showAlertSummary and "ON" or "OFF") .. " CAT:" .. (state.showCategorySummary and "ON" or "OFF")
    writeAt(termObj, math.max(2, w - #modeText - 1), 4, modeText, colors.lightBlue, colors.black)
end

local function drawMetricCard(termObj, title, used, total, pct, alert, extra1, extra2, y, w, unit)
    fillLine(termObj, y, colors.gray)
    fillLine(termObj, y + 1, colors.black)
    fillLine(termObj, y + 2, colors.black)
    fillLine(termObj, y + 3, colors.black)
    fillLine(termObj, y + 4, colors.black)

    local innerX = 2
    local innerW = math.max(10, w - 2)

    local headRight = tostring(pct) .. "% " .. (alert and alert.text or "N/A")
    writeAt(termObj, innerX, y, title, colors.white, colors.gray, innerW - #headRight - 1)
    writeAt(termObj, math.max(innerX, w - #headRight), y, headRight, alert and alert.color or colors.lightGray, colors.gray)

    local main = formatNumber(used) .. " / " .. formatNumber(total)
    if unit and unit ~= "" then
        main = main .. " " .. unit
    end
    writeAt(termObj, innerX, y + 1, main, colors.white, colors.black)

    drawProgressBar(termObj, innerX, y + 2, w - 2, pct / 100, getPercentColor(pct), colors.gray, "")

    writeAt(termObj, innerX, y + 3, trim(extra1 or "", innerW), colors.lightBlue, colors.black)
    writeAt(termObj, innerX, y + 4, trim(extra2 or "", innerW), colors.lightGray, colors.black)
end

local function buildCategoryCountsLine(categories, maxWidth)
    local parts = {}

    for _, cat in ipairs(categories) do
        local abbr = CONFIG.ABBR[cat.key] or string.upper(string.sub(cat.key, 1, 3))
        local part = abbr .. "x" .. tostring(cat.count)
        parts[#parts + 1] = part
    end

    return trim("Cats: " .. table.concat(parts, " | "), maxWidth)
end

local function buildCategoryWarnLine(categories, maxWidth)
    local parts = {}
    local worst = 0

    for _, cat in ipairs(categories) do
        if cat.alert.enabled and (cat.alert.severity or 0) > 0 then
            local abbr = CONFIG.ABBR[cat.key] or string.upper(string.sub(cat.key, 1, 3))
            parts[#parts + 1] = abbr .. ":" .. cat.alert.text
            if cat.alert.severity > worst then
                worst = cat.alert.severity
            end
        end
    end

    if #parts == 0 then
        return "Cat warn: aucune", colors.lime
    end

    local color = (worst >= 2) and colors.red or colors.orange
    return trim("Cat warn: " .. table.concat(parts, " | "), maxWidth), color
end

local function drawFooter(termObj, w, h)
    if not CONFIG.SHOW_FOOTER or h < 8 then
        return
    end

    fillLine(termObj, h - 1, colors.black)
    fillLine(termObj, h, colors.black)

    local left = 2
    left = left + drawButton(termObj, left, h, "ALR", state.showAlertSummary) + 2
    left = left + drawButton(termObj, left, h, "CAT", state.showCategorySummary) + 2
    left = left + drawButton(termObj, left, h, "REF", false) + 2

    local info = "Synthese"
    writeAt(termObj, math.max(left, w - #info - 1), h, info, colors.cyan, colors.black)
end

local function drawScreen(data)
    local termObj, w, h = getBuffer()

    drawHeader(termObj, data, w)

    local y = CONFIG.HEADER_HEIGHT + 1

    drawMetricCard(
        termObj,
        "Items",
        data.items.used,
        data.items.total,
        data.items.percent,
        data.items.alert,
        "Types: " .. tostring(data.items.types),
        "Alerte: " .. data.items.alert.text,
        y,
        w,
        ""
    )
    y = y + 5

    drawMetricCard(
        termObj,
        "Fluides",
        data.fluids.used,
        data.fluids.total,
        data.fluids.percent,
        data.fluids.alert,
        "Types: " .. tostring(data.fluids.types),
        "Alerte: " .. data.fluids.alert.text,
        y,
        w,
        "mB"
    )
    y = y + 5

    drawMetricCard(
        termObj,
        "Energie",
        data.energy.stored,
        data.energy.total,
        data.energy.percent,
        data.energy.alert,
        "Net: " .. formatRate(data.energy.deltaPerSec) .. " | " .. data.energy.trend,
        "ETA: " .. data.energy.eta,
        y,
        w,
        "FE"
    )
    y = y + 5

    local maxBodyY = h - (CONFIG.SHOW_FOOTER and 2 or 0)

    while y <= maxBodyY do
        fillLine(termObj, y, colors.black)
        y = y + 1
    end

    y = CONFIG.HEADER_HEIGHT + 16

    if state.showAlertSummary and y <= maxBodyY then
        local summary = "Synthese alertes: ITM " .. data.items.alert.text .. " | FLD " .. data.fluids.alert.text .. " | NRG " .. data.energy.alert.text
        local severity = math.max(
            data.items.alert.severity or 0,
            data.fluids.alert.severity or 0,
            data.energy.alert.severity or 0
        )
        local color = colors.lime
        if severity >= 2 then color = colors.red
        elseif severity >= 1 then color = colors.orange end
        writeAt(termObj, 2, y, trim(summary, w - 2), color, colors.black)
        y = y + 1
    end

    if state.showCategorySummary and y <= maxBodyY then
        writeAt(termObj, 2, y, buildCategoryCountsLine(data.categories, w - 2), colors.lightGray, colors.black)
        y = y + 1

        local warnText, warnColor = buildCategoryWarnLine(data.categories, w - 2)
        writeAt(termObj, 2, y, warnText, warnColor, colors.black)
        y = y + 1
    end

    if y <= maxBodyY then
        local footerInfo = "Disques: " .. tostring(data.diskCount)
        writeAt(termObj, 2, y, footerInfo, colors.lightGray, colors.black)
    end

    drawFooter(termObj, w, h)
    backBuffer.setVisible(true)
end

-- =========================
-- INTERACTIONS
-- =========================
local function handleTouch(x, y)
    local w, h = mon.getSize()

    if CONFIG.SHOW_FOOTER and y == h then
        if x >= 2 and x <= 7 then
            state.showAlertSummary = not state.showAlertSummary
            return
        elseif x >= 9 and x <= 14 then
            state.showCategorySummary = not state.showCategorySummary
            return
        elseif x >= 16 and x <= 21 then
            cache.slowLastRefresh = 0
            return
        end
    end

    -- tap ailleurs = refresh lent force
    cache.slowLastRefresh = 0
end

-- =========================
-- PALETTE / BUFFERS
-- =========================
applyPalette()

-- =========================
-- BOUCLE
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
        state.lastError = "rs_bridge non detecte"
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

    state.frame = state.frame + 1
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
