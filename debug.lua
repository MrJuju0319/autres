-- =========================================================
-- RS Bridge Full Monitor
-- CC:Tweaked + rsBridge
-- Affiche un maximum d'informations disponibles du bridge
-- sur un moniteur avec pagination automatique.
-- =========================================================

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/debug.lua",
    AUTO_UPDATE_ENABLED = true,
    AUTO_UPDATE_FILE = "startup.lua",
    AUTO_UPDATE_TMP = "startup.lua.tmp",
    MONITOR_NAME = nil,        -- nil = auto-detect
    BRIDGE_NAME = nil,         -- nil = auto-detect
    TEXT_SCALE = 0.5,
    REFRESH_INTERVAL = 2,
    PAGE_ROTATE_EVERY = 6,     -- secondes
    TITLE = "Refined Storage - Bridge Infos",
    FOOTER = "CC:Tweaked + rsBridge",
    USE_COLOR = true
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
-- COLORS
-- =========================
local C = {
    bg = colors.black,
    titleBg = colors.blue,
    titleText = colors.white,
    section = colors.cyan,
    label = colors.lightGray,
    value = colors.white,
    ok = colors.lime,
    warn = colors.yellow,
    err = colors.red,
    dim = colors.gray,
    footer = colors.lightBlue
}

-- =========================
-- HELPERS
-- =========================
local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return true, result
    end
    return false, tostring(result)
end

local function toStr(v)
    if v == nil then return "nil" end
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" then
        if math.floor(v) == v then
            return tostring(v)
        end
        return string.format("%.2f", v)
    end
    return tostring(v)
end

local function formatNumber(n)
    if type(n) ~= "number" then return toStr(n) end

    local negative = n < 0
    n = math.abs(n)

    local s
    if n >= 1000000000 then
        s = string.format("%.2fG", n / 1000000000)
    elseif n >= 1000000 then
        s = string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then
        s = string.format("%.2fk", n / 1000)
    else
        s = tostring(math.floor(n * 100) / 100)
    end

    if negative then s = "-" .. s end
    return s
end

local function centerText(termObj, y, text, textColor, bgColor)
    local w, _ = termObj.getSize()
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    if bgColor then termObj.setBackgroundColor(bgColor) end
    if textColor then termObj.setTextColor(textColor) end
    termObj.setCursorPos(x, y)
    termObj.write(text)
end

local function writeAt(termObj, x, y, text, textColor, bgColor)
    if bgColor then termObj.setBackgroundColor(bgColor) end
    if textColor then termObj.setTextColor(textColor) end
    termObj.setCursorPos(x, y)
    termObj.write(text)
end

local function fillLine(termObj, y, bgColor)
    local w, _ = termObj.getSize()
    termObj.setCursorPos(1, y)
    termObj.setBackgroundColor(bgColor or C.bg)
    termObj.write(string.rep(" ", w))
end

local function trim(str, maxLen)
    str = tostring(str or "")
    if #str <= maxLen then return str end
    if maxLen <= 3 then return string.sub(str, 1, maxLen) end
    return string.sub(str, 1, maxLen - 3) .. "..."
end

local function tableCount(t)
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

local function firstAvailableMethod(obj, names)
    for _, name in ipairs(names) do
        if type(obj[name]) == "function" then
            return name
        end
    end
    return nil
end

-- =========================
-- PERIPHERAL DISCOVERY
-- =========================
local function findPeripheralByType(types)
    local names = peripheral.getNames()
    for _, name in ipairs(names) do
        local pType = peripheral.getType(name)
        for _, wanted in ipairs(types) do
            if pType == wanted then
                return name, peripheral.wrap(name), pType
            end
        end
    end
    return nil, nil, nil
end

local function initMonitor()
    local monName, mon

    if CONFIG.MONITOR_NAME then
        if peripheral.isPresent(CONFIG.MONITOR_NAME) then
            mon = peripheral.wrap(CONFIG.MONITOR_NAME)
            monName = CONFIG.MONITOR_NAME
        end
    else
        monName, mon = findPeripheralByType({ "monitor" })
    end

    if not mon then
        error("Aucun moniteur detecte.")
    end

    mon.setTextScale(CONFIG.TEXT_SCALE)
    mon.setBackgroundColor(C.bg)
    mon.clear()

    return monName, mon
end

local function initBridge()
    local bridgeName, bridge, bridgeType

    if CONFIG.BRIDGE_NAME then
        if peripheral.isPresent(CONFIG.BRIDGE_NAME) then
            bridge = peripheral.wrap(CONFIG.BRIDGE_NAME)
            bridgeName = CONFIG.BRIDGE_NAME
            bridgeType = peripheral.getType(CONFIG.BRIDGE_NAME)
        end
    else
        -- Plusieurs noms possibles selon versions/mods
        bridgeName, bridge, bridgeType = findPeripheralByType({
            "rsBridge",
            "meBridge",
            "refinedstorage:bridge",
            "ae2:bridge"
        })
    end

    if not bridge then
        error("Aucun bridge rsBridge detecte.")
    end

    return bridgeName, bridge, bridgeType
end

-- =========================
-- DATA COLLECTION
-- =========================
local function collectMethodList(bridge)
    local methods = {}

    local ok, result = safeCall(peripheral.getMethods, peripheral.getName(bridge))
    if ok and type(result) == "table" then
        for _, m in ipairs(result) do
            table.insert(methods, m)
        end
        table.sort(methods)
        return methods
    end

    -- fallback si jamais peripheral.getMethods ne marche pas
    for k, v in pairs(bridge) do
        if type(v) == "function" then
            table.insert(methods, k)
        end
    end
    table.sort(methods)
    return methods
end

local function tryNamedCall(bridge, names, ...)
    local method = firstAvailableMethod(bridge, names)
    if not method then
        return false, "method_missing", nil
    end
    local ok, result = safeCall(bridge[method], ...)
    if ok then
        return true, method, result
    end
    return false, method, result
end

local function summarizeTable(t)
    if type(t) ~= "table" then return toStr(t) end
    local parts = {}
    local count = 0
    for k, v in pairs(t) do
        count = count + 1
        if count <= 4 then
            table.insert(parts, tostring(k) .. "=" .. toStr(v))
        end
    end
    local s = table.concat(parts, ", ")
    if count > 4 then
        s = s .. ", ..."
    end
    if s == "" then s = "(table vide)" end
    return s
end

local function collectData(bridge)
    local data = {
        timestamp = os.date("%H:%M:%S"),
        general = {},
        items = {},
        fluids = {},
        crafting = {},
        energy = {},
        methods = {},
        rawSamples = {}
    }

    -- Liste des méthodes dispo
    data.methods = collectMethodList(bridge)

    -- =========================
    -- GENERAL
    -- =========================
    local ok1, method1, result1 = tryNamedCall(bridge, {
        "getNetworkName", "getName"
    })
    data.general.networkName = ok1 and result1 or ("N/A (" .. tostring(method1) .. ")")

    local ok2, method2, result2 = tryNamedCall(bridge, {
        "isConnected", "hasNetwork"
    })
    data.general.connected = ok2 and result2 or ("N/A (" .. tostring(method2) .. ")")

    -- =========================
    -- ENERGY
    -- =========================
    local ok3, method3, result3 = tryNamedCall(bridge, {
        "getEnergyStorage", "getEnergy", "getStoredEnergy"
    })
    data.energy.stored = ok3 and result3 or nil
    data.energy.storedMethod = method3

    local ok4, method4, result4 = tryNamedCall(bridge, {
        "getMaxEnergyStorage", "getMaxEnergy", "getEnergyCapacity"
    })
    data.energy.max = ok4 and result4 or nil
    data.energy.maxMethod = method4

    local ok5, method5, result5 = tryNamedCall(bridge, {
        "getEnergyUsage", "getUsage"
    })
    data.energy.usage = ok5 and result5 or nil
    data.energy.usageMethod = method5

    -- =========================
    -- ITEMS
    -- =========================
    local ok6, method6, result6 = tryNamedCall(bridge, {
        "listItems", "getItems", "getAvailableItems"
    })
    data.items.method = method6
    if ok6 and type(result6) == "table" then
        data.items.list = result6
        data.items.count = #result6

        local totalAmount = 0
        for _, item in ipairs(result6) do
            totalAmount = totalAmount + (tonumber(item.amount) or tonumber(item.qty) or 0)
        end
        data.items.totalAmount = totalAmount

        for i = 1, math.min(5, #result6) do
            local item = result6[i]
            table.insert(data.rawSamples, {
                title = "Item " .. i,
                text = summarizeTable(item)
            })
        end
    else
        data.items.list = {}
        data.items.count = 0
        data.items.totalAmount = 0
        data.items.error = result6
    end

    -- =========================
    -- FLUIDS
    -- =========================
    local ok7, method7, result7 = tryNamedCall(bridge, {
        "listFluids", "getFluids", "getAvailableFluids"
    })
    data.fluids.method = method7
    if ok7 and type(result7) == "table" then
        data.fluids.list = result7
        data.fluids.count = #result7

        local totalFluid = 0
        for _, fluid in ipairs(result7) do
            totalFluid = totalFluid + (tonumber(fluid.amount) or 0)
        end
        data.fluids.totalAmount = totalFluid

        for i = 1, math.min(3, #result7) do
            local fluid = result7[i]
            table.insert(data.rawSamples, {
                title = "Fluid " .. i,
                text = summarizeTable(fluid)
            })
        end
    else
        data.fluids.list = {}
        data.fluids.count = 0
        data.fluids.totalAmount = 0
        data.fluids.error = result7
    end

    -- =========================
    -- CRAFTING
    -- =========================
    local ok8, method8, result8 = tryNamedCall(bridge, {
        "isCrafting"
    })
    data.crafting.isCrafting = ok8 and result8 or nil
    data.crafting.isCraftingMethod = method8

    local ok9, method9, result9 = tryNamedCall(bridge, {
        "listCraftingTasks", "getCraftingTasks"
    })
    data.crafting.tasksMethod = method9
    if ok9 and type(result9) == "table" then
        data.crafting.tasks = result9
        data.crafting.taskCount = #result9

        for i = 1, math.min(5, #result9) do
            table.insert(data.rawSamples, {
                title = "Craft " .. i,
                text = summarizeTable(result9[i])
            })
        end
    else
        data.crafting.tasks = {}
        data.crafting.taskCount = 0
        data.crafting.tasksError = result9
    end

    -- =========================
    -- EXTRA TESTS
    -- =========================
    local extraMethods = {
        "getPattern", "listPatterns", "getMaxItemDiskStorage", "getMaxFluidDiskStorage",
        "getItemStorage", "getFluidStorage", "getDisk", "listDisks"
    }

    data.general.extra = {}
    for _, m in ipairs(extraMethods) do
        if type(bridge[m]) == "function" then
            local ok, res = safeCall(bridge[m])
            data.general.extra[m] = ok and res or ("ERR: " .. tostring(res))
        end
    end

    return data
end

-- =========================
-- PAGE BUILDERS
-- =========================
local function makePages(data, bridgeName, bridgeType)
    local pages = {}

    -- Page 1 : résumé
    table.insert(pages, {
        name = "Resume",
        draw = function(mon)
            local w, h = mon.getSize()
            local y = 3

            writeAt(mon, 2, y, "Bridge", C.section); y = y + 1
            writeAt(mon, 3, y, "Nom : ", C.label)
            writeAt(mon, 10, y, trim(bridgeName or "?", w - 11), C.value); y = y + 1
            writeAt(mon, 3, y, "Type: ", C.label)
            writeAt(mon, 10, y, trim(bridgeType or "?", w - 11), C.value); y = y + 2

            writeAt(mon, 2, y, "Etat", C.section); y = y + 1
            writeAt(mon, 3, y, "Reseau   : ", C.label)
            writeAt(mon, 14, y, trim(toStr(data.general.networkName), w - 15), C.value); y = y + 1
            writeAt(mon, 3, y, "Connecte : ", C.label)
            local connected = toStr(data.general.connected)
            writeAt(mon, 14, y, connected, connected == "true" and C.ok or C.warn); y = y + 2

            writeAt(mon, 2, y, "Stockage", C.section); y = y + 1
            writeAt(mon, 3, y, "Types items : ", C.label)
            writeAt(mon, 17, y, formatNumber(data.items.count), C.value); y = y + 1
            writeAt(mon, 3, y, "Total items : ", C.label)
            writeAt(mon, 17, y, formatNumber(data.items.totalAmount), C.value); y = y + 1
            writeAt(mon, 3, y, "Types fluides:", C.label)
            writeAt(mon, 17, y, formatNumber(data.fluids.count), C.value); y = y + 1
            writeAt(mon, 3, y, "Total fluides:", C.label)
            writeAt(mon, 17, y, formatNumber(data.fluids.totalAmount), C.value); y = y + 2

            writeAt(mon, 2, y, "Craft", C.section); y = y + 1
            writeAt(mon, 3, y, "En cours : ", C.label)
            writeAt(mon, 14, y, toStr(data.crafting.isCrafting), C.value); y = y + 1
            writeAt(mon, 3, y, "Nb tasks : ", C.label)
            writeAt(mon, 14, y, formatNumber(data.crafting.taskCount), C.value); y = y + 1

            if data.energy.stored ~= nil or data.energy.max ~= nil or data.energy.usage ~= nil then
                y = y + 1
                writeAt(mon, 2, y, "Energie", C.section); y = y + 1
                writeAt(mon, 3, y, "Stocke : ", C.label)
                writeAt(mon, 13, y, formatNumber(data.energy.stored or 0), C.value); y = y + 1
                writeAt(mon, 3, y, "Max    : ", C.label)
                writeAt(mon, 13, y, formatNumber(data.energy.max or 0), C.value); y = y + 1
                writeAt(mon, 3, y, "Usage  : ", C.label)
                writeAt(mon, 13, y, formatNumber(data.energy.usage or 0), C.value); y = y + 1
            end
        end
    })

    -- Page 2 : méthodes
    table.insert(pages, {
        name = "Methodes",
        draw = function(mon)
            local _, h = mon.getSize()
            local y = 3

            writeAt(mon, 2, y, "Methodes detectees: " .. tostring(#data.methods), C.section)
            y = y + 2

            for i = 1, math.min(#data.methods, h - 5) do
                writeAt(mon, 3, y, trim(data.methods[i], 35), C.value)
                y = y + 1
            end
        end
    })

    -- Page 3 : items
    table.insert(pages, {
        name = "Items",
        draw = function(mon)
            local w, h = mon.getSize()
            local y = 3

            writeAt(mon, 2, y, "Items (" .. tostring(data.items.count) .. " types)", C.section)
            y = y + 1
            writeAt(mon, 2, y, "Methode: " .. toStr(data.items.method), C.dim)
            y = y + 2

            if #data.items.list == 0 then
                writeAt(mon, 3, y, "Aucun item ou methode indisponible", C.warn)
                return
            end

            local maxLines = h - 5
            for i = 1, math.min(#data.items.list, maxLines) do
                local item = data.items.list[i]
                local name = item.displayName or item.name or ("item#" .. i)
                local amount = item.amount or item.qty or 0

                local left = trim(name, math.max(10, w - 12))
                writeAt(mon, 2, y, left, C.value)
                local amountText = formatNumber(tonumber(amount) or 0)
                writeAt(mon, math.max(2, w - #amountText), y, amountText, C.ok)
                y = y + 1
            end
        end
    })

    -- Page 4 : fluides
    table.insert(pages, {
        name = "Fluides",
        draw = function(mon)
            local w, h = mon.getSize()
            local y = 3

            writeAt(mon, 2, y, "Fluides (" .. tostring(data.fluids.count) .. " types)", C.section)
            y = y + 1
            writeAt(mon, 2, y, "Methode: " .. toStr(data.fluids.method), C.dim)
            y = y + 2

            if #data.fluids.list == 0 then
                writeAt(mon, 3, y, "Aucun fluide ou methode indisponible", C.warn)
                return
            end

            local maxLines = h - 5
            for i = 1, math.min(#data.fluids.list, maxLines) do
                local fluid = data.fluids.list[i]
                local name = fluid.displayName or fluid.name or ("fluid#" .. i)
                local amount = fluid.amount or 0

                local left = trim(name, math.max(10, w - 12))
                writeAt(mon, 2, y, left, C.value)
                local amountText = formatNumber(tonumber(amount) or 0)
                writeAt(mon, math.max(2, w - #amountText), y, amountText, C.ok)
                y = y + 1
            end
        end
    })

    -- Page 5 : crafts
    table.insert(pages, {
        name = "Crafts",
        draw = function(mon)
            local _, h = mon.getSize()
            local y = 3

            writeAt(mon, 2, y, "Crafting Tasks (" .. tostring(data.crafting.taskCount) .. ")", C.section)
            y = y + 1
            writeAt(mon, 2, y, "Methode: " .. toStr(data.crafting.tasksMethod), C.dim)
            y = y + 2

            if #data.crafting.tasks == 0 then
                writeAt(mon, 3, y, "Aucune task ou methode indisponible", C.warn)
                return
            end

            local maxLines = h - 5
            for i = 1, math.min(#data.crafting.tasks, maxLines) do
                local task = data.crafting.tasks[i]
                writeAt(mon, 2, y, trim(summarizeTable(task), 45), C.value)
                y = y + 1
            end
        end
    })

    -- Page 6 : échantillons bruts
    table.insert(pages, {
        name = "Brut",
        draw = function(mon)
            local _, h = mon.getSize()
            local y = 3

            writeAt(mon, 2, y, "Exemples de donnees brutes", C.section)
            y = y + 2

            if #data.rawSamples == 0 then
                writeAt(mon, 3, y, "Aucun exemple brut disponible", C.warn)
                return
            end

            for i = 1, math.min(#data.rawSamples, math.floor((h - 4) / 2)) do
                local s = data.rawSamples[i]
                writeAt(mon, 2, y, "[" .. s.title .. "]", C.footer)
                y = y + 1
                writeAt(mon, 3, y, trim(s.text, 46), C.value)
                y = y + 1
            end
        end
    })

    return pages
end

-- =========================
-- DRAW FRAME
-- =========================
local function drawFrame(mon, pageName, pageIndex, pageCount, timestamp)
    local w, h = mon.getSize()
    mon.setBackgroundColor(C.bg)
    mon.clear()

    fillLine(mon, 1, C.titleBg)
    centerText(mon, 1, CONFIG.TITLE, C.titleText, C.titleBg)

    fillLine(mon, h, C.bg)
    local footerLeft = trim(CONFIG.FOOTER, math.floor(w * 0.5))
    local footerRight = "Page " .. pageIndex .. "/" .. pageCount .. " | " .. pageName .. " | " .. timestamp

    writeAt(mon, 2, h, footerLeft, C.footer, C.bg)
    local fx = math.max(#footerLeft + 4, w - #footerRight)
    writeAt(mon, fx, h, footerRight, C.dim, C.bg)
end

local function drawPage(mon, pages, index, data)
    local page = pages[index]
    drawFrame(mon, page.name, index, #pages, data.timestamp)
    page.draw(mon)
end

-- =========================
-- MAIN
-- =========================
local monName, mon = initMonitor()
local bridgeName, bridge, bridgeType = initBridge()

local pageIndex = 1
local lastRotate = os.clock()

while true do
    local ok, dataOrErr = pcall(function()
        return collectData(bridge)
    end)

    if ok then
        local data = dataOrErr
        local pages = makePages(data, bridgeName, bridgeType)

        if (os.clock() - lastRotate) >= CONFIG.PAGE_ROTATE_EVERY then
            pageIndex = pageIndex + 1
            if pageIndex > #pages then pageIndex = 1 end
            lastRotate = os.clock()
        end

        drawPage(mon, pages, pageIndex, data)
    else
        mon.setBackgroundColor(colors.black)
        mon.clear()
        fillLine(mon, 1, colors.red)
        centerText(mon, 1, "ERREUR RS BRIDGE", colors.white, colors.red)
        writeAt(mon, 2, 3, trim(tostring(dataOrErr), 45), colors.red)
        writeAt(mon, 2, 5, "Moniteur: " .. tostring(monName), colors.lightGray)
        writeAt(mon, 2, 6, "Bridge: " .. tostring(bridgeName), colors.lightGray)
    end

    sleep(CONFIG.REFRESH_INTERVAL)
end
