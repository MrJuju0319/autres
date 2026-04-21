-- rs_debug.lua
-- Debug complet RS Bridge pour CC:Tweaked / Advanced Peripherals

local BRIDGE_TYPES = { "rs_bridge", "rsBridge" }
local OUTPUT_FILE = "rs_debug_output.txt"

local out = {}

local function log(msg)
  msg = tostring(msg or "")
  print(msg)
  table.insert(out, msg)
end

local function section(title)
  log("")
  log(string.rep("=", 70))
  log(title)
  log(string.rep("=", 70))
end

local function safeCall(fn)
  local ok, a, b, c, d, e = pcall(fn)
  if ok then
    return true, { a, b, c, d, e }
  else
    return false, { a }
  end
end

local function serialize(v)
  return textutils.serialize(v, { compact = false })
end

-- helper inspire de ton wrapPs, mais corrige
local function wrapPs(peripheralType)
  local periTab = {}
  local sideTab = {}

  if peripheralType == nil then
    return nil, nil
  end

  local peripherals = peripheral.getNames()
  local i2 = 1

  for i = 1, #peripherals do
    local pName = peripherals[i]
    if peripheral.getType(pName) == peripheralType then
      periTab[i2] = peripheral.wrap(pName)
      sideTab[i2] = pName
      i2 = i2 + 1
    end
  end

  if #periTab > 0 then
    return periTab, sideTab
  end

  return nil, nil
end

local function findBridge()
  for _, t in ipairs(BRIDGE_TYPES) do
    local tabs, sides = wrapPs(t)
    if tabs and tabs[1] then
      return tabs[1], sides[1], t
    end
  end
  return nil, nil, nil
end

local bridge, bridgeSide, bridgeType = findBridge()
if not bridge then
  error("Aucun RS Bridge detecte (types testes: rs_bridge, rsBridge)")
end

section("INFOS BRIDGE")
log("Type detecte : " .. tostring(bridgeType))
log("Nom / side    : " .. tostring(bridgeSide))

section("PERIPHERIQUES DETECTES")
for _, name in ipairs(peripheral.getNames()) do
  log(("- %s -> %s"):format(name, tostring(peripheral.getType(name))))
end

section("METHODES DU BRIDGE")
local methods = peripheral.getMethods(bridgeSide) or {}
table.sort(methods)
for _, m in ipairs(methods) do
  log("- " .. m)
end

local function tryBridgeMethod(methodName, ...)
  section("TEST METHODE : " .. methodName)

  if type(bridge[methodName]) ~= "function" then
    log("Methode absente")
    return nil
  end

  local args = { ... }
  local ok, res = safeCall(function()
    return bridge[methodName](table.unpack(args))
  end)

  if ok then
    log("Appel OK")
    log(serialize(res[1]))
    return res[1]
  else
    log("Erreur : " .. tostring(res[1]))
    return nil
  end
end

local function inspectTask(task, index)
  section("INSPECTION TASK #" .. tostring(index))
  log("RAW TASK :")
  log(serialize(task))

  if type(task) ~= "table" then
    log("La task n'est pas une table")
    return
  end

  local keys = {}
  for k, _ in pairs(task) do
    table.insert(keys, k)
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  log("")
  log("CLES DE LA TASK :")
  for _, k in ipairs(keys) do
    log((" - %s (%s)"):format(tostring(k), type(task[k])))
  end

  log("")
  log("APPEL DES METHODES DE LA TASK :")
  for _, k in ipairs(keys) do
    if type(task[k]) == "function" then
      local ok, res = safeCall(function()
        return task[k]()
      end)

      if ok then
        log("")
        log("task." .. tostring(k) .. "() ->")
        log(serialize(res[1]))
      else
        log("")
        log("task." .. tostring(k) .. "() -> ERREUR")
        log(tostring(res[1]))
      end
    end
  end
end

-- méthodes utiles d'après la doc / ton script
local tasks = tryBridgeMethod("getCraftingTasks")
tryBridgeMethod("listCraftableItems")
tryBridgeMethod("listItems")
tryBridgeMethod("listFluids")
tryBridgeMethod("getEnergyStorage")
tryBridgeMethod("getMaxEnergyStorage")
tryBridgeMethod("getMaxItemDiskStorage")
tryBridgeMethod("getMaxFluidDiskStorage")
tryBridgeMethod("getItem", { name = "minecraft:oak_planks" })
tryBridgeMethod("isItemCraftable", { name = "minecraft:oak_planks" })
tryBridgeMethod("isItemCrafting", { name = "minecraft:oak_planks" })
tryBridgeMethod("getPattern", { name = "minecraft:oak_planks" })

section("INSPECTION DES TASKS")
if type(tasks) == "table" then
  log("Nombre de tasks: " .. tostring(#tasks))
  log("DUMP BRUT:")
  log(serialize(tasks))

  for i, task in ipairs(tasks) do
    inspectTask(task, i)
  end
else
  log("getCraftingTasks ne retourne pas de table exploitable")
end

section("ECRITURE FICHIER")
local fh = fs.open(OUTPUT_FILE, "w")
if not fh then
  error("Impossible d'ecrire " .. OUTPUT_FILE)
end

for _, line in ipairs(out) do
  fh.writeLine(line)
end
fh.close()

log("Fichier cree : " .. OUTPUT_FILE)
log("Commande utile : edit " .. OUTPUT_FILE)
