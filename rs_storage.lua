-- =========================================================
-- Refined Storage Dashboard
-- Focus stockage + energie utile
-- Anti-flicker / Auto-update
-- =========================================================

-- =========================
-- AUTO UPDATE
-- =========================
local AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/rs_storage.lua"
local AUTO_UPDATE_ENABLED = true
local AUTO_UPDATE_FILE = "startup.lua"
local AUTO_UPDATE_TMP = "startup.lua.tmp"

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
    showGraph = false,
    monitorScale = 0.5,
    refreshInterval = 1,
    historySize = 48,
    title = "Refined Storage Dashboard v3",
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
    inputAvg = 0,
    outputEst = 0,
}

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
-- DATA
-- =========================
local function updateEnergyStats(storedEnergy, avgInput)
    local now = os.epoch("utc") / 1000

    storedEnergy = tonumber(storedEnergy) or 0
    avgInput = tonumber(avgInput) or 0

    if energyStats.lastStored ~= nil and energyStats.lastTime ~= nil then
        local dt = now - energyStats.lastTime
        if dt > 0 then
            local delta = storedEnergy - energyStats.lastStored
            local instantDeltaPerSec = delta / dt

            -- lissage simple
            energyStats.deltaPerSec = (energyStats.deltaPerSec * 0.7) + (instantDeltaPerSec * 0.3)
        end
    end

    energyStats.lastStored = storedEnergy
    energyStats.lastTime = now
    energyStats.inputAvg = avgInput

    -- OUT estime = IN - delta_stock
    energyStats.outputEst = avgInput - energyStats.deltaPerSec
end

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

    local items = safe(function() return bridge.getItems() end, {}) or {}
    local fluids = safe(function() return bridge.getFluids() end, {}) or {}

    local itemTypes = #items
    local fluidTypes = #fluids

    local online = safe(function() return bridge.isOnline() end, nil)
    local connected = safe(function() return bridge.isConnected() end, nil)

    updateEnergyStats(storedEnergy, avgInput)

    return {
        items = {
            used = usedItems,
            total = totalItems,
            types = itemTypes,
        },
        fluids = {
            used = usedFluids,
            total = totalFluids,
            types = fluidTypes,
        },
        energy = {
            stored = storedEnergy,
            total = energyTotal,
            inputAvg = energyStats.inputAvg,
            outputEst = energyStats.outputEst,
            deltaPerSec = energyStats.deltaPerSec,
        },
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

    writeLine(frame, y, string.rep("-", w), colors.gray)
    y = y + 1

    return y
end

local function buildEnergySection(frame, y, energy)
    local w = size()
    local p = percent(energy.stored, energy.total)
    local color = getPercentColor(p)

    writeLine(frame, y, "Energie", colors.cyan)
    y = y + 1

    local left = formatNumber(energy.stored) .. " / " .. formatNumber(energy.total) .. " FE"
    local right = tostring(p) .. "%"
    local middleWidth = math.max(1, w - #right - 1)

    local line1 = trim(left, middleWidth)
    if #line1 < middleWidth then
        line1 = line1 .. string.rep(" ", middleWidth - #line1)
    end
    line1 = line1 .. right
    writeLine(frame, y, line1, color)
    y = y + 1

    writeLine(frame, y, barString(w, energy.stored, energy.total > 0 and energy.total or 1), color)
    y = y + 1

    local inText = "IN: " .. formatNumber(energy.inputAvg) .. "/s"
    local outText = "OUT est: " .. formatNumber(math.max(0, energy.outputEst)) .. "/s"
    local line2 = inText .. " | " .. outText
    writeLine(frame, y, line2, colors.lightBlue)
    y = y + 1

    local deltaPrefix = "Delta: "
    local deltaValue = formatNumber(energy.deltaPerSec) .. "/s"
    if energy.deltaPerSec > 0 then
        deltaValue = "+" .. deltaValue
    end
    writeLine(frame, y, deltaPrefix .. deltaValue, colors.lightGray)
    y = y + 1

    writeLine(frame, y, string.rep("-", w), colors.gray)
    y = y + 1

    return y
end

local function buildFrame(data)
    local w, h = size()
    local frame = newFrame()

    local statusText = "ONLINE"
    if data.network.online == false then
        statusText = "OFFLINE"
    elseif data.network.connected == false then
        statusText = "DISCONNECT"
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
    y = buildEnergySection(frame, y, data.energy)

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
    pushHistory(history.energy, data.energy.stored)

    local frame = buildFrame(data)
    renderFrame(frame)

    sleep(CONFIG.refreshInterval)
end
