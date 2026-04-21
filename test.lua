-- startup.lua (VERSION CORRIGEE POUR TON RS)

local bridge = peripheral.find("rs_bridge")
local mon = peripheral.find("monitor")

mon.setTextScale(0.5)

local function clear()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1,1)
end

local function getTasks()
    return bridge.getCraftingTasks() or {}
end

local function drawBar(x,y,w,progress,total)
    local filled = 0
    if total > 0 then
        filled = math.floor((progress/total)*w)
    end

    mon.setCursorPos(x,y)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ",w))

    mon.setCursorPos(x,y)
    mon.setBackgroundColor(colors.green)
    mon.write(string.rep(" ",filled))

    mon.setBackgroundColor(colors.black)
end

local function getName(task)
    if task.resource then
        return task.resource.displayName or task.resource.name
    end
    return "Inconnu"
end

local function getProgress(task)
    local total = task.quantity or 0
    local completion = task.completion or 0
    local current = math.floor(total * completion)

    return current, total
end

local function getStatus(task)
    if task.completion >= 1 then
        return "Termine", colors.lime
    end

    if task.completion > 0 then
        return "En cours", colors.yellow
    end

    return "Attente", colors.gray
end

local function draw()
    clear()

    local w,h = mon.getSize()
    local tasks = getTasks()

    mon.setCursorPos(1,1)
    mon.setTextColor(colors.cyan)
    mon.write("Refined Storage - Crafts")

    if #tasks == 0 then
        mon.setCursorPos(1,3)
        mon.setTextColor(colors.lime)
        mon.write("Aucun craft")
        return
    end

    local y = 3

    for i,task in ipairs(tasks) do
        if y > h-3 then break end

        local name = getName(task)
        local prog,total = getProgress(task)
        local status,color = getStatus(task)

        mon.setCursorPos(1,y)
        mon.setTextColor(colors.yellow)
        mon.write("["..i.."] "..name)
        y = y + 1

        mon.setCursorPos(2,y)
        mon.setTextColor(color)
        mon.write("Etat: "..status)
        y = y + 1

        drawBar(2,y,w-10,prog,total)

        mon.setCursorPos(w-8,y)
        mon.setTextColor(colors.white)
        mon.write(prog.."/"..total)
        y = y + 2
    end
end

while true do
    draw()
    sleep(1)
end
