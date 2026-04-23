-- =========================================================
-- Refined Storage - Monitoring Patch
-- 1 s / double buffer / anti-scintillement / horloge Paris
-- CC:Tweaked + Advanced Peripherals (RS Bridge)
-- =========================================================

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/rs_storage.lua",
    AUTO_UPDATE_ENABLED = true,

    TITLE = "Refined Storage - Monitoring",
    TEXT_SCALE = 0.5,
    REFRESH_INTERVAL = 1.0,
    SLOW_REFRESH_INTERVAL = 8,
    ETA_SMOOTHING = 0.35,
    USE_CUSTOM_PALETTE = true,
    SHOW_FOOTER = true,

    CLOCK_MIN_WIDTH = 39,
    CLOCK_MIN_HEIGHT = 13,

    ITEMS_WARN_PERCENT = 80,
    ITEMS_DANGER_PERCENT = 95,

    FLUIDS_WARN_PERCENT = 80,
    FLUIDS_DANGER_PERCENT = 95,

    ENERGY_WARN_LOW_PERCENT = 20,
    ENERGY_DANGER_LOW_PERCENT = 5,

    -- Heuristique defensive : au-dela de ce seuil, on masque le pourcentage
    -- car certains bridges remontent une capacite technique "quasi infinie".
    HUGE_ENERGY_CAPACITY = 9000000000000000,
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
    return "startup.lua"
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

local function copyFile(src, dst)
    local content = readFile(src)
    if not content then return false end
    return writeFile(dst, content)
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
    local backupFile = currentFile .. ".bak"

    local remote = fetchUrl(CONFIG.AUTO_UPDATE_URL, tmpFile)
    if not remote then
        print("Auto-update: verification distante impossible.")
        return
    end

    local localContent = readFile(currentFile)
    if localContent == remote then
        print("Auto-update: aucune mise a jour.")
        return
    end

    local ok, err = load(remote, "@remote_update")
    if not ok then
        print("Auto-update: script distant invalide.")
        print(err)
        return
    end

    if fs.exists(tmpFile) then
        fs.delete(tmpFile)
    end

    if not writeFile(tmpFile, remote) then
        print("Auto-update: echec d'ecriture du fichier temporaire.")
        return
    end

    if fs.exists(backupFile) then
        fs.delete(backupFile)
    end

    if fs.exists(currentFile) then
        if fs.copy then
            pcall(function() fs.copy(currentFile, backupFile) end)
        else
            copyFile(currentFile, backupFile)
        end
        fs.delete(currentFile)
    end

    fs.move(tmpFile, currentFile)
    print("Auto-update: mise a jour appliquee, reboot...")
    sleep(1)
    os.reboot()
end

autoUpdate()

-- =========================
-- HELPERS
-- =========================
local function clamp(value, minValue, maxValue)
    value = tonumber(value)
    minValue = tonumber(minValue)
    maxValue = tonumber(maxValue)

    if value == nil then
        return minValue or 0
    end

    if minValue ~= nil and value < minValue then
        return minValue
    end

    if maxValue ~= nil and value > maxValue then
        return maxValue
    end

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

local function firstExisting(tbl, keys, default)
    if type(tbl) ~= "table" then return default end
    for _, key in ipairs(keys) do
        if tbl[key] ~= nil then
            return tbl[key]
        end
    end
    return default
end

local function percent(used, total)
    used = tonumber(used)
    total = tonumber(total)

    if used == nil or total == nil or total <= 0 then
        return nil
    end

    return clamp(math.floor((used / total) * 100 + 0.5), 0, 100)
end

local MAG_SUFFIXES = { "", "k", "M", "G", "T", "P", "E", "Z", "Y" }
local ENERGY_UNITS = { "FE", "kFE", "MFE", "GFE", "TFE", "PFE", "EFE", "ZFE", "YFE" }

local function formatScaledValue(n, suffixes)
    n = tonumber(n) or 0

    local sign = ""
    if n < 0 then
        sign = "-"
        n = math.abs(n)
    end

    local index = 1
    while n >= 1000 and index < #suffixes do
        n = n / 1000
        index = index + 1
    end

    local decimals
    if n >= 100 then
        decimals = 0
    elseif n >= 10 then
        decimals = 1
    else
        decimals = 2
    end

    local value = string.format("%." .. decimals .. "f", n)
    value = value:gsub("%.?0+$", "")

    return sign, value, suffixes[index]
end

local function formatCount(n)
    local sign, value, suffix = formatScaledValue(n, MAG_SUFFIXES)
    return sign .. value .. suffix
end

local function formatFluidAmount(mb)
    mb = tonumber(mb) or 0

    local sign = ""
    if mb < 0 then
        sign = "-"
        mb = math.abs(mb)
    end

    if mb < 1000 then
        return sign .. tostring(math.floor(mb + 0.5)) .. " mB"
    end

    local s, value, suffix = formatScaledValue(mb / 1000, MAG_SUFFIXES)
    return s .. value .. suffix .. " BKT"
end

local function formatEnergy(n)
    local sign, value, unit = formatScaledValue(n, ENERGY_UNITS)
    return sign .. value .. " " .. unit
end

local function formatEnergyRate(n)
    n = tonumber(n) or 0
    if n > 0 then
        return "+" .. formatEnergy(n) .. "/s"
    end
    return formatEnergy(n) .. "/s"
end

local function formatEnergyPerTick(n)
    return formatEnergy(n) .. "/t"
end

local function formatTime(seconds)
    seconds = tonumber(seconds)
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
    if p == nil then
        return colors.lightGray
    elseif p >= 95 then
        return colors.red
    elseif p >= 80 then
        return colors.orange
    elseif p >= 60 then
        return colors.yellow
    else
        return colors.lime
    end
end

local function buildAlert(name, p, warn, danger, inverse, charging)
    if p == nil then
        return { text = name .. " N/A", color = colors.lightGray, severity = 0 }
    end

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

local function classifyEnergyCapacity(total)
    total = tonumber(total) or 0
    if total <= 0 then
        return "unknown"
    elseif total >= CONFIG.HUGE_ENERGY_CAPACITY then
        return "huge"
    else
        return "normal"
    end
end

-- =========================
-- HORLOGE PARIS
-- =========================
local function isLeapYear(year)
    if year % 400 == 0 then return true end
    if year % 100 == 0 then return false end
    return year % 4 == 0
end

local function daysInMonth(year, month)
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and isLeapYear(year) then
        return 29
    end
    return days[month]
end

-- Retourne 0 = dimanche, 1 = lundi, ..., 6 = samedi
local function dayOfWeek(year, month, day)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if month < 3 then
        year = year - 1
    end
    return (year + math.floor(year / 4) - math.floor(year / 100) + math.floor(year / 400) + t[month] + day) % 7
end

local function lastSunday(year, month)
    local dim = daysInMonth(year, month)
    return dim - dayOfWeek(year, month, dim)
end

-- Règle UE/France : heure d'été du dernier dimanche de mars à 01:00 UTC
-- jusqu'au dernier dimanche d'octobre à 01:00 UTC.
local function isParisDSTFromUTC(utcSeconds)
    if type(os.date) ~= "function" then
        return true -- fallback le plus simple si os.date n'existe pas
    end

    local t = os.date("!*t", utcSeconds)
    local year, month, day, hour = t.year, t.month, t.day, t.hour

    if month < 3 or month > 10 then
        return false
    elseif month > 3 and month < 10 then
        return true
    end

    local boundary = lastSunday(year, month)

    if month == 3 then
        if day > boundary then return true end
        if day < boundary then return false end
        return hour >= 1
    else
        if day < boundary then return true end
        if day > boundary then return false end
        return hour < 1
    end
end

local function getParisClockString()
    local utcSeconds = math.floor(os.epoch("utc") / 1000)

    -- Fallback minimal si os.date n'est pas disponible
    if type(os.date) ~= "function" then
        local seconds = utcSeconds + (2 * 3600)
        local daySeconds = seconds % 86400
        local hour = math.floor(daySeconds / 3600)
        local minute = math.floor((daySeconds % 3600) / 60)
        local second = daySeconds % 60
        return string.format("Paris %02d:%02d:%02d", hour, minute, second)
    end

    local offset = isParisDSTFromUTC(utcSeconds) and 2 or 1
    local paris = os.date("!*t", utcSeconds + offset * 3600)
    return string.format("Paris %02d:%02d:%02d", paris.hour, paris.min, paris.sec)
end

-- =========================
-- BUFFER DOUBLE
-- =========================
local BLIT_MAP = {
    [colors.white] = "0",
    [colors.orange] = "1",
    [colors.magenta] = "2",
    [colors.lightBlue] = "3",
    [colors.yellow] = "4",
    [colors.lime] = "5",
    [colors.pink] = "6",
    [colors.gray] = "7",
    [colors.lightGray] = "8",
    [colors.cyan] = "9",
    [colors.purple] = "a",
    [colors.blue] = "b",
    [colors.brown] = "c",
    [colors.green] = "d",
    [colors.red] = "e",
    [colors.black] = "f",
}

local function toBlitColour(colour)
    if colors.toBlit then
        local ok, value = pcall(colors.toBlit, colour)
        if ok and value then
            return value
        end
    end
    return BLIT_MAP[colour] or "f"
end

local function newFrame(w, h, fg, bg)
    local frame = {
        w = w,
        h = h,
        lines = {},
    }

    local defaultFg = string.rep(toBlitColour(fg or colors.white), w)
    local defaultBg = string.rep(toBlitColour(bg or colors.black), w)
    local defaultText = string.rep(" ", w)

    for y = 1, h do
        frame.lines[y] = {
            text = defaultText,
            fg = defaultFg,
            bg = defaultBg,
        }
    end

    return frame
end

local function replaceSlice(source, startPos, replacement)
    if not replacement or replacement == "" then
        return source
    end

    if startPos < 1 then
        replacement = replacement:sub(2 - startPos)
        startPos = 1
    end

    if startPos > #source then
        return source
    end

    local finish = math.min(#source, startPos + #replacement - 1)
    replacement = replacement:sub(1, finish - startPos + 1)

    return source:sub(1, startPos - 1) .. replacement .. source:sub(finish + 1)
end

local function fillRect(frame, x, y, w, h, bg)
    if not frame or w <= 0 or h <= 0 then return end

    local startY = math.max(1, y)
    local endY = math.min(frame.h, y + h - 1)
    local startX = math.max(1, x)
    local endX = math.min(frame.w, x + w - 1)

    if startX > endX or startY > endY then return end

    local len = endX - startX + 1
    local bgText = string.rep(toBlitColour(bg or colors.black), len)
    local spaces = string.rep(" ", len)

    for yy = startY, endY do
        local line = frame.lines[yy]
        line.text = replaceSlice(line.text, startX, spaces)
        line.bg = replaceSlice(line.bg, startX, bgText)
    end
end

local function fillLine(frame, y, bg)
    fillRect(frame, 1, y, frame.w, 1, bg)
end

local function writeAt(frame, x, y, text, fg, bg, maxLen)
    if not frame then return end
    if y < 1 or y > frame.h or x > frame.w then return end

    text = tostring(text or "")
    if maxLen then
        text = trim(text, maxLen)
    end

    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end

    if text == "" then return end

    text = trim(text, frame.w - x + 1)
    if text == "" then return end

    local len = #text
    local line = frame.lines[y]

    line.text = replaceSlice(line.text, x, text)

    if fg then
        line.fg = replaceSlice(line.fg, x, string.rep(toBlitColour(fg), len))
    end

    if bg then
        line.bg = replaceSlice(line.bg, x, string.rep(toBlitColour(bg), len))
    end
end

local function centerText(frame, y, text, fg, bg)
    text = trim(text, frame.w)
    local x = math.max(1, math.floor((frame.w - #text) / 2) + 1)
    writeAt(frame, x, y, text, fg, bg)
end

local function drawButton(frame, x, y, label, isActive)
    local bg = isActive and colors.blue or colors.gray
    local fg = colors.white
    local text = " " .. label .. " "
    writeAt(frame, x, y, text, fg, bg)
    return #text
end

local function drawProgressBar(frame, x, y, w, ratio, fillColor, emptyColor, label)
    if w <= 0 or y < 1 or y > frame.h then return end

    local line = frame.lines[y]
    local startX = math.max(1, x)
    local endX = math.min(frame.w, x + w - 1)
    local len = endX - startX + 1

    if len <= 0 then return end

    fillRect(frame, startX, y, len, 1, emptyColor or colors.gray)

    if ratio ~= nil then
        ratio = tonumber(ratio)
        if ratio ~= nil then
            ratio = clamp(ratio, 0, 1)
        end
    end

    local filled = 0
    if ratio ~= nil then
        filled = clamp(math.floor((len * ratio) + 0.5), 0, len)
    end

    if filled > 0 then
        line.bg = replaceSlice(line.bg, startX, string.rep(toBlitColour(fillColor or colors.gray), filled))
    end

    if label and label ~= "" then
        local tx = startX + math.max(0, math.floor((len - #label) / 2))
        writeAt(frame, tx, y, label, colors.white, nil, len)
    end
end

-- Affiche uniquement les segments modifies : pas de clear general a chaque tick.
local frontBuffer = nil
local bufferW, bufferH = 0, 0

local function flushFrame(mon, frame)
    if not mon or not frame then return end

    for y = 1, frame.h do
        local newLine = frame.lines[y]
        local oldLine = frontBuffer and frontBuffer.lines[y] or nil

        local same = oldLine
            and oldLine.text == newLine.text
            and oldLine.fg == newLine.fg
            and oldLine.bg == newLine.bg

        if not same then
            local segmentStart = nil

            for x = 1, frame.w do
                local changed = (not oldLine)
                    or oldLine.text:sub(x, x) ~= newLine.text:sub(x, x)
                    or oldLine.fg:sub(x, x) ~= newLine.fg:sub(x, x)
                    or oldLine.bg:sub(x, x) ~= newLine.bg:sub(x, x)

                if changed and not segmentStart then
                    segmentStart = x
                end

                local endSegment = false
                local segmentEnd = nil

                if segmentStart then
                    if x == frame.w and changed then
                        endSegment = true
                        segmentEnd = x
                    elseif not changed then
                        endSegment = true
                        segmentEnd = x - 1
                    end
                end

                if endSegment and segmentStart and segmentEnd and segmentEnd >= segmentStart then
                    mon.setCursorPos(segmentStart, y)
                    mon.blit(
                        newLine.text:sub(segmentStart, segmentEnd),
                        newLine.fg:sub(segmentStart, segmentEnd),
                        newLine.bg:sub(segmentStart, segmentEnd)
                    )
                    segmentStart = nil
                end
            end

            frontBuffer.lines[y] = {
                text = newLine.text,
                fg = newLine.fg,
                bg = newLine.bg,
            }
        end
    end
end

-- =========================
-- PERIPHERIQUES
-- =========================
local bridge = peripheral.find("rs_bridge") or peripheral.find("rsBridge")
local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

local monitorName = peripheral.getName(mon)

local function applyPalette()
    if not CONFIG.USE_CUSTOM_PALETTE or not mon then
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

local function prepareMonitor()
    if not mon then return end
    mon.setTextScale(CONFIG.TEXT_SCALE)
    mon.setCursorBlink(false)
    applyPalette()
end

local function reacquirePeripherals()
    bridge = peripheral.find("rs_bridge") or peripheral.find("rsBridge")
    mon = peripheral.find("monitor")
    if mon then
        monitorName = peripheral.getName(mon)
    else
        monitorName = nil
    end
end

local function getBackBuffer()
    local w, h = mon.getSize()

    if not frontBuffer or w ~= bufferW or h ~= bufferH then
        bufferW, bufferH = w, h
        frontBuffer = newFrame(w, h, colors.white, colors.black)
        mon.setBackgroundColor(colors.black)
        mon.clear()
    end

    return newFrame(w, h, colors.white, colors.black), w, h
end

-- =========================
-- ETAT
-- =========================
local cache = {
    slowLastRefresh = 0,
    itemTypes = 0,
    fluidTypes = 0,
    cellCount = 0,
    itemsList = {},
    fluidsList = {},
}

local energyStats = {
    lastStored = nil,
    lastTime = nil,
    deltaPerSec = 0,
    avgInput = 0,
}

local uiState = {
    refX = 2,
    refW = 0,
    refUntil = 0,
}

-- =========================
-- BRIDGE HELPERS
-- =========================
local function callBridge(methodName, ...)
    if not bridge or type(bridge[methodName]) ~= "function" then
        return nil
    end

    local args = { ... }
    return safe(function()
        return bridge[methodName](table.unpack(args))
    end, nil)
end

local function listBridgeResources(primaryMethod, legacyMethod)
    local result = callBridge(primaryMethod, {})
    if type(result) == "table" then
        return result
    end

    result = callBridge(primaryMethod)
    if type(result) == "table" then
        return result
    end

    if legacyMethod then
        result = callBridge(legacyMethod)
        if type(result) == "table" then
            return result
        end
    end

    return {}
end

local function getStackAmount(stack)
    return toNumber(firstExisting(stack, { "amount", "count", "stored" }, 0), 0)
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
            energyStats.deltaPerSec =
                (energyStats.deltaPerSec * (1 - CONFIG.ETA_SMOOTHING))
                + (instantDeltaPerSec * CONFIG.ETA_SMOOTHING)
        end
    end

    energyStats.lastStored = storedEnergy
    energyStats.lastTime = now
    energyStats.avgInput = avgInput
end

local function refreshSlowData(force)
    local now = nowSec()
    if not force and (now - cache.slowLastRefresh) < CONFIG.SLOW_REFRESH_INTERVAL then
        return
    end

    if not bridge then
        cache.itemTypes = 0
        cache.fluidTypes = 0
        cache.cellCount = 0
        cache.itemsList = {}
        cache.fluidsList = {}
        cache.slowLastRefresh = now
        return
    end

    cache.itemsList = listBridgeResources("getItems", "listItems")
    cache.fluidsList = listBridgeResources("getFluids", "listFluids")

    local cells = callBridge("getCells") or {}
    if type(cells) ~= "table" then
        cells = {}
    end

    cache.itemTypes = #cache.itemsList
    cache.fluidTypes = #cache.fluidsList
    cache.cellCount = #cells
    cache.slowLastRefresh = now
end

local function buildData()
    refreshSlowData(false)

    if not bridge then
        return {
            bridgePresent = false,
            items = { used = 0, total = 0, types = 0, percent = nil, alert = buildAlert("ITM", nil, 0, 0, false, false) },
            fluids = { used = 0, total = 0, types = 0, percent = nil, alert = buildAlert("FLD", nil, 0, 0, false, false) },
            energy = {
                stored = 0, total = 0, percent = nil, usage = 0, avgInput = 0,
                deltaPerSec = 0, trend = "Stable", eta = "--",
                alert = buildAlert("NRG", nil, 0, 0, true, false),
                capacityClass = "unknown",
            },
            cells = { count = 0 },
            network = { online = false, connected = false },
        }
    end

    local usedItems = toNumber(callBridge("getUsedItemStorage"), -1)
    local totalItems = toNumber(callBridge("getTotalItemStorage"), 0)

    local usedFluids = toNumber(callBridge("getUsedFluidStorage"), -1)
    local totalFluids = toNumber(callBridge("getTotalFluidStorage"), 0)

    if usedItems < 0 then
        usedItems = 0
        for _, item in ipairs(cache.itemsList) do
            usedItems = usedItems + getStackAmount(item)
        end
    end

    if usedFluids < 0 then
        usedFluids = 0
        for _, fluid in ipairs(cache.fluidsList) do
            usedFluids = usedFluids + getStackAmount(fluid)
        end
    end

    local storedEnergy = callBridge("getStoredEnergy")
    if storedEnergy == nil then
        storedEnergy = callBridge("getEnergyStorage")
    end
    storedEnergy = toNumber(storedEnergy, 0)

    local energyTotal = callBridge("getEnergyCapacity")
    if energyTotal == nil then
        energyTotal = callBridge("getMaxEnergyStorage")
    end
    energyTotal = toNumber(energyTotal, 0)

    local energyUsage = toNumber(callBridge("getEnergyUsage"), 0)

    local avgInput = callBridge("getAverageEnergyInput")
    if avgInput == nil then
        avgInput = callBridge("getAvgPowerInjection")
    end
    avgInput = toNumber(avgInput, 0)

    local online = callBridge("isOnline")
    local connected = callBridge("isConnected")

    updateEnergyStats(storedEnergy, avgInput)

    local itemsPercent = percent(usedItems, totalItems)
    local fluidsPercent = percent(usedFluids, totalFluids)

    local energyCapacityClass = classifyEnergyCapacity(energyTotal)
    local energyPercent = energyCapacityClass == "normal" and percent(storedEnergy, energyTotal) or nil

    local charging = energyStats.deltaPerSec > 1

    local itemAlert = buildAlert("ITM", itemsPercent, CONFIG.ITEMS_WARN_PERCENT, CONFIG.ITEMS_DANGER_PERCENT, false, false)
    local fluidAlert = buildAlert("FLD", fluidsPercent, CONFIG.FLUIDS_WARN_PERCENT, CONFIG.FLUIDS_DANGER_PERCENT, false, false)
    local energyAlert = buildAlert("NRG", energyPercent, CONFIG.ENERGY_WARN_LOW_PERCENT, CONFIG.ENERGY_DANGER_LOW_PERCENT, true, charging)

    local trend = "Stable"
    local eta = "--"

    if energyStats.deltaPerSec > 1 then
        trend = "Charge"
        if energyCapacityClass == "normal" then
            local remaining = energyTotal - storedEnergy
            if remaining > 0 then
                eta = formatTime(remaining / energyStats.deltaPerSec)
            end
        end
    elseif energyStats.deltaPerSec < -1 then
        trend = "Decharge"
        if storedEnergy > 0 then
            eta = formatTime(storedEnergy / math.abs(energyStats.deltaPerSec))
        end
    end

    return {
        bridgePresent = true,
        items = {
            used = usedItems,
            total = totalItems,
            types = cache.itemTypes,
            percent = itemsPercent,
            alert = itemAlert,
        },
        fluids = {
            used = usedFluids,
            total = totalFluids,
            types = cache.fluidTypes,
            percent = fluidsPercent,
            alert = fluidAlert,
        },
        energy = {
            stored = storedEnergy,
            total = energyTotal,
            usage = energyUsage,
            avgInput = avgInput,
            percent = energyPercent,
            deltaPerSec = energyStats.deltaPerSec,
            trend = trend,
            eta = eta,
            alert = energyAlert,
            capacityClass = energyCapacityClass,
        },
        cells = {
            count = cache.cellCount,
        },
        network = {
            online = online,
            connected = connected,
        },
    }
end

-- =========================
-- DESSIN
-- =========================
local function drawHeader(frame, data, w)
    fillLine(frame, 1, colors.gray)
    fillLine(frame, 2, colors.black)
    fillLine(frame, 3, colors.black)

    local status = "ONLINE"
    if not data.bridgePresent then
        status = "NO BRIDGE"
    elseif data.network.online == false then
        status = "OFFLINE"
    elseif data.network.connected == false then
        status = "DISCONNECT"
    end

    writeAt(frame, 2, 1, trim(CONFIG.TITLE, math.max(1, w - #status - 4)), colors.white, colors.gray)
    writeAt(frame, math.max(2, w - #status - 1), 1, status, colors.cyan, colors.gray)

    local meta = "Types I " .. tostring(data.items.types)
        .. " | Types F " .. tostring(data.fluids.types)
        .. " | Disques " .. tostring(data.cells.count)
    centerText(frame, 2, trim(meta, w - 4), colors.lightGray, colors.black)

    local summary
    if not data.bridgePresent then
        summary = "Bridge RS non detecte"
    else
        summary = data.items.alert.text .. " | " .. data.fluids.alert.text .. " | " .. data.energy.alert.text
    end
    writeAt(frame, 2, 3, trim(summary, w - 2), colors.lightBlue, colors.black)
end

local function drawMetricSection(frame, y, w, title, rightText, rightColor, valueText, ratio, barLabel)
    if y + 2 > frame.h then
        return
    end

    fillLine(frame, y, colors.gray)
    fillLine(frame, y + 1, colors.black)
    fillLine(frame, y + 2, colors.black)

    writeAt(frame, 2, y, title, colors.white, colors.gray, math.max(1, w - #rightText - 4))
    writeAt(frame, math.max(2, w - #rightText - 1), y, rightText, rightColor, colors.gray)

    writeAt(frame, 2, y + 1, trim(valueText, w - 2), colors.white, colors.black)

    local label = barLabel or ""
    drawProgressBar(
        frame,
        2,
        y + 2,
        w - 2,
        ratio,
        getPercentColor(ratio and math.floor(ratio * 100 + 0.5) or nil),
        colors.gray,
        label
    )
end

local function drawFooter(frame, w, h)
    if not CONFIG.SHOW_FOOTER then
        return
    end

    fillLine(frame, h, colors.black)

    local left = 2
    local active = nowSec() < uiState.refUntil
    local refW = drawButton(frame, left, h, "REF", active)

    uiState.refX = left
    uiState.refW = refW

    local footerText
    if w >= CONFIG.CLOCK_MIN_WIDTH and h >= CONFIG.CLOCK_MIN_HEIGHT then
        footerText = getParisClockString()
    else
        footerText = "Monitoring"
    end

    writeAt(
        frame,
        math.max(left + refW + 2, w - #footerText + 1),
        h,
        footerText,
        colors.cyan,
        colors.black
    )
end

local function drawBridgeMissing(frame, w, h)
    local footerH = CONFIG.SHOW_FOOTER and 1 or 0
    local targetMax = math.max(4, h - footerH)
    local messageY = math.max(4, math.min(targetMax, math.floor((h - footerH) / 2)))

    centerText(frame, messageY, "rs_bridge / rsBridge non detecte", colors.red, colors.black)

    if messageY + 1 <= h - footerH then
        centerText(frame, messageY + 1, "Verifier le bridge, le cable et le modem", colors.lightGray, colors.black)
    end
end

local function drawScreen(data)
    if not mon then
        return
    end

    local frame, w, h = getBackBuffer()
    drawHeader(frame, data, w)

    if data.bridgePresent then
        local footerH = CONFIG.SHOW_FOOTER and 1 or 0
        local extra = h - (3 + footerH + 9)
        local topGap = extra >= 1 and 1 or 0
        local sectionGap = (extra - topGap) >= 2 and 1 or 0

        local yItems = 4 + topGap
        local yFluids = yItems + 3 + sectionGap
        local yEnergy = yFluids + 3 + sectionGap
        local infoY = yEnergy + 3 + sectionGap
        local maxBodyY = h - footerH

        local itemsRight = ((data.items.percent ~= nil and tostring(data.items.percent) or "--") .. "% " .. data.items.alert.text)
        local itemsValue = formatCount(data.items.used) .. " / " .. formatCount(data.items.total)
            .. " | Types: " .. tostring(data.items.types)

        drawMetricSection(
            frame,
            yItems,
            w,
            "Items",
            itemsRight,
            data.items.alert.color,
            itemsValue,
            data.items.percent and (data.items.percent / 100) or nil,
            nil
        )

        local fluidsRight = ((data.fluids.percent ~= nil and tostring(data.fluids.percent) or "--") .. "% " .. data.fluids.alert.text)
        local fluidsValue = formatFluidAmount(data.fluids.used) .. " / " .. formatFluidAmount(data.fluids.total)
            .. " | Types: " .. tostring(data.fluids.types)

        drawMetricSection(
            frame,
            yFluids,
            w,
            "Fluides",
            fluidsRight,
            data.fluids.alert.color,
            fluidsValue,
            data.fluids.percent and (data.fluids.percent / 100) or nil,
            nil
        )

        local energyRight
        local energyRatio = nil
        local energyBarLabel = nil
        local energyRightColor = colors.lightGray
        local energyTotalText = "N/A"

        if data.energy.capacityClass == "normal" then
            energyRight = tostring(data.energy.percent) .. "% " .. data.energy.alert.text
            energyRightColor = data.energy.alert.color
            energyRatio = data.energy.percent / 100
            energyTotalText = formatEnergy(data.energy.total)
        elseif data.energy.capacityClass == "huge" then
            energyRight = "MAX API"
            energyBarLabel = "Cap. API"
            energyTotalText = "MAX"
        else
            energyRight = "N/A"
            energyBarLabel = "Cap. ?"
        end

        local energyValue = formatEnergy(data.energy.stored) .. " / " .. energyTotalText
        if data.energy.usage and data.energy.usage > 0 then
            energyValue = energyValue .. " | Usage: " .. formatEnergyPerTick(data.energy.usage)
        end

        drawMetricSection(
            frame,
            yEnergy,
            w,
            "Energie",
            energyRight,
            energyRightColor,
            energyValue,
            energyRatio,
            energyBarLabel
        )

        if infoY <= maxBodyY then
            local line1 = "Net: " .. formatEnergyRate(data.energy.deltaPerSec)
                .. " | " .. data.energy.trend
                .. " | ETA: " .. data.energy.eta
            writeAt(frame, 2, infoY, trim(line1, w - 2), colors.lightBlue, colors.black)
        end

        if infoY + 1 <= maxBodyY then
            local line2 = "Usage: " .. formatEnergyPerTick(data.energy.usage)
            if data.energy.avgInput and data.energy.avgInput > 0 then
                line2 = line2 .. " | Entree: " .. formatEnergyPerTick(data.energy.avgInput)
            end
            line2 = line2 .. " | Disques: " .. tostring(data.cells.count)
            writeAt(frame, 2, infoY + 1, trim(line2, w - 2), colors.lightGray, colors.black)
        end
    else
        drawBridgeMissing(frame, w, h)
    end

    drawFooter(frame, w, h)
    flushFrame(mon, frame)
end

-- =========================
-- INTERACTION
-- =========================
local function handleTouch(x, y)
    if not mon then return end

    local _, h = mon.getSize()
    if CONFIG.SHOW_FOOTER and y == h then
        local startX = uiState.refX
        local endX = uiState.refX + uiState.refW - 1

        if x >= startX and x <= endX then
            cache.slowLastRefresh = 0
            uiState.refUntil = nowSec() + 0.5
        end
    end
end

-- =========================
-- RENDU
-- =========================
local function render()
    if not mon then
        return
    end

    local data = buildData()
    drawScreen(data)
end

prepareMonitor()
render()

local timer = os.startTimer(CONFIG.REFRESH_INTERVAL)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" and p1 == timer then
        render()
        timer = os.startTimer(CONFIG.REFRESH_INTERVAL)

    elseif event == "monitor_touch" and monitorName and p1 == monitorName then
        handleTouch(p2, p3)
        render()

    elseif event == "monitor_resize" and monitorName and p1 == monitorName then
        prepareMonitor()
        frontBuffer = nil
        render()

    elseif event == "peripheral" or event == "peripheral_detach" then
        local oldMonitorName = monitorName
        reacquirePeripherals()

        if mon then
            if oldMonitorName ~= monitorName then
                prepareMonitor()
                frontBuffer = nil
            end
            render()
        end
    end
end
