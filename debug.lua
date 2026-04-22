-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    AUTO_UPDATE_URL = "https://raw.githubusercontent.com/MrJuju0319/autres/refs/heads/main/debug.lua",
    AUTO_UPDATE_ENABLED = true,
    AUTO_UPDATE_FILE = "startup.lua",
    AUTO_UPDATE_TMP = "startup.lua.tmp"
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
