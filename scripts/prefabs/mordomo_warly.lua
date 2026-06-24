-- scripts/prefabs/mordomo_warly.lua
-- Mordomo-Mod Warly NPC 预制件（仅厨师，无战斗/武器装备）
-- ────────────────────────────────────────────────────────────
-- 与原 NPCFriends 的 npcfriend 不同：
--   · 不创建任何厨房建筑（cookpot/icebox/chest），完全依赖玩家世界已有的锅与冰箱
--   · 不装备武器、不战斗（combat 组件保留最低限度仅用于受击反馈）
--   · 熟食存入最近的冰箱（freezer 优先），修复“只存自家冰箱/乱存箱子”的 Bug
--   · 仅暴露 Follow / CookHere / Stop 命令
--
-- 动画使用 DST 内置：bank "wilson" + build "warly"（无需额外 anim 资源）。

local TUNING = require("mordomo/tuning")
local Speech = require("mordomo/speech")
local brain  = require("brains/mordomo_warly_brain")

local assets = {
    Asset("ANIM", "anim/wilson.zip"),       -- 玩家标准动画库（内置）
    Asset("ANIM", "anim/warly.zip"),        -- Warly 角色外观（内置）
}

local prefabs = {}

-- ════════════════════════════════════════════════════════════
--  物理与移动
-- ════════════════════════════════════════════════════════════

local function MakePhysics(inst)
    -- 角色型物理：可碰撞、可被点选
    inst.entity:AddPhysics()
    inst.Physics:SetMass(150)
    inst.Physics:SetFriction(10)
    inst.Physics:SetDamping(5)
    inst.Physics:SetCollisionGroup(COLLISION.CHARACTERS)
    inst.Physics:ClearCollisionMask()
    inst.Physics:CollidesWith(COLLISION.WORLD)
    inst.Physics:CollidesWith(COLLISION.OBSTACLES)
    inst.Physics:CollidesWith(COLLISION.SMALLOBSTACLES)
    inst.Physics:CollidesWith(COLLISION.CHARACTERS)
    inst.Physics:CollidesWith(COLLISION.GIANTS)
    inst.Physics:SetCapsule(0.5, 1.5)
end

local function SetupLocomotor(inst)
    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = TUNING.RUN_SPEED
    inst.components.locomotor.runspeed  = TUNING.RUN_SPEED
    -- 允许在非海洋地面行走
    inst.components.locomotor.pathcaps = { ignorewalls = false, allowocean = false }
end

-- ════════════════════════════════════════════════════════════
--  组件装配
-- ════════════════════════════════════════════════════════════

local function SetupComponents(inst)
    -- 健康
    inst:AddComponent("health")
    local stats = TUNING.CHARACTER_STATS.warly
    inst.components.health:SetMaxHealth(stats.max_health or 150)
    inst.components.health.fire_damage_scale = 0.5
    inst.components.health.canheal = false

    -- 战斗（最低限度：仅受击反馈，不主动攻击）
    inst:AddComponent("combat")
    inst.components.combat.hiteffectsymbol = "torso"
    inst.components.combat.canbeattacked = true
    inst.components.combat:SetDefaultDamage(0) -- 不造成伤害
    inst.components.combat:SetAttackPeriod(0)
    inst.components.combat:SetRetargetFunction(0, function() return nil end) -- 不主动找敌
    inst.components.combat:SetKeepTargetFunction(function() return false end) -- 不保持目标

    -- 背包（厨师背包，16 格）
    inst:AddComponent("inventory")
    inst.components.inventory.maxslots = stats.inventory_slots or 16

    -- 跟随者
    inst:AddComponent("follower")
    inst.components.follower:KeepLeaderOnAttacked()
    inst.components.follower.keepdeadleader = true

    -- 说话
    inst:AddComponent("talker")
    inst.components.talker.colour = Vector3(0.9, 0.8, 0.5)

    -- 已知位置（home / 烹饪中心记忆）
    inst:AddComponent("knownlocations")

    -- 可检查
    inst:AddComponent("inspectable")

    -- 可命名（悬浮信息）
    inst:AddComponent("named")
    inst.components.named:SetName("Warly")
end

-- ════════════════════════════════════════════════════════════
--  标签 / 身份
-- ════════════════════════════════════════════════════════════

local function SetupIdentity(inst)
    inst.npc_character_type = "warly"
    inst._is_warly = true

    -- 核心身份标签
    inst:AddTag("mordomo_npc")     -- 本 Mod 识别标签
    inst:AddTag("npcfriend")       -- 兼容原 mod 通用交互（喂食等）
    inst:AddTag("companion")
    inst:AddTag("character")
    inst:AddTag("notraptrigger")

    -- 厨师专属标签（解锁专属食谱 + 加速）
    inst:AddTag("masterchef")
    inst:AddTag("expertchef")

    -- 不被某些系统干扰
    inst:AddTag("scarytoprey")
    inst:AddTag("notscary")   -- 不惊吓其他玩家

    -- 网络可见的 owner userid（用于命令权限校验）；在 SetPristine 前创建以同步
    inst.owner_userid = net_string(inst.GUID, "mordomo_warly.owner_userid", "owner_dirty")
end

-- ════════════════════════════════════════════════════════════
--  存档 / 读档
-- ════════════════════════════════════════════════════════════

local function OnSave(inst, data)
    data.cooking_center = inst._cooking_center or nil
    data.owner_userid   = inst._owner_userid or nil
    data.work_paused    = inst._work_paused or nil
    local hx, _, hz = inst.Transform:GetWorldPosition()
    data.x, data.z = hx, hz
end

local function OnLoad(inst, data)
    if not data then return end
    if data.cooking_center then
        inst._cooking_center = { x = data.cooking_center.x, z = data.cooking_center.z }
    end
    if data.owner_userid then
        inst._owner_userid = data.owner_userid
        if inst.owner_userid then
            inst.owner_userid:set(data.owner_userid)
        end
    end
    inst._work_paused = data.work_paused or nil
    if data.x and data.z then
        inst.Transform:SetPosition(data.x, 0, data.z)
    end
    -- 恢复 home
    if inst.components.knownlocations and data.x and data.z then
        inst.components.knownlocations:RememberLocation("home", Vector3(data.x, 0, data.z))
    end
end

-- ════════════════════════════════════════════════════════════
--  主构造函数
-- ════════════════════════════════════════════════════════════

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    -- 动画：标准玩家库 + Warly 外观
    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("warly")
    inst.AnimState:PlayAnimation("idle_loop", true)

    MakePhysics(inst)
    SetupIdentity(inst)

    -- 联机：服务端权威，客户端仅渲染
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        return inst
    end

    SetupComponents(inst)
    SetupLocomotor(inst)

    inst:SetBrain(brain)
    inst:SetStateGraph("SGmordomo_warly")

    -- 首次进入世界：记住出生点为 home
    inst:DoTaskInTime(0.5, function()
        if inst:IsValid() and inst.components.knownlocations then
            local x, _, z = inst.Transform:GetWorldPosition()
            inst.components.knownlocations:RememberLocation("home", Vector3(x, 0, z))
        end
    end)

    inst.OnSave   = OnSave
    inst.OnLoad   = OnLoad

    return inst
end

return Prefab("mordomo_warly", fn, assets, prefabs)
