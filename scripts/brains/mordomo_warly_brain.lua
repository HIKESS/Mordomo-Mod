-- scripts/brains/mordomo_warly_brain.lua
-- Mordomo-Mod Warly 厨师大脑（精简版，仅烹饪 + 跟随 + 闲逛，无战斗）
-- ────────────────────────────────────────────────────────────
-- 采用 DoPeriodicTask 驱动的有限状态机，避免 BehaviourTree 语义复杂度。
-- 每个 tick（0.25s）按优先级决策：
--   1) 死亡/幽灵/忙碌 → 跳过
--   2) 着火 → 短暂乱跑（仅保命，不战斗）
--   3) 烹饪模式（_cooking_center 且未暂停）→ 烹饪状态机
--   4) 跟随 → 跟随 leader
--   5) 闲逛 → 在 home 附近随机走动
--
-- 烹饪状态机（阶段存储于 inst._cook_plan / inst._cook_wait_pot）：
--   - 无计划、无等待 → 用 CookingPlanner 规划
--   - 有计划、取材路线非空 → 走到下一个容器并取食材（pickup 状态）
--   - 有计划、取材完毕 → 走到锅前开始烹饪（cookaction 状态）→ 进入等待
--   - 等待中：锅 done → 收菜 → 存入最近冰箱（freezer 优先）→ 清空，回到规划

local TUNING          = require("mordomo/tuning")
local Speech          = require("mordomo/speech")
local Storage         = require("mordomo/storage")
local StructureUtil   = require("mordomo/structure_util")

local CookingPlanner  = require("mordomo/cooking_planner")

local Brain = require("brains/brain")
local MordomoWarlyBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

-- ════════════════════════════════════════════════════════════
--  辅助函数
-- ════════════════════════════════════════════════════════════

local function GetPos(ent)
    if not ent or not ent:IsValid() then return nil end
    local x, _, z = ent.Transform:GetWorldPosition()
    return { x = x, z = z }
end

local function DistSq(a, b)
    if not a or not b then return math.huge end
    local dx, dz = a.x - b.x, a.z - b.z
    return dx * dx + dz * dz
end

local function DistSqEnt(ent, pos)
    return DistSq(GetPos(ent), pos)
end

local function SayLine(inst, scene)
    if not inst or not inst.components.talker then return end
    local line = Speech.GetLine(scene, inst.npc_character_type)
    if line then
        inst.components.talker:ShutUp()
        inst.components.talker:Say(line)
    end
end

--- 在烹饪中心附近查找所有烹饪锅与容器（冰箱+箱子）
local function FindPotsAndContainers(center)
    local pots = {}
    local containers = {}
    if not center then return pots, containers end
    local radius = TUNING.COOK_RANGE_DEFAULT or 17

    -- 烹饪锅（含 portablecookpot / cookpot）：通过 stewer 标签
    local pot_ents = TheSim:FindEntities(center.x, 0, center.z, radius, { "stewer" })
    for _, e in ipairs(pot_ents) do
        if e:IsValid() and e.components.stewer and e.components.container then
            table.insert(pots, e)
        end
    end

    -- 冰箱（freezer 优先）
    local iceboxes = StructureUtil.FindNearbyIceboxes(center, nil, radius)
    for _, e in ipairs(iceboxes) do
        table.insert(containers, e)
    end
    -- 箱子（退而求其次的食材来源）
    local chests = StructureUtil.FindNearbyChests(center, nil, radius)
    for _, e in ipairs(chests) do
        table.insert(containers, e)
    end

    return pots, containers
end

--- 从容器指定槽位取出物品到 Warly 背包（支持堆叠拆分）
local function TakeItemFromContainer(inst, container, slot, prefab, take_count)
    if not container or not container:IsValid() then return false end
    local cont = container.components.container
    if not cont then return false end
    local item = cont:GetItemInSlot(slot)
    if not item or not item:IsValid() then return false end
    if item.prefab ~= prefab then return false end

    local inv = inst.components.inventory
    if not inv then return false end

    local to_take = take_count or 1
    if item.components.stackable then
        local stack_size = item.components.stackable:StackSize()
        if stack_size > to_take then
            -- 拆栈
            local new_stack = item.components.stackable:Get(to_take)
            if new_stack then
                inv:GiveItem(new_stack)
                return true
            end
            return false
        end
    end
    -- 整个取走
    cont:RemoveItem(item, false)
    inv:GiveItem(item)
    return true
end

--- 把背包里的 4 个食材装入烹饪锅并开始烹饪
local function LoadPotAndStartCooking(inst, pot)
    if not pot or not pot:IsValid() or not pot.components.stewer then return false end
    local inv = inst.components.inventory
    if not inv then return false end

    -- 收集背包中的食材（取前 4 个非成品料理）
    local ingredients = {}
    for i = 1, inv.maxslots do
        local item = inv:GetItemInSlot(i)
        if item and item:IsValid() then
            -- 排除成品料理（带 preparedfood 标签）
            if not item:HasTag("preparedfood") then
                table.insert(ingredients, item)
                if #ingredients >= 4 then break end
            end
        end
    end

    if #ingredients < 4 then return false end

    -- 装入锅的容器
    local pot_cont = pot.components.container
    if not pot_cont then return false end

    -- 先清空锅里残留（若有未烹饪食材）
    -- （正常情况下锅应是空的，这里安全起见跳过）

    for _, item in ipairs(ingredients) do
        inv:RemoveItem(item, false)
        pot_cont:GiveItem(item)
    end

    -- 设置 Warly 厨师为烹饪者，加速生效
    local stats = TUNING.CHARACTER_STATS and TUNING.CHARACTER_STATS.warly
    if stats and stats.cook_time_mult and pot.components.stewer then
        pot.components.stewer.cooktimemult = stats.cook_time_mult
    end

    -- 开始烹饪
    pot.components.stewer:StartCooking(inst)
    return true
end

--- 收取锅里成品
local function HarvestPot(inst, pot)
    if not pot or not pot:IsValid() or not pot.components.stewer then return false end
    -- stewer:Harvest 把成品交给 harvester 的背包
    pot.components.stewer:Harvest(inst)
    return true
end

-- ════════════════════════════════════════════════════════════
--  烹饪状态机
-- ════════════════════════════════════════════════════════════

local function TickCooking(self)
    local inst = self.inst
    local center = inst._cooking_center
    if not center then return end

    -- 1) 等待锅完成
    if inst._cook_wait_pot and inst._cook_wait_pot:IsValid() then
        local pot = inst._cook_wait_pot
        local stewer = pot.components.stewer
        if not stewer then
            inst._cook_wait_pot = nil
            return
        end
        if stewer:IsDone() then
            -- 收菜 → 存冰箱 → 清等待
            if inst.sg and not inst.sg:HasStateTag("busy") then
                inst._do_cook_fn = function()
                    HarvestPot(inst, pot)
                    Storage.StoreAllCookedFood(inst, center)
                    SayLine(inst, Speech.COOKING_DONE)
                end
                inst.sg:GoToState("cookaction")
                inst._cook_wait_pot = nil   -- 已发起收菜，清等待（忙碌时保留下次重试）
            end
        elseif stewer:IsCooking() then
            -- 等待：站在锅旁
            if inst.sg and not inst.sg:HasStateTag("busy") then
                local pot_pos = GetPos(pot)
                local my_pos = GetPos(inst)
                if DistSq(pot_pos, my_pos) > (TUNING.COOK_APPROACH_DIST + 1) ^ 2 then
                    inst.components.locomotor:GoToEntity(pot)
                else
                    inst.components.locomotor:Stop()
                end
            end
        else
            -- 锅被清空/异常
            inst._cook_wait_pot = nil
        end
        return
    end

    -- 2) 执行现有计划
    if inst._cook_plan then
        local plan = inst._cook_plan
        local pot = plan.cookpot
        if not pot or not pot:IsValid() or not pot.components.stewer then
            inst._cook_plan = nil
            return
        end

        local route = plan.pickup_route
        if route and #route > 0 then
            -- 还有取材步骤
            local step = route[1]
            if not step.container or not step.container:IsValid() then
                table.remove(route, 1)
                return
            end
            if inst.sg and not inst.sg:HasStateTag("busy") then
                local cont_pos = GetPos(step.container)
                local my_pos = GetPos(inst)
                if DistSq(cont_pos, my_pos) <= TUNING.COOK_APPROACH_DIST ^ 2 then
                    -- 到位：执行取物动画 + 实际取物
                    inst._do_pickup_fn = function()
                        for _, it in ipairs(step.items) do
                            TakeItemFromContainer(inst, step.container, it.slot, it.prefab, it.take_count)
                        end
                    end
                    inst.sg:GoToState("pickup")
                    table.remove(route, 1)
                else
                    inst.components.locomotor:GoToEntity(step.container)
                end
            end
            return
        end

        -- 取材完毕：去锅前烹饪
        if inst.sg and not inst.sg:HasStateTag("busy") then
            local pot_pos = GetPos(pot)
            local my_pos = GetPos(inst)
            if DistSq(pot_pos, my_pos) <= TUNING.COOK_APPROACH_DIST ^ 2 then
                -- 到位：执行烹饪动画 + 装锅开煮
                inst._do_cook_fn = function()
                    if LoadPotAndStartCooking(inst, pot) then
                        inst._cook_wait_pot = pot
                        SayLine(inst, Speech.COOKING_START)
                    end
                end
                inst.sg:GoToState("cookaction")
                inst._cook_plan = nil
            else
                inst.components.locomotor:GoToEntity(pot)
            end
        end
        return
    end

    -- 3) 无计划：规划一次
    local pots, containers = FindPotsAndContainers(center)
    if #pots == 0 then
        -- 没锅，偶尔提示
        if not inst._no_pot_warn_until or GetTime() > inst._no_pot_warn_until then
            inst._no_pot_warn_until = GetTime() + 15
            SayLine(inst, Speech.NO_COOKPOT)
        end
        return
    end

    local plan = CookingPlanner.PlanCooking(inst, containers, pots, true)
    if plan then
        inst._cook_plan = plan
    else
        -- 无可用食谱/食材，偶尔提示
        if not inst._no_ing_warn_until or GetTime() > inst._no_ing_warn_until then
            inst._no_ing_warn_until = GetTime() + 20
            SayLine(inst, Speech.NO_INGREDIENTS)
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  跟随
-- ════════════════════════════════════════════════════════════

local function TickFollow(self, leader)
    local inst = self.inst
    if not leader or not leader:IsValid() then return end
    if inst.sg and inst.sg:HasStateTag("busy") then return end

    local my_pos = GetPos(inst)
    local leader_pos = GetPos(leader)
    local dsq = DistSq(my_pos, leader_pos)
    local target = TUNING.FOLLOW_TARGET_DIST or 3
    local leash = TUNING.FOLLOW_LEASH_DIST or 12

    if dsq > target * target then
        inst.components.locomotor:GoToEntity(leader)
    else
        inst.components.locomotor:Stop()
    end
end

-- ════════════════════════════════════════════════════════════
--  闲逛
-- ════════════════════════════════════════════════════════════

local function TickIdle(self)
    local inst = self.inst
    if inst.sg and inst.sg:HasStateTag("busy") then return end
    if inst._next_wander and GetTime() < inst._next_wander then
        inst.components.locomotor:Stop()
        return
    end
    inst._next_wander = GetTime() + 4 + math.random() * 4

    local home
    if inst.components.knownlocations then
        home = inst.components.knownlocations:GetLocation("home")
    end
    local my_pos = GetPos(inst) or { x = 0, z = 0 }
    local base = home or my_pos

    local angle = math.random() * TWOPI
    local r = math.random() * 4
    local tx, tz = base.x + math.cos(angle) * r, base.z + math.sin(angle) * r
    inst.components.locomotor:GoToPoint(Vector3(tx, 0, tz))
end

-- ════════════════════════════════════════════════════════════
--  主 Tick
-- ════════════════════════════════════════════════════════════

local function Tick(self)
    local inst = self.inst
    if not inst or not inst:IsValid() then return end

    -- 防御性：单个 tick 内任何错误都不应击溃整个大脑
    local ok, err = pcall(function()
        -- 死亡 / 幽灵 → 不行动
        if inst._is_ghost_mode then return end
        if inst.components.health and inst.components.health:IsDead() then return end

        -- 着火：保命乱跑（不战斗）
        if inst.components.health and inst.components.health.fire_damage
           and inst.components.health.fire_damage > 0 then
            if inst.sg and not inst.sg:HasStateTag("busy") then
                local x, _, z = inst.Transform:GetWorldPosition()
                local angle = math.random() * TWOPI
                inst.components.locomotor:RunInDirection(angle)
            end
            return
        end

        -- 烹饪模式
        if inst._cooking_center and not inst._work_paused then
            TickCooking(self)
            return
        end

        -- 跟随
        local leader = inst.components.follower and inst.components.follower.leader
        if leader and leader:IsValid() then
            TickFollow(self, leader)
            return
        end

        -- 闲逛
        TickIdle(self)
    end)

    if not ok and TUNING.DEBUG_BEHAVIOR then
        print("[Mordomo][Brain] tick error:", err)
    end
end

-- ════════════════════════════════════════════════════════════
--  Brain 生命周期
-- ════════════════════════════════════════════════════════════

function MordomoWarlyBrain:OnStart()
    local period = 0.25
    self._task = self.inst:DoPeriodicTask(period, function()
        Tick(self)
    end)
end

function MordomoWarlyBrain:OnStop()
    if self._task then
        self._task:Cancel()
        self._task = nil
    end
end

return MordomoWarlyBrain
