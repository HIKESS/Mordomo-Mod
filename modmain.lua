-- modmain.lua
-- Mordomo-Mod 主入口
-- ────────────────────────────────────────────────────────────
-- 职责：
--   1. 读取配置并注入 mordomo/tuning
--   2. 注册 Prefab（mordomo_warly）与动画资源
--   3. 注册 "Mordomo"/"Command" RPC → commands.lua
--   4. 自动生成 Warly（auto 模式：首日主机旁）
--   5. 客户端热键打开命令菜单（Follow / Cook Here / Stop）

local MordomoCommands = require("mordomo/commands")
local TUNING_MOD      = require("mordomo/tuning")

-- ════════════════════════════════════════════════════════════
--  配置
-- ════════════════════════════════════════════════════════════
local SPAWN_MODE = GetModConfigData("spawn_mode")   or "auto"
local HOTKEY_STR = GetModConfigData("hotkey")        or "M"
local COOK_RANGE = GetModConfigData("cook_range")    or 17
local COOK_SPEED = GetModConfigData("cook_speed_mult") or 0.5
local DEBUG_MODE = GetModConfigData("debug") == true

-- 注入到调参表（供 brain / planner / storage 读取）
TUNING_MOD.COOK_RANGE_DEFAULT = COOK_RANGE
TUNING_MOD.FARM_WORK_RADIUS   = COOK_RANGE
TUNING_MOD.CHARACTER_STATS.warly.cook_time_mult = COOK_SPEED
TUNING_MOD.DEBUG_BEHAVIOR = DEBUG_MODE
TUNING_MOD.DEBUG_COOKING  = DEBUG_MODE

-- ════════════════════════════════════════════════════════════
--  Prefab 与资源
-- ════════════════════════════════════════════════════════════
PrefabFiles = {
    "mordomo_warly",
}

Assets = {
    Asset("ANIM", "anim/wilson.zip"),   -- 玩家标准动画（内置）
    Asset("ANIM", "anim/warly.zip"),    -- Warly 外观（内置）
}

-- 字符串（简单本地化）
STRINGS.NAMES.MORDOMO_WARLY = "Warly"
STRINGS.CHARACTERS.GENERIC.DESCRIBE.MORDOMO_WARLY = "Um chefe de cozinha dedicado."

-- ════════════════════════════════════════════════════════════
--  服务端：RPC 处理器
-- ════════════════════════════════════════════════════════════
AddModRPCHandler("Mordomo", "Command", function(player, payload)
    if not player or not payload then return end
    MordomoCommands.HandleCommand(player, payload)
end)

-- ════════════════════════════════════════════════════════════
--  服务端：自动生成 Warly（auto 模式）
-- ════════════════════════════════════════════════════════════
local function FindExistingWarly()
    for _, e in pairs(Ents) do
        if e:IsValid() and e.prefab == "mordomo_warly" then
            return e
        end
    end
    return nil
end

local function SpawnWarlyNear(target)
    if not target or not target:IsValid() then return nil end
    local x, _, z = target.Transform:GetWorldPosition()
    -- 尝试在玩家附近找可通行点
    local spawn_x, spawn_z = x + 2, z + 2
    local map = TheWorld.Map
    if map and not map:IsPassableAtPoint(spawn_x, 0, spawn_z) then
        spawn_x, spawn_z = x - 2, z - 2
    end
    local warly = SpawnPrefab("mordomo_warly")
    if not warly then return nil end
    warly.Transform:SetPosition(spawn_x, 0, spawn_z)
    warly._owner_userid = target.userid
    if warly.owner_userid then
        warly.owner_userid:set(target.userid or "")
    end
    if warly.components.knownlocations then
        warly.components.knownlocations:RememberLocation("home", Vector3(spawn_x, 0, spawn_z))
    end
    if DEBUG_MODE then
        print("[Mordomo] Warly spawned near", target.name or target.userid)
    end
    return warly
end

AddPrefabPostInit("world", function(inst)
    if not TheWorld.ismastersim then return end
    inst:DoTaskInTime(5, function()
        if SPAWN_MODE ~= "auto" then return end
        if FindExistingWarly() then return end
        -- 优先找主机玩家
        local target = nil
        for _, p in pairs(AllPlayers) do
            if p and p:IsValid() then
                target = p
                break
            end
        end
        if target then
            SpawnWarlyNear(target)
        else
            -- 暂无玩家，监听下次有玩家加入
            inst:ListenForEvent("ms_playerspawn", function(world, data)
                if not FindExistingWarly() and data and data.player then
                    SpawnWarlyNear(data.player)
                end
            end)
        end
    end)
end)

-- ════════════════════════════════════════════════════════════
--  客户端：热键打开命令菜单
-- ════════════════════════════════════════════════════════════
-- modimport 共享 modenv：menu 文件中的 MordomoMenu 成为 modenv 全局
modimport("scripts/screens/mordomo_menu.lua")

local KEY_MAP = {
    M = GLOBAL.KEY_M, N = GLOBAL.KEY_N, B = GLOBAL.KEY_B,
    V = GLOBAL.KEY_V, J = GLOBAL.KEY_J, K = GLOBAL.KEY_K,
}
local HOTKEY = KEY_MAP[HOTKEY_STR] or GLOBAL.KEY_M

AddPlayerPostInit(function(inst)
    -- 仅本地玩家注册热键
    if inst ~= ThePlayer then return end
    if inst._mordomo_hotkey_added then return end
    inst._mordomo_hotkey_added = true
    inst:DoTaskInTime(1, function()
        if not TheInput then return end
        TheInput:AddKeyUpHandler(HOTKEY, function()
            -- 避免在非游戏界面（如选人、暂停）打开
            local active = TheFrontEnd:GetActiveScreen()
            if not active then return end
            local name = active.name or ""
            -- 仅在主游戏界面打开
            if name ~= "HUD" and not name:find("HUD") then return end
            -- 避免重复打开
            if name:find("MordomoMenu") then return end
            if MordomoMenu then
                TheFrontEnd:PushScreen(MordomoMenu(inst))
            end
        end)
    end)
end)

-- ════════════════════════════════════════════════════════════
--  控制台命令（手动模式备用）
-- ════════════════════════════════════════════════════════════
if GLOBAL and GLOBAL.rawset then
    -- c_spawn_warly() ：在本地玩家旁生成 Warly
    GLOBAL.rawset(GLOBAL, "c_spawn_warly", function()
        if not TheWorld.ismastersim then
            print("[Mordomo] c_spawn_warly 只能在服务端使用")
            return
        end
        local target = ThePlayer or nil
        if not target then
            for _, p in pairs(AllPlayers) do
                if p and p:IsValid() then target = p break end
            end
        end
        if target then
            SpawnWarlyNear(target)
        else
            print("[Mordomo] 未找到玩家")
        end
    end)

    -- c_mordomo_despawn() ：移除所有 Warly
    GLOBAL.rawset(GLOBAL, "c_mordomo_despawn", function()
        if not TheWorld.ismastersim then return end
        local count = 0
        for _, e in pairs(Ents) do
            if e:IsValid() and e.prefab == "mordomo_warly" then
                e:Remove()
                count = count + 1
            end
        end
        print(string.format("[Mordomo] Removed %d Warly NPC(s)", count))
    end)
end

if DEBUG_MODE then
    print("[Mordomo] modmain loaded — spawn_mode=" .. tostring(SPAWN_MODE)
        .. " hotkey=" .. tostring(HOTKEY_STR)
        .. " cook_range=" .. tostring(COOK_RANGE)
        .. " cook_speed=" .. tostring(COOK_SPEED))
end
