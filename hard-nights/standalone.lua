if not game:IsLoaded() then game.Loaded:Wait() end

local globals = getgenv()
if globals.StandaloneHardNightsRunning then return end
globals.StandaloneHardNightsRunning = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local LOBBY_PLACE_ID = 3260590327
local ROOT_URL = "https://raw.githubusercontent.com/zaixxy123/Try/refs/heads/main/hard-nights/"
local APIS_URL = "https://raw.githubusercontent.com/zaixxy123/lists/refs/heads/main/apis2"
local PUZZLE_URL = "https://raw.githubusercontent.com/zaixxy123/lists/refs/heads/main/puzzle.lua"
local GATLIFY_URL = "https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"
local LOADOUT = {"DJ Booth", "Gatling Gun", "Mercenary Base", "Hacker", "Assassin"}
local started = {}
local finished = {}
local gatlifyLoaded = false
local gatlifyLoading = false

local function Status(message)
    print("[Hard Nights] " .. message)
end

local function LoadTDS()
    local source = game:HttpGet(APIS_URL)
    local chunk, err = loadstring(source)
    if not chunk then error(err) end
    local tds = chunk()
    if type(tds) ~= "table" then error("apis2 did not return a table") end
    return tds
end

local function GetState()
    local folder = ReplicatedStorage:FindFirstChild("StateReplicators")
    return folder and folder:FindFirstChild("GameStateReplicator")
end

local function GetNight(state)
    local difficulty = tostring(state:GetAttribute("Difficulty") or "")
    local night = difficulty:match("^Act([1-4])$")
    if not night and difficulty == "" then
        local display = tostring(state:GetAttribute("DifficultyDisplayName") or "")
        night = display:match("^Act%s*([1-4])$")
            or display:match("^Night%s*([1-4])%s*Hard$")
    end
    return tonumber(night)
end

local function GetPlayerReplicator()
    local folder = ReplicatedStorage:FindFirstChild("StateReplicators")
    if not folder then return nil end
    for _, rep in ipairs(folder:GetChildren()) do
        if rep.Name == "PlayerReplicator"
            and tonumber(rep:GetAttribute("UserId")) == LocalPlayer.UserId then
            return rep
        end
    end
end

local function ReadEquipped(rep)
    local raw = rep and rep:GetAttribute("EquippedTowers")
    local json = type(raw) == "string" and raw:match("%[.*%]")
    if not json then return {} end
    local ok, value = pcall(function() return HttpService:JSONDecode(json) end)
    if ok and type(value) == "table" then return value end
    return {}
end

local function HasRequiredLoadout(rep)
    local equipped = {}
    for _, tower in ipairs(ReadEquipped(rep)) do equipped[tower] = true end
    for _, tower in ipairs(LOADOUT) do
        if not equipped[tower] then return false end
    end
    return true
end

local function EquipLobby()
    local rep
    local deadline = os.clock() + 20
    repeat
        rep = GetPlayerReplicator()
        if not rep then task.wait(0.2) end
    until rep or os.clock() >= deadline
    if not rep then return false end
    if HasRequiredLoadout(rep) then return true end

    local remote = ReplicatedStorage:WaitForChild("RemoteEvent", 10)
    if not remote then return false end
    for _, tower in ipairs(ReadEquipped(rep)) do
        if tower ~= "" and tower ~= "None" then
            remote:FireServer("Inventory", "Unequip", "Tower", tower)
            task.wait(0.3)
        end
    end
    task.wait(0.2)
    for _, tower in ipairs(LOADOUT) do
        remote:FireServer("Inventory", "Equip", "Tower", tower)
        task.wait(0.3)
    end
    deadline = os.clock() + 8
    repeat
        if HasRequiredLoadout(rep) then return true end
        task.wait(0.2)
    until os.clock() >= deadline
    return HasRequiredLoadout(rep)
end

local function BackToLobby()
    local network = ReplicatedStorage:FindFirstChild("Network")
    local teleport = network and network:FindFirstChild("Teleport")
    local remote = teleport and teleport:FindFirstChild("RE:backToLobby")
    if remote then
        pcall(function() remote:FireServer() end)
        task.wait(5)
    end
    if game.PlaceId ~= LOBBY_PLACE_ID then
        pcall(function()
            TeleportService:Teleport(LOBBY_PLACE_ID, LocalPlayer)
        end)
    end
end

local function NextNight()
    local network = ReplicatedStorage:WaitForChild("Network", 10)
    local halloween = network and network:WaitForChild("Halloween2026", 10)
    local remote = halloween and halloween:WaitForChild("RF:NextNight", 10)
    if not remote then return false end
    local ok, result = pcall(function() return remote:InvokeServer() end)
    return ok and result ~= false
end

local function QueueRelaunch()
    local queue = queue_on_teleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if type(queue) == "function" then
        pcall(queue, 'loadstring(game:HttpGet("' .. ROOT_URL .. 'standalone.lua"))()')
    end
end

local function StartGatlify(state)
    if gatlifyLoaded or gatlifyLoading then return end
    gatlifyLoading = true
    task.spawn(function()
        while state.Parent
            and state:GetAttribute("GameStarted") ~= true
            and state:GetAttribute("GameOver") ~= true do
            task.wait(0.1)
        end

        if not state.Parent or state:GetAttribute("GameOver") == true then
            gatlifyLoading = false
            return
        end

        local ok, err = pcall(function()
            local source = game:HttpGet(GATLIFY_URL)
            local chunk, compileError = loadstring(source)
            if not chunk then error(compileError) end
            chunk()
        end)

        gatlifyLoading = false
        if ok then
            gatlifyLoaded = true
            Status("Gatlify loaded")
        else
            warn("[Hard Nights] Gatlify:", err)
        end
    end)
end

local function StartPuzzle(state)
    task.spawn(function()
        while state.Parent
            and state:GetAttribute("GameStarted") ~= true
            and state:GetAttribute("GameOver") ~= true do
            task.wait(0.2)
        end
        if not state.Parent or state:GetAttribute("GameOver") == true then return end
        if type(globals._MoonPuzzleCleanup) == "function" then return end
        local ok, err = pcall(function()
            local source = game:HttpGet(PUZZLE_URL)
            local chunk, compileError = loadstring(source)
            if not chunk then error(compileError) end
            chunk()
        end)
        if not ok then warn("[Hard Nights] Moon Puzzle:", err) end
    end)
end

local function RunNight(tds, night, state)
    started[night] = true
    tds.PlacedTowers = {}
    tds.placed_towers = tds.PlacedTowers
    tds.StackCounts = {}
    StartGatlify(state)
    if night == 4 then StartPuzzle(state) end
    Status("Running Night " .. night .. " Hard")
    task.spawn(function()
        local ok, err = pcall(function()
            local source = game:HttpGet(ROOT_URL .. "night" .. night .. ".lua")
            local chunk, compileError = loadstring(source)
            if not chunk then error(compileError) end
            local strategy = chunk()
            if type(strategy) ~= "function" then error("Strategy must return a function") end
            strategy(tds)
        end)
        if not ok then warn("[Hard Nights] Strategy " .. night .. ":", err) end
    end)
end

local ok, err = pcall(function()
    QueueRelaunch()
    local tds = LoadTDS()

    if game.PlaceId == LOBBY_PLACE_ID then
        Status("Equipping lobby loadout")
        local loadoutOK = tds:Loadout("DJ Booth", "Gatling Gun", "Mercenary Base", "Hacker", "Assassin")
        if loadoutOK ~= true and not EquipLobby() then
            warn("[Hard Nights] Failed to equip five towers")
            return
        end
        Status("Matchmaking Night 1 Hard")
        tds:Mode("Act1")
        return
    end

    while true do
        local state = GetState()
        local night = state and GetNight(state)
        if state and night then
            if not started[night] and state:GetAttribute("GameOver") ~= true then
                RunNight(tds, night, state)
            end

            if started[night] and state:GetAttribute("GameOver") == true
                and not finished[night] then
                finished[night] = true
                local deadline = os.clock() + 5
                local health = tonumber(state:GetAttribute("Health"))
                while state.Parent and health == nil
                    and os.clock() < deadline do
                    task.wait(0.2)
                    health = tonumber(state:GetAttribute("Health"))
                end

                if health == nil then
                    warn("[Hard Nights] Health unavailable after GameOver. Stopping safely.")
                    return
                end

                if health <= 0 then
                    Status("Night " .. night .. " lost. Returning to lobby")
                    BackToLobby()
                    return
                end

                if night == 4 then
                    Status("Night 4 won. Finished.")
                    return
                end

                Status("Night " .. night .. " won. Advancing.")
                if not NextNight() then
                    warn("[Hard Nights] NextNight failed. No repeat matchmaking.")
                    return
                end
            end
        end
        task.wait(0.25)
    end
end)

globals.StandaloneHardNightsRunning = false
if not ok then warn("[Hard Nights]", err) end
