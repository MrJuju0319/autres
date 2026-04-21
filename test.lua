-- =========================
-- AUTO UPDATE
-- =========================
local AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/test.lua"
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
    print("Mise a jour appliquee, redemarrage...")
    sleep(1)
    os.reboot()
end

autoUpdate()

-- startup.lua
-- Refined Storage Craft Monitor
-- Compatible avec ton format getCraftingTasks()
-- task.resource / task.quantity / task.completion

local bridge = peripheral.find("rs_bridge")
if not bridge then
    error("rs_bridge non detecte")
end

local mon = peripheral.find("monitor")
if not mon then
    error("monitor non detecte")
end

mon.setTextScale(0.5)

local history = {}

local function clear()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function trim(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    if maxLen <= 3 then return text:sub(1, maxLen) end
    return text:sub(1, maxLen - 3) .. "..."
end

local function getTasks()
    local ok, tasks = pcall(function()
        return bridge.getCraftingTasks()
    end)
    if ok and type(tasks) == "table" then
        return tasks
    end
    return {}
end

local function drawBar(x, y, w, progress, total)
    local filled = 0
    if total > 0 then
        filled = math.floor((progress / total) * w + 0.5)
        if filled < 0 then filled = 0 end
        if filled > w then filled = w end
    end

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ", w))

    if filled > 0 then
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(colors.green)
        mon.write(string.rep(" ", filled))
    end

    mon.setBackgroundColor(colors.black)
end

local function getName(task)
    if task.resource then
        return task.resource.displayName or task.resource.name or "Inconnu"
    end
    return "Inconnu"
end

local function getId(task, index)
    return task.id or ("task_" .. tostring(index))
end

local function getProgress(task)
    local total = tonumber(task.quantity) or tonumber(task.resource and task.resource.count) or 0
    local completion = tonumber(task.completion) or 0
    if completion < 0 then completion = 0 end
    if completion > 1 then completion = 1 end

    local current = total * completion
    return current, total, completion
end

local function getStatus(task)
    local completion = tonumber(task.completion) or 0

    if completion >= 1 then
        return "Termine", colors.lime
    elseif completion > 0 then
        return "En cours", colors.yellow
    else
        return "Attente", colors.lightGray
    end
end

local function getPercent(completion)
    return math.floor((completion or 0) * 100 + 0.5)
end

local function getTextIcon(task)
    local res = task.resource or {}
    local name = res.displayName or res.name or "?"
    local raw = res.name or name

    if raw:find("extrastorage:disk_") then
        return "[D]"
    end

    local words = {}
    for w in name:gmatch("[%w]+") do
        words[#words + 1] = w
    end

    if #words >= 2 then
        return "[" .. words[1]:sub(1,1):upper() .. words[2]:sub(1,1):upper() .. "]"
    elseif #words == 1 then
        return "[" .. words[1]:sub(1, math.min(2, #words[1])):upper() .. "]"
    end

    return "[?]"
end

local function formatTime(seconds)
    if not seconds or seconds < 0 or seconds == math.huge then
        return "--:--"
    end

    seconds = math.floor(seconds + 0.5)

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60

    if h > 0 then
        return string.format("%dh%02dm%02ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm%02ds", m, s)
    else
        return string.format("%ds", s)
    end
end

local function estimateRemaining(task, index, currentProgress, total, completion)
    local id = getId(task, index)
    local now = os.epoch("utc") / 1000

    local entry = history[id]
    if not entry then
        history[id] = {
            lastProgress = currentProgress,
            lastTime = now,
            rate = nil,
        }
        return nil
    end

    local dt = now - entry.lastTime
    local dp = currentProgress - entry.lastProgress

    if dt > 0 and dp > 0 then
        local instantRate = dp / dt

        if entry.rate then
            entry.rate = (entry.rate * 0.7) + (instantRate * 0.3)
        else
            entry.rate = instantRate
        end
    end

    entry.lastProgress = currentProgress
    entry.lastTime = now

    if completion >= 1 then
        return 0
    end

    if not entry.rate or entry.rate <= 0 then
        return nil
    end

    local remaining = total - currentProgress
    if remaining <= 0 then
        return 0
    end

    return remaining / entry.rate
end

local function cleanupHistory(tasks)
    local alive = {}
    for i, task in ipairs(tasks) do
        alive[getId(task, i)] = true
    end

    for id, _ in pairs(history) do
        if not alive[id] then
            history[id] = nil
        end
    end
end

local function draw()
    clear()

    local w, h = mon.getSize()
    local tasks = getTasks()
    cleanupHistory(tasks)

    mon.setCursorPos(1, 1)
    mon.setTextColor(colors.cyan)
    mon.write(trim("Refined Storage - Crafts", w))

    local right = "Jobs: " .. tostring(#tasks)
    mon.setCursorPos(math.max(1, w - #right + 1), 1)
    mon.setTextColor(colors.lightGray)
    mon.write(right)

    mon.setCursorPos(1, 2)
    mon.setTextColor(colors.gray)
    mon.write(string.rep("-", w))

    if #tasks == 0 then
        mon.setCursorPos(1, 4)
        mon.setTextColor(colors.lime)
        mon.write("Aucun craft en cours")
        return
    end

    local linesPerTask = 5
    local maxTasks = math.max(1, math.floor((h - 2) / linesPerTask))
    local y = 3

    for i = 1, math.min(#tasks, maxTasks) do
        local task = tasks[i]

        local name = getName(task)
        local icon = getTextIcon(task)
        local progress, total, completion = getProgress(task)
        local percent = getPercent(completion)
        local status, statusColor = getStatus(task)
        local eta = estimateRemaining(task, i, progress, total, completion)

        local progressInt = math.floor(progress + 0.5)
        local label = progressInt .. "/" .. tostring(total) .. " " .. percent .. "%"
        local etaText = "ETA " .. formatTime(eta)

        mon.setCursorPos(1, y)
        mon.setTextColor(colors.yellow)
        mon.write(trim("[" .. i .. "] " .. icon .. " " .. name, w))
        y = y + 1

        mon.setCursorPos(2, y)
        mon.setTextColor(statusColor)
        mon.write(trim("Etat: " .. status, w))
        y = y + 1

        local barWidth = math.max(10, w - 2)
        drawBar(2, y, barWidth, progress, total > 0 and total or 1)
        y = y + 1

        mon.setCursorPos(2, y)
        mon.setTextColor(colors.white)
        mon.write(trim(label, w - 1))

        mon.setCursorPos(math.max(2, w - #etaText + 1), y)
        mon.setTextColor(colors.lightBlue)
        mon.write(trim(etaText, math.max(1, w - (math.max(2, w - #etaText + 1)) + 1)))
        y = y + 1

        mon.setCursorPos(1, y)
        mon.setTextColor(colors.gray)
        mon.write(string.rep("-", w))
        y = y + 1
    end
end

while true do
    draw()
    sleep(1)
end
