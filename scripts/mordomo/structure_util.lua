-- scripts/npc/npc_structure_util.lua
-- NPC 结构管理公共工具
-- 提供结构保护、位置校验、实体查找等通用功能，供多角色/行为共享
-- ────────────────────────────────────────────────────────────

local StructureUtil = {}

local NPC_TUNING = require("mordomo/tuning")
local DEBUG_BEHAVIOR = NPC_TUNING.DEBUG_BEHAVIOR

-- ════════════════════════════════════════════════════════════
--  结构保护
-- ════════════════════════════════════════════════════════════

--- 完全保护结构：不可敲/不可烧/不可拆/不可作祟
--- 适用于 NPC 建造的工作站（冰箱、箱子、烹饪锅等）
--- 存档加载后需重新调用（prefab 构造函数会恢复默认组件）
function StructureUtil.ProtectStructure(ent)
    if not ent or not ent:IsValid() then return end
    if ent.components.workable then ent:RemoveComponent("workable") end
    if ent.components.burnable then ent:RemoveComponent("burnable") end
    if ent.components.propagator then ent:RemoveComponent("propagator") end
    if ent.components.hauntable then ent:RemoveComponent("hauntable") end
    if ent.components.portablestructure then ent:RemoveComponent("portablestructure") end
    ent:AddTag("_npc_structure")
end

-- ════════════════════════════════════════════════════════════
--  位置校验
-- ════════════════════════════════════════════════════════════

--- 简单位置有效性检查（可通行 + 非海洋）
--- 用于建造前的快速校验
function StructureUtil.IsValidBuildPos(pos)
    local map = TheWorld.Map
    if not map then return false end
    if not map:IsPassableAtPoint(pos.x, 0, pos.z) then return false end
    if map:IsOceanAtPoint(pos.x, 0, pos.z) then return false end
    -- 检查附近是否有物理占位实体（排除角色、特效、地面可拾取物品）
    local nearby = TheSim:FindEntities(pos.x, 0, pos.z, 1.0)
    for _, e in ipairs(nearby) do
        if e:IsValid() and not e:IsInLimbo() and e.Physics
           and not (e:HasTag("player") or e:HasTag("npcfriend")
                    or e:HasTag("companion") or e:HasTag("FX")
                    or e:HasTag("NOCLICK") or e:HasTag("DECOR"))
           and not e.components.inventoryitem then
            return false
        end
    end
    return true
end

-- ════════════════════════════════════════════════════════════
--  实体搜索
-- ════════════════════════════════════════════════════════════

--- 在指定位置附近查找指定 prefab 的实体
--- @param pos        Vector3 搜索中心
--- @param prefab     string  目标 prefab 名称
--- @param radius     number  搜索半径（默认 1.5）
--- @param assigned   table?  已分配实体集合（防止同一实体被多个 key 引用）
--- @return entity|nil
function StructureUtil.FindAt(pos, prefab, radius, assigned)
    if not pos then return nil end
    radius = radius or 1.5
    local ents = TheSim:FindEntities(pos.x, 0, pos.z, radius)
    for _, e in ipairs(ents) do
        if e:IsValid() and e.prefab == prefab then
            if not assigned or not assigned[e] then
                if assigned then assigned[e] = true end
                return e
            end
        end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════
--  障碍物搜索
-- ════════════════════════════════════════════════════════════

--- 在一组位置附近搜索可清除的障碍物（树、草、灌木、树桩等）
--- @param positions   table   { key = Vector3, ... } 需要检查的位置集合
--- @param inst        entity  NPC 实体（用于计算最近距离）
--- @param clear_radius number 每个位置的搜索半径
--- @return entity|nil, string|nil  最近的障碍物 + 工作类型 ("chop"/"dig")
function StructureUtil.FindObstacleNearPositions(positions, inst, clear_radius)
    if not positions or not inst then return nil, nil end
    local ix, _, iz = inst.Transform:GetWorldPosition()
    local best, best_dsq, best_action = nil, math.huge, nil
    for _, pos in pairs(positions) do
        local ents = TheSim:FindEntities(pos.x, 0, pos.z, clear_radius,
                                         nil,
                                         {"_npc_structure", "farm_plant", "weed", "farm_debris"},
                                         {"CHOP_workable", "DIG_workable"})
        for _, e in ipairs(ents) do
            if e:IsValid() and not e:IsInLimbo()
               and e.components.workable and e.components.workable:CanBeWorked() then
                local ex, _, ez = e.Transform:GetWorldPosition()
                local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
                if dsq < best_dsq then
                    best = e
                    best_dsq = dsq
                    best_action = e:HasTag("CHOP_workable") and "chop" or "dig"
                end
            end
        end
    end
    return best, best_action
end

-- ════════════════════════════════════════════════════════════
--  地面物品搜索
-- ════════════════════════════════════════════════════════════

local function IsStorageRobot(ent)
    return ent ~= nil
        and (ent:HasTag("storagerobot") or ent.prefab == "winona_storage_robot")
end

local function IsPickupableGroundItem(e)
    if e == nil or not e:IsValid() then return false end
    if IsStorageRobot(e) then return false end
    if e:HasTag("NOCLICK") then return false end
    if e.components == nil or e.components.inventoryitem == nil then return false end
    if e.components.inventoryitem.canbepickedup == false then return false end
    local owner = e.components.inventoryitem.owner
    if owner ~= nil and owner:IsValid() and IsStorageRobot(owner) then return false end
    if e.highlightparent ~= nil and e.highlightparent:IsValid() and IsStorageRobot(e.highlightparent) then return false end
    return true
end

--- 在一组位置附近搜索地面掉落物品（种子、蔬菜、材料等）
--- 排除：NPC 结构 / NPC 工具 / INLIMBO / NOCLICK / 不可拾取物 / 活体生物 / 农场原生实体 / 水面物品
--- @param positions   table   { key = Vector3, ... } 需要检查的位置集合
--- @param inst        entity  NPC 实体（用于计算最近距离）
--- @param clear_radius number 每个位置的搜索半径
--- @return entity|nil  最近的地面物品
function StructureUtil.FindGroundItemNearPositions(positions, inst, clear_radius)
    if not positions or not inst then return nil end
    local ix, _, iz = inst.Transform:GetWorldPosition()
    local best, best_dsq = nil, math.huge
    for _, pos in pairs(positions) do
        local ents = TheSim:FindEntities(pos.x, 0, pos.z, clear_radius,
                                         {"_inventoryitem"},
                                         {"INLIMBO", "NOCLICK", "_npc_structure", "_npc_tool"})
        for _, e in ipairs(ents) do
            if IsPickupableGroundItem(e)
               and not e.components.locomotor    -- 排除活体生物
               and not e:HasTag("soil")          -- 排除农场土壤
               and not e:HasTag("farm_plant")    -- 排除农作物
               and not e:HasTag("weed")          -- 排除杂草
               and not e:HasTag("farm_debris")   -- 排除农场碎片
               then
                local ex, _, ez = e.Transform:GetWorldPosition()
                -- 平台过滤：排除船上的物品（NPC 无法到达）
                -- 注意：不能用 IsOceanAtPoint，因为 DST 中 allow_boats 默认为 false，
                -- 船甲板上 IsOceanAtPoint 返回 false，导致船上物品无法被正确过滤
                if TheWorld.Map:IsPassableAtPoint(ex, 0, ez)
                   and e:GetCurrentPlatform() == nil then
                    local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
                    if dsq < best_dsq then
                        best = e
                        best_dsq = dsq
                    end
                end
            end
        end
    end
    return best
end

-- ════════════════════════════════════════════════════════════
--  中心点半径搜索（单点圆形范围，适用于工作站周边巡逻）
-- ════════════════════════════════════════════════════════════

--- 以单个中心点为圆心搜索可清除的障碍物（树、草、灌木、树桩等）
--- @param center    table   { x, z } 或 Vector3 搜索中心
--- @param inst      entity  NPC 实体
--- @param radius    number  搜索半径
--- @return entity|nil, string|nil  最近的障碍物 + 工作类型 ("chop"/"dig")
function StructureUtil.FindObstacleInRadius(center, inst, radius)
    if not center or not inst then return nil, nil end
    local ix, _, iz = inst.Transform:GetWorldPosition()
    local best, best_dsq, best_action = nil, math.huge, nil
    local ents = TheSim:FindEntities(center.x, 0, center.z, radius,
                                     nil,
                                     {"_npc_structure", "farm_plant", "weed", "farm_debris"},
                                     {"CHOP_workable", "DIG_workable"})
    for _, e in ipairs(ents) do
        if e:IsValid() and not e:IsInLimbo()
           and e.components.workable and e.components.workable:CanBeWorked() then
            local ex, _, ez = e.Transform:GetWorldPosition()
            local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
            if dsq < best_dsq then
                best = e
                best_dsq = dsq
                best_action = e:HasTag("CHOP_workable") and "chop" or "dig"
            end
        end
    end
    return best, best_action
end

--- 以单个中心点为圆心搜索地面掉落物品
--- @param center    table   { x, z } 或 Vector3 搜索中心
--- @param inst      entity  NPC 实体
--- @param radius    number  搜索半径
--- @return entity|nil  最近的地面物品
--- @param filter_fn (可选) function(entity, inst) → true 表示跳过该物品
function StructureUtil.FindGroundItemInRadius(center, inst, radius, filter_fn)
    if not center or not inst then return nil end
    local ix, _, iz = inst.Transform:GetWorldPosition()
    local best, best_dsq = nil, math.huge
    local ents = TheSim:FindEntities(center.x, 0, center.z, radius,
                                     {"_inventoryitem"},
                                     {"INLIMBO", "NOCLICK", "_npc_structure", "_npc_tool"})
    if DEBUG_BEHAVIOR then
        print("[NPC_DEBUG] FindGroundItemInRadius - center:", string.format("(%.1f, %.1f)", center.x, center.z),
              "radius:", radius, "raw_count:", #ents)
    end
    for _, e in ipairs(ents) do
        if IsPickupableGroundItem(e)
           and not e.components.locomotor
           and not e:HasTag("heavy")
           and not e:HasTag("soil")
           and not e:HasTag("farm_plant")
           and not e:HasTag("weed")
           and not e:HasTag("farm_debris")
           then
            local filtered = (filter_fn and filter_fn(e, inst))
            if DEBUG_BEHAVIOR then
                print("[NPC_DEBUG] FindGroundItemInRadius - entity:", e.prefab or "?",
                      "backpack=", tostring(e:HasTag("backpack")),
                      "_inventoryitem=", tostring(e:HasTag("_inventoryitem")),
                      "canbepickedup=", tostring(e.components.inventoryitem and e.components.inventoryitem.canbepickedup),
                      "container=", tostring(e.components.container ~= nil),
                      "chest=", tostring(e:HasTag("chest")),
                      "fridge=", tostring(e:HasTag("fridge")),
                      "filtered=", tostring(filtered or false))
            end
            if not filtered then
                local ex, _, ez = e.Transform:GetWorldPosition()
                if TheWorld.Map:IsPassableAtPoint(ex, 0, ez)
                   and e:GetCurrentPlatform() == nil
                   and TheWorld.Pathfinder:IsClear(
                       ix, 0, iz, ex, 0, ez,
                       { ignorewalls = true, ignorecreep = true, allowocean = false })
                   then
                    local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
                    if dsq < best_dsq then
                        best = e
                        best_dsq = dsq
                    end
                end
            end
        end
    end
    if DEBUG_BEHAVIOR then
        print("[NPC_DEBUG] FindGroundItemInRadius - result:", best and (best.prefab or "?") or "nil")
    end
    return best
end

-- ════════════════════════════════════════════════════════════
--  巨大作物搜索
-- ════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════
--  周边容器搜索（世界中玩家放置的冰箱/箱子）
-- ════════════════════════════════════════════════════════════

--- 在指定位置附近搜索可用的冰箱（含 "fridge" 标签 + container 组件）
--- 排除 NPC 建造的结构（已由工作站跟踪），排除已在 exclude_set 中的实体
--- @param center    table    { x, z } 或 Vector3 搜索中心
--- @param inst      entity   NPC 实体
--- @param radius    number   搜索半径
--- @param exclude_set table|nil  {[entity]=true} 已跟踪的容器（可选）
--- @return table 冰箱实体列表
function StructureUtil.FindNearbyIceboxes(center, inst, radius, exclude_set)
    if not center then return {} end
    local result = {}
    local ents = TheSim:FindEntities(center.x, 0, center.z, radius, {"fridge"})
    for _, e in ipairs(ents) do
        if e:IsValid() and not e:IsInLimbo()
           and e.components.container
           and not e:HasTag("_npc_structure")
           and not e:HasTag("backpack")
           and not (exclude_set and exclude_set[e]) then
            table.insert(result, e)
        end
    end
    if DEBUG_BEHAVIOR then
        local strs = {}
        for _, c in ipairs(result) do table.insert(strs, (c.prefab or "?") .. "(" .. tostring(c) .. ")") end
        print("[NPC_DEBUG] FindNearbyIceboxes - found:", #result, "[", table.concat(strs, ", "), "]")
    end
    return result
end

--- 在指定位置附近搜索可用的箱子（使用 "chest" 标签，兼容所有箱子类型含 mod 箱子）
--- 排除 NPC 建造的结构，排除冰箱类容器，排除已在 exclude_set 中的实体
--- @param center    table    { x, z } 或 Vector3 搜索中心
--- @param inst      entity   NPC 实体
--- @param radius    number   搜索半径
--- @param exclude_set table|nil  {[entity]=true} 已跟踪的容器（可选）
--- @return table 箱子实体列表
function StructureUtil.FindNearbyChests(center, inst, radius, exclude_set)
    if not center then return {} end
    local result = {}
    local ents = TheSim:FindEntities(center.x, 0, center.z, radius, {"chest"})
    for _, e in ipairs(ents) do
        if e:IsValid() and not e:IsInLimbo()
           and e.components.container
           and not e:HasTag("_npc_structure")
           and not e:HasTag("fridge")
           and not e:HasTag("stewer")
           and not (exclude_set and exclude_set[e]) then
            table.insert(result, e)
        end
    end
    if DEBUG_BEHAVIOR then
        local strs = {}
        for _, c in ipairs(result) do table.insert(strs, (c.prefab or "?") .. "(" .. tostring(c) .. ")") end
        print("[NPC_DEBUG] FindNearbyChests - found:", #result, "[", table.concat(strs, ", "), "]")
    end
    return result
end

-- ════════════════════════════════════════════════════════════
--  巨大作物搜索
-- ════════════════════════════════════════════════════════════

--- 以中心点为圆心搜索附近的巨大作物（oversized_veggie）
--- 返回距离 NPC 最近的一个可敲击的巨大作物
--- @param center    table   { x, z } 或 Vector3 搜索中心
--- @param inst      entity  NPC 实体
--- @param radius    number  搜索半径
--- @return entity|nil  最近的可敲击巨大作物
function StructureUtil.FindOversizedCrop(center, inst, radius)
    if not center or not inst then return nil end
    local ix, _, iz = inst.Transform:GetWorldPosition()
    local best, best_dsq = nil, math.huge
    local ents = TheSim:FindEntities(center.x, 0, center.z, radius, {"oversized_veggie"})
    for _, e in ipairs(ents) do
        if e:IsValid() and not e:IsInLimbo()
           and e.components.workable and e.components.workable:CanBeWorked() then
            local ex, _, ez = e.Transform:GetWorldPosition()
            -- 平台过滤：排除船上的物品（NPC 无法到达）
            -- 注意：不能用 IsOceanAtPoint，因为 DST 中 allow_boats 默认为 false，
            -- 船甲板上 IsOceanAtPoint 返回 false，导致船上物品无法被正确过滤
            if TheWorld.Map:IsPassableAtPoint(ex, 0, ez)
               and e:GetCurrentPlatform() == nil then
                local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
                if dsq < best_dsq then
                    best = e
                    best_dsq = dsq
                end
            end
        end
    end
    return best
end

-- ════════════════════════════════════════════════════════════
--  农场中心搜索（从 wes.lua/winona.lua 提取）
-- ════════════════════════════════════════════════════════════

--- 搜索最近的农场中心（植物人 NPC 的 farm_center）
--- 遍历世界中所有 npcfriend 实体，找到拥有 farmer.farm_center 的 NPC，
--- 返回距离 inst 最近的农场中心点
--- @param inst         entity NPC 实体
--- @param searchRadius number 搜索半径（默认 200）
--- @return table|nil   { x, z } 农场中心坐标
function StructureUtil.FindNearestFarmCenter(inst, searchRadius)
    if not inst then return nil end
    local x, y, z = inst.Transform:GetWorldPosition()
    local range = searchRadius or 200
    local npcs = TheSim:FindEntities(x, y, z, range, {"npcfriend"})
    local best_center, best_dist = nil, math.huge
    for _, npc in ipairs(npcs) do
        if npc ~= inst and npc:IsValid()
           and npc._farmer and npc._farmer.farm_center then
            local fc = npc._farmer.farm_center
            local dx, dz = x - fc.x, z - fc.z
            local dsq = dx * dx + dz * dz
            if dsq < best_dist then
                best_dist = dsq
                best_center = fc
            end
        end
    end
    return best_center
end

-- ════════════════════════════════════════════════════════════
--  按类型搜索半径内容器（从 wes.lua/winona.lua 提取）
-- ════════════════════════════════════════════════════════════

--- 在指定中心点半径内搜索容器
--- @param center         table   { x, z } 或 Vector3 搜索中心
--- @param radius         number  搜索半径
--- @param container_type string|nil  "icebox"、"chest" 或 nil（全部）
--- @return table 容器实体列表
function StructureUtil.FindContainersInRadius(center, radius, container_type)
    if not center then return {} end
    local result = {}
    if container_type == "icebox" then
        local ents = TheSim:FindEntities(center.x, 0, center.z, radius, {"fridge"})
        for _, ent in ipairs(ents) do
            if ent:IsValid() and ent.components.container
               and not ent:HasTag("backpack") then
                table.insert(result, ent)
            end
        end
    elseif container_type == "chest" then
        local ents = TheSim:FindEntities(center.x, 0, center.z, radius, {"chest"})
        for _, ent in ipairs(ents) do
            if ent:IsValid() and ent.components.container
               and not ent:HasTag("fridge")
               and not ent:HasTag("cookpot")
               and not ent:HasTag("stewer") then
                table.insert(result, ent)
            end
        end
    else
        local iceboxes = TheSim:FindEntities(center.x, 0, center.z, radius, {"fridge"})
        for _, ent in ipairs(iceboxes) do
            if ent:IsValid() and ent.components.container
               and not ent:HasTag("backpack") then
                table.insert(result, ent)
            end
        end
        local chests = TheSim:FindEntities(center.x, 0, center.z, radius, {"chest"})
        for _, ent in ipairs(chests) do
            if ent:IsValid() and ent.components.container
               and not ent:HasTag("fridge")
               and not ent:HasTag("cookpot")
               and not ent:HasTag("stewer") then
                table.insert(result, ent)
            end
        end
    end
    if DEBUG_BEHAVIOR then
        local strs = {}
        for _, c in ipairs(result) do
            table.insert(strs, (c.prefab or "?") .. "(" .. tostring(c) .. ", chest=" .. tostring(c:HasTag("chest")) .. ", fridge=" .. tostring(c:HasTag("fridge")) .. ")")
        end
        print("[NPC_DEBUG] FindContainersInRadius - type:", container_type or "all",
              "found:", #result, "[", table.concat(strs, ", "), "]")
    end
    return result
end

return StructureUtil
