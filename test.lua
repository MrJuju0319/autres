-- rs_debug.lua
-- Debug complet du peripheral rs_bridge

local BRIDGE_TYPE = "rs_bridge"
local OUTPUT_FILE = "rs_debug_output.txt"

local bridge = peripheral.find(BRIDGE_TYPE)
if not bridge then
    error("rs_bridge non detecte")
end

local function safeCall(fn)
    local ok, a, b, c, d, e = pcall(fn)
    if ok then
        return true, {a, b, c, d, e}
    end
    return false, {a}
end

local function serialize(value)
    return textutils.serialize(value, { compact = false })
end

local out = {}

local function log(line)
    line = tostring(line or "")
    out[#out + 1] = line
    print(line)
end

local function logSection(title)
    log("")
    log(string.rep("=", 60))
    log(title)
    log(string.rep("=", 60))
end

local function dumpValue(name, value)
    log(name .. " =")
    log(serialize(value))
end

local function listPeripheralNames()
    logSection("PERIPHERIQUES DETECTES")
    for _, name in ipairs(peripheral.getNames()) do
        log(("- %s -> %s"):format(name, tostring(peripheral.getType(name))))
    end
end

local function listBridgeMethods()
    logSection("METHODES DU RS_BRIDGE")

    local methods = peripheral.getMethods(peripheral.getName(bridge) or "unknown")
    if not methods then
        log("Impossible de recuperer la liste via peripheral.getMethods")
        return
    end

    table.sort(methods)
    for _, method in ipairs(methods) do
        log("- " .. method)
    end
end

local function tryMethod(methodName, ...)
    logSection("TEST METHODE : " .. methodName)

    if type(bridge[methodName]) ~= "function" then
        log("Methode absente")
        return nil
    end

    local args = {...}
    local ok, results = safeCall(function()
        return bridge[methodName](table.unpack(args))
    end)

    if ok then
        log("Appel OK")
        dumpValue("resultat", results[1])
        return results[1]
    else
        log("Erreur : " .. tostring(results[1]))
        return nil
    end
end

local function inspectTask(task, index)
    logSection("INSPECTION TASK #" .. tostring(index))

    dumpValue("task_raw", task)

    if type(task) ~= "table" then
        log("Task non-table")
        return
    end

    local keys = {}
    for k, _ in pairs(task) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)

    log("Cles de la task :")
    for _, k in ipairs(keys) do
        local v = task[k]
        log((" - %s (%s)"):format(k, type(v)))
    end

    for _, k in ipairs(keys) do
        if type(task[k]) == "function" then
            local ok, results = safeCall(function()
                return task[k]()
            end)

            if ok then
                log("")
                log("Appel task:" .. k .. "() OK")
                log(serialize(results[1]))
            else
                log("")
                log("Appel task:" .. k .. "() ERREUR")
                log(tostring(results[1]))
            end
        end
    end
end

local function inspectTasks(tasks)
    logSection("INSPECTION DES TASKS")

    if type(tasks) ~= "table" then
        log("getCraftingTasks n'a pas retourne une table")
        return
    end

    log("Nombre de tasks: " .. tostring(#tasks))
    dumpValue("tasks_brut", tasks)

    for i, task in ipairs(tasks) do
        inspectTask(task, i)
    end
end

local function saveToFile(path)
    local h = fs.open(path, "w")
    if not h then
        error("Impossible d'ecrire dans " .. path)
    end

    for _, line in ipairs(out) do
        h.writeLine(line)
    end

    h.close()
end

-- =========================
-- EXECUTION
-- =========================

logSection("DEBUG RS BRIDGE")
log("Nom peripheral : " .. tostring(peripheral.getName(bridge)))
log("Type peripheral: " .. tostring(peripheral.getType(peripheral.getName(bridge))))

listPeripheralNames()
listBridgeMethods()

-- Appels les plus probables / utiles
local tasks = tryMethod("getCraftingTasks")
tryMethod("listCraftingTasks")
tryMethod("isConnected")
tryMethod("getPattern")
tryMethod("getPatterns")
tryMethod("listItems")
tryMethod("getItem", { name = "minecraft:stone", count = 1 })
tryMethod("listFluids")
tryMethod("listCraftableItems")
tryMethod("listCraftables")
tryMethod("getEnergyStorage")
tryMethod("getMaxEnergyStorage")
tryMethod("getDiskCapacity")
tryMethod("getDiskUsage")

inspectTasks(tasks)

saveToFile(OUTPUT_FILE)

logSection("TERMINE")
log("Sortie enregistree dans : " .. OUTPUT_FILE)
