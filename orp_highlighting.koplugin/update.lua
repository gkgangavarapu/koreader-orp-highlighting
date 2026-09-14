--[[--
Update checker and installer for ORP Highlighting.

Checks GitHub Releases for a newer version, and (only after an explicit user
confirmation) downloads the release zip, verifies its SHA-256, extracts it to a
staging directory, and swaps the running plugin folder for the new one. A
KOReader restart is required for the new code to load.

Read-only check by default; no telemetry. Installation is fail-safe: the
previous plugin folder is kept as a backup and restored if the swap fails.

@module koplugin.orp_highlighting.update
--]]--

local Update = {}

-- Version of the code in this repository. Bump together with the git tag.
Update.VERSION = "0.2.3"

local REPO = "gkgangavarapu/koreader-orp-highlighting"
local API_URL = "https://api.github.com/repos/" .. REPO .. "/releases/latest"
local PAGE_URL = "https://github.com/" .. REPO .. "/releases/latest"
local PLUGIN_FOLDER = "orp_highlighting.koplugin"

local ok_logger, logger = pcall(require, "logger")
if not ok_logger then
    logger = { info = function() end, warn = function() end, err = function() end, dbg = function() end }
end

local function koreader_util()
    local ok, util = pcall(require, "util")
    return ok and util or nil
end

local function ffi_util()
    local ok, ffiUtil = pcall(require, "ffi/util")
    return ok and ffiUtil or nil
end

-- `ffi/util` has no pathExists; use lfs (or io.open as a fallback).
local function path_exists(path)
    if type(path) ~= "string" or path == "" then return false end
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then
        return lfs.attributes(path, "mode") ~= nil
    end
    local file = io.open(path, "r")
    if file then file:close() return true end
    return false
end

-- Minimal GET helper shared by the check and the downloads.
local function http_get(url, headers)
    local ok_http, http = pcall(require, "socket.http")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    if not (ok_http and ok_ltn12) then
        return nil, "network support unavailable"
    end
    local sink = {}
    local request = {
        url = url,
        headers = headers or {},
        sink = ltn12.sink.table(sink),
        redirect = true,
    }
    -- LuaSocket returns (1, code, headers, status) on success, or (nil, err).
    local call_ok, ok, code = pcall(http.request, request)
    if not call_ok or not ok then
        return nil, tostring(code)
    end
    if type(code) == "number" and (code < 200 or code >= 300) then
        return nil, "HTTP " .. tostring(code)
    end
    return table.concat(sink)
end

--------------------------------------------------------------------------------
-- Release parsing
--------------------------------------------------------------------------------

-- Pure: extract the version and asset URLs from a GitHub Releases API body.
function Update.parse_release(body)
    if type(body) ~= "string" then return nil end
    local tag = body:match('"tag_name"%s*:%s*"v?([^"]+)"')
    if not tag then return nil end
    local zip_url = body:match('"browser_download_url"%s*:%s*"(https://[^"]+%.zip)"')
    local sha_url = body:match('"browser_download_url"%s*:%s*"(https://[^"]+%.zip%.sha256)"')
    return {
        version = tag,
        zip_url = zip_url,
        sha_url = sha_url,
        page_url = PAGE_URL,
    }
end

-- Returns release info, error.
function Update.check(_opts)
    local body, err = http_get(API_URL, {
        ["Accept"] = "application/vnd.github+json",
        ["User-Agent"] = "orp_highlighting",
    })
    if not body then
        return nil, err or "network error"
    end
    local info = Update.parse_release(body)
    if not info then
        return nil, "invalid response"
    end
    return info, nil
end

local function parse_version(v)
    local parts = {}
    for n in tostring(v):gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
    return parts
end

function Update.is_newer(latest, current)
    local a, b = parse_version(latest), parse_version(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

--------------------------------------------------------------------------------
-- Download / hash / extract / swap
--------------------------------------------------------------------------------

-- Download a URL to a file. Returns ok, error.
function Update.download(url, dest)
    local ok_http, http = pcall(require, "socket.http")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    if not (ok_http and ok_ltn12) then
        return false, "network support unavailable"
    end
    local file = io.open(dest, "wb")
    if not file then return false, "cannot write file" end
    local ok, code = http.request{
        url = url,
        headers = { ["User-Agent"] = "orp_highlighting" },
        sink = ltn12.sink.file(file),
        redirect = true,
    }
    if not ok or (type(code) == "number" and code ~= 200) then
        os.remove(dest)
        return false, tostring(code)
    end
    return true
end

function Update.sha256File(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("*a")
    file:close()
    if not data then return nil end
    local ok, sha2 = pcall(require, "ffi/sha2")
    if ok and sha2 and type(sha2.sha256) == "function" then
        return sha2.sha256(data)
    end
    return nil
end

function Update.readExpectedSha(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content and content:match("(%x%x%x%x%x%x%x%x+)")
end

-- Extract a release zip into dest_dir, validating paths and layout.
function Update.extract(zip_path, dest_dir)
    local ok, archiver = pcall(require, "ffi/archiver")
    if not ok or not archiver then
        return false, "archive support unavailable"
    end
    local util = koreader_util()
    local reader = archiver.Reader:new()
    if not reader:open(zip_path) then
        return false, "cannot open archive"
    end

    local found_main = false
    for entry in reader:iterate() do
        if entry.mode == "file" then
            local p = entry.path
            if not p or p:sub(1, 1) == "/" or p:find("%.%.") then
                reader:close()
                return false, "unsafe archive path"
            end
            local dest = dest_dir .. "/" .. p
            local parent = dest:match("^(.*)/[^/]*$")
            if parent and util then util.makePath(parent) end
            reader:extractToPath(p, dest)
            if p == PLUGIN_FOLDER .. "/main.lua" then found_main = true end
        end
    end
    reader:close()
    if not found_main then
        return false, "archive missing plugin"
    end
    return true
end

-- Replace plugin_dir with staged_plugin, keeping a backup.
function Update.swap(plugin_dir, staged_plugin)
    local ffiUtil = ffi_util()
    if not ffiUtil then return false, "filesystem helpers unavailable" end
    local backup = plugin_dir .. ".bak"
    if path_exists(backup) then ffiUtil.purgeDir(backup) end
    if not os.rename(plugin_dir, backup) then
        return false, "cannot back up current plugin"
    end
    if not os.rename(staged_plugin, plugin_dir) then
        os.rename(backup, plugin_dir)
        return false, "cannot install update"
    end
    return true
end

-- Remove a leftover backup from a previous successful update.
function Update.cleanupBackup(plugin_dir)
    local ffiUtil = ffi_util()
    if not ffiUtil or not plugin_dir then return end
    local backup = plugin_dir .. ".bak"
    if path_exists(backup) then ffiUtil.purgeDir(backup) end
end

function Update.isWritable(plugin_dir)
    local probe = plugin_dir .. "/.orp_highlighting_write_test"
    local file = io.open(probe, "w")
    if not file then return false end
    file:close()
    os.remove(probe)
    return true
end

-- Full install: download -> verify -> extract -> swap. Returns ok, error.
function Update.install(info, plugin_dir)
    if type(info) ~= "table" or not info.zip_url or not info.sha_url then
        return false, "no update available"
    end
    local ok_ds, DataStorage = pcall(require, "datastorage")
    local util = koreader_util()
    local ffiUtil = ffi_util()
    if not (ok_ds and util and ffiUtil) then
        return false, "install environment unavailable"
    end

    local base = DataStorage:getSettingsDir() .. "/orp_highlighting/update"
    if path_exists(base) then ffiUtil.purgeDir(base) end
    util.makePath(base)

    local zip_path = base .. "/update.zip"
    local sha_path = base .. "/update.zip.sha256"

    local ok, err = Update.download(info.zip_url, zip_path)
    if not ok then return false, "download: " .. tostring(err) end
    ok, err = Update.download(info.sha_url, sha_path)
    if not ok then return false, "checksum download: " .. tostring(err) end

    local expected = Update.readExpectedSha(sha_path)
    local actual = Update.sha256File(zip_path)
    if not expected or not actual or expected ~= actual then
        return false, "checksum mismatch"
    end

    local staging = base .. "/staging"
    util.makePath(staging)
    ok, err = Update.extract(zip_path, staging)
    if not ok then return false, "extract: " .. tostring(err) end

    local staged_plugin = staging .. "/" .. PLUGIN_FOLDER
    if not path_exists(staged_plugin) then
        return false, "staged plugin missing"
    end

    ok, err = Update.swap(plugin_dir, staged_plugin)
    if not ok then return false, "swap: " .. tostring(err) end

    if path_exists(base) then ffiUtil.purgeDir(base) end
    logger.info("orp_highlighting update: installed", info.version)
    return true
end

Update.REPO = REPO
Update.PAGE_URL = PAGE_URL
Update.PLUGIN_FOLDER = PLUGIN_FOLDER

return Update
