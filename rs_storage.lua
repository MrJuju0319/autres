-- =========================================================
-- Refined Storage Dashboard
-- Stoneblock 4 / CC:Tweaked / rs_bridge / monitor
-- Auto-update + graphs + infos avancees
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
        print("Aucune mise a jour.")
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
    monitorScale = 0.5,
    refreshInterval = 1,
    historySize = 48,
    title = "Refined Storage Dashboard",
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

-- =========================
-- UTILS
-- =========================
local function safe(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
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

local function writeAt(x, y, text, fg, bg)
    local w, h = size()
    if y < 1 or y > h then return end
    if x < 1 then x = 1 end

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fg or colors.white)
    mon.write(trim(text, w - x + 1))
    mon.setBackgroundColor(colors.black)
end

local function centerText(y, text, fg)
    local w = size()
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    writeAt(x, y, text, fg)
end

local function line(y, fg)
    local w = size()
    writeAt(1, y, string.rep("-", w), fg or colors.gray)
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

local function drawBar(x, y, width, used, total, fillColor, emptyColor)
    width = math.max(1, width)
    used = tonumber(used) or 0
    total = tonumber(total) or 0

    local filled = 0
    if total > 0 then
        filled = math.floor((used / total) * width + 0.5)
        if filled < 0 then filled = 0 end
        if filled > width then filled = width end
    end

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(emptyColor or colors.gray)
    mon.write(string.rep(" ", width))

    if filled > 0 then
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(fillColor or colors.green)
        mon.write(string.rep(" ", filled))
    end

    mon.setBackgroundColor(colors.black)
end

local function drawMiniGraph(x, y, width, values, color)
    width = math.max(1, width)
    local count = #values
    if count == 0 then
        writeAt(x, y, string.rep(".", width), colors.gray)
        return
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
            chars[#chars + 1] = "\127"
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

    writeAt(x, y, table.concat(chars), color or colors.lightBlue)
end

local function drawMetricBlock(y, title, used, total, unit, graphData)
    local w = size()
    local p = percent(used, total)
    local color = getPercentColor(p)

    writeAt(1, y, title, colors.cyan)
    y = y + 1

    local left = formatNumber(used) .. " / " .. formatNumber(total)
    if unit and unit ~= "" then
        left = left .. " " .. unit
    end

    local right = tostring(p) .. "%"
    writeAt(2, y, left, colors.white)
    writeAt(math.max(2, w - #right + 1), y, right, color)
    y = y + 1

    drawBar(2, y, math.max(10, w - 2), used, total > 0 and total or 1, color, colors.gray)
    y = y + 1

    writeAt(2, y, "Historique", colors.lightGray)
    drawMiniGraph(14, y, math.max(8, w - 13), graphData, colors.lightBlue)
    y = y + 1

    line(y)
    y = y + 1

    return y
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
-- RENDER
-- =========================
local function drawHeader(data)
    local w = size()
    writeAt(1, 1, CONFIG.title, colors.cyan)

    local onlineText = "ONLINE"
    local onlineColor = colors.lime

    if data.network.online == false then
        onlineText = "OFFLINE"
        onlineColor = colors.red
    elseif data.network.connected == false then
        onlineText = "DISCONNECT"
        onlineColor = colors.orange
    end

    writeAt(math.max(1, w - #onlineText + 1), 1, onlineText, onlineColor)
    line(2)
end

local function drawFooter(y, data)
    local w, h = size()
    if y > h then return end

    local txt = "Types items: " .. tostring(data.items.types)
        .. " | Types fluides: " .. tostring(data.fluids.types)

    writeAt(1, math.min(h, y), trim(txt, w), colors.lightGray)
end

local function render()
    clear()

    local data = getData()

    pushHistory(history.items, data.items.used)
    pushHistory(history.fluids, data.fluids.used)
    pushHistory(history.energy, data.energy.used)

    drawHeader(data)

    local y = 3
    y = drawMetricBlock(y, "Items", data.items.used, data.items.total, "", history.items)
    y = drawMetricBlock(y, "Fluides", data.fluids.used, data.fluids.total, "mB", history.fluids)
    y = drawMetricBlock(y, "Energie", data.energy.used, data.energy.total, "FE", history.energy)

    drawFooter(y, data)
end

-- =========================
-- LOOP
-- =========================
while true do
    render()
    sleep(CONFIG.refreshInterval)
end
