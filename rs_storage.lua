-- =========================================================
-- Refined Storage Dashboard
-- Anti-flicker version
-- =========================================================

-- =========================
-- AUTO UPDATE
-- =========================

local AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/rs_storage.lua"
local AUTO_UPDATE_ENABLED = true
local AUTO_UPDATE_FILE = "rs_storage.lua"
local AUTO_UPDATE_TMP = "rs_storage.lua.tmp"

local function autoUpdate()
    if not AUTO_UPDATE_ENABLED then
        return
    end

    if not http then
        print("HTTP indisponible, auto-update ignore.")
        return
    end

    print("Verification mise a jour...")

    if fs.exists(AUTO_UPDATE_TMP) then
        fs.delete(AUTO_UPDATE_TMP)
    end

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
        fs.delete(AUTO_UPDATE_TMP)
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
    print("Mise a jour appliquee, relance...")
    sleep(1)
    shell.run(AUTO_UPDATE_FILE)
    os.shutdown()
end

autoUpdate()

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    showGraph = false,
    monitorScale = 0.5,
    refreshInterval = 1,
    historySize = 48,
    title = "Refined Storage Dashboard v1",
}

-- =========================
-- PERIPHERALS
-- =========================
local bridge = peripheral.find("rs_bridge")
if not bridge then
    error("rs_bridge non detecte")
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

-- =========================
-- UTILS
-- =========================
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
            bg = colors.black
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
        bg = bg or colors.black
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
-- DATA
-- =========================
local function getData()
    local usedItems = tonumber(safe(function() return bridge.getUsedItemStorage() end, 0)) or 0
    local totalItems = tonumber(safe(function() return bridge.getTotalItemStorage() end, 0)) or 0

    local usedFluids = tonumber(safe(function() return bridge.getUsedFluidStorage() end, 0)) or 0
    local totalFluids = tonumber(safe(function() return bridge.getTotalFluidStorage() end, 0)) or 0

    local energyUsed = tonumber(safe(function() return bridge.getEnergyUsage() end, 0)) or 0
    local energyTotal = tonumber(safe(function() return bridge.getEnergyCapacity() end, 0)) or 0

    local items = safe(function() return bridge.getItems() end, {}) or {}
    local fluids = safe(function() return bridge.getFluids() end, {}) or {}

    local itemTypes = #items
    local fluidTypes = #fluids

    local online = safe(function() return bridge.isOnline() end, nil)
    local connected = safe(function() return bridge.isConnected() end, nil)

    return {
        items = { used = usedItems, total = totalItems, types = itemTypes },
        fluids = { used = usedFluids, total = totalFluids, types = fluidTypes },
        energy = { used = energyUsed, total = energyTotal },
        network = {
            online = online,
            connected = connected,
        }
    }
end

-- =========================
-- BUILD FRAME
-- =========================
local function buildMetric(frame, y, title, used, total, unit, graphData)
    local w = size()
    local p = percent(used, total)
    local color = getPercentColor(p)

    writeLine(frame, y, title, colors.cyan)
    y = y + 1

    local left = formatNumber(used) .. " / " .. formatNumber(total)
    if unit and unit ~= "" then
        left = left .. " " .. unit
    end

    local right = tostring(p) .. "%"
    local middleWidth = math.max(1, w - #right - 1)
    local line1 = trim(left, middleWidth)
    if #line1 < middleWidth then
        line1 = line1 .. string.rep(" ", middleWidth - #line1)
    end
    line1 = line1 .. right
    writeLine(frame, y, line1, color)
    y = y + 1

    local bar = barString(w, used, total > 0 and total or 1)
    writeLine(frame, y, bar, color)
    y = y + 1

if CONFIG.showGraph then
    writeLine(frame, y, "Historique:", colors.lightGray)
    y = y + 1

    local graph = graphString(w, graphData)
    writeLine(frame, y, graph, colors.lightBlue)
    y = y + 1
end

local function buildFrame(data)
    local w, h = size()
    local frame = newFrame()

    local statusText = "ONLINE"
    local statusColor = colors.lime

    if data.network.online == false then
        statusText = "OFFLINE"
        statusColor = colors.red
    elseif data.network.connected == false then
        statusText = "DISCONNECT"
        statusColor = colors.orange
    end

    local title = trim(CONFIG.title, math.max(1, w - #statusText - 1))
    local top = title
    if #top < (w - #statusText) then
        top = top .. string.rep(" ", (w - #statusText) - #top)
    end
    top = trim(top .. statusText, w)

    writeLine(frame, 1, top, colors.cyan)
    writeLine(frame, 2, string.rep("-", w), colors.gray)

    local y = 3
    y = buildMetric(frame, y, "Items", data.items.used, data.items.total, "", history.items)
    y = buildMetric(frame, y, "Fluides", data.fluids.used, data.fluids.total, "mB", history.fluids)
    y = buildMetric(frame, y, "Energie", data.energy.used, data.energy.total, "FE", history.energy)

    if y <= h then
        local footer = "Types items: " .. tostring(data.items.types)
            .. " | Types fluides: " .. tostring(data.fluids.types)
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
    pushHistory(history.energy, data.energy.used)

    local frame = buildFrame(data)
    renderFrame(frame)

    sleep(CONFIG.refreshInterval)
end
