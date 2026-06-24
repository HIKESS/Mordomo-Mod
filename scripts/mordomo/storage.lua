-- scripts/mordomo/storage.lua
-- Mordomo-Mod 熟食存储模块 —— 修复“只存自家冰箱/乱存箱子”的 Bug
-- ────────────────────────────────────────────────────────────
-- 核心策略（用户要求的“最近的冰箱优先”标签方案）：
--   1. 先在烹饪中心半径内扫描所有冰箱（"fridge" 标签）
--   2. 按到 Warly 的距离升序排序
--   3. 把成品料理存进“最近且有空位”的冰箱
--   4. 若所有冰箱都满，才退而求其次找最近的箱子（"chest" 标签）
--   5. 再不行就把食物留在 Warly 背包里，避免丢失
--
-- 这样 Warly 绝不会跳过冰箱去存箱子，也不会只认自己（已被移除的）自家冰箱。

local TUNING       = require("mordomo/tuning")
local StructureUtil = require("mordomo/structure_util")

local Storage = {}

--- 判断某容器是否可以接收指定物品
--- @param container entity 容器实体
--- @param item entity 物品实体
--- @return boolean
local function CanAcceptItem(container, item)
    if not container or not container:IsValid() then return false end
    local cont = container.components.container
    if not cont then return false end
    -- container:CanTakeItemInSlot / HasItem 已经做堆叠与空槽检查
    return cont:CanTakeItemInSlot(item)
end

--- 计算两点（实体 → 中心）的距离平方
local function DistSqToCenter(ent, center)
    if not ent or not center then return math.huge end
    local x, _, z = ent.Transform:GetWorldPosition()
    local dx, dz = x - center.x, z - center.z
    return dx * dx + dz * dz
end

--- 把背包里的指定物品存入最近的有空位的冰箱；失败则尝试箱子。
--- @param inst entity      Warly NPC 实体
--- @param center table     烹饪中心 { x, z }
--- @param item entity      要存的物品（成品料理）
--- @return boolean         是否成功存入某个容器
function Storage.StoreItem(inst, center, item)
    if not inst or not item or not item:IsValid() then return false end
    center = center or (inst._cooking_center or { x = 0, z = 0 })

    local radius = TUNING.STORAGE_SEARCH_RADIUS or 18

    -- 1) 最近的冰箱优先（用户修复方案：freezer 优先标签）
    local iceboxes = StructureUtil.FindNearbyIceboxes(center, inst, radius)
    if #iceboxes > 0 then
        table.sort(iceboxes, function(a, b)
            return DistSqToCenter(a, center) < DistSqToCenter(b, center)
        end)
        for _, fridge in ipairs(iceboxes) do
            if CanAcceptItem(fridge, item) then
                local inv = inst.components.inventory
                if inv then inv:RemoveItem(item, false) end
                fridge.components.container:GiveItem(item)
                return true
            end
        end
    end

    -- 2) 退而求其次：最近的箱子（排除冰箱/锅）
    local chests = StructureUtil.FindNearbyChests(center, inst, radius)
    if #chests > 0 then
        table.sort(chests, function(a, b)
            return DistSqToCenter(a, center) < DistSqToCenter(b, center)
        end)
        for _, chest in ipairs(chests) do
            if CanAcceptItem(chest, item) then
                local inv = inst.components.inventory
                if inv then inv:RemoveItem(item, false) end
                chest.components.container:GiveItem(item)
                return true
            end
        end
    end

    -- 3) 全都满 / 没找到：留在背包里，避免丢失
    return false
end

--- 把 Warly 背包里所有“成品料理”统一存入最近的冰箱/箱子。
--- @param inst entity  Warly NPC 实体
--- @param center table 烹饪中心 { x, z }
--- @return number 存入容器的物品数量
function Storage.StoreAllCookedFood(inst, center)
    if not inst or not inst.components.inventory then return 0 end
    local inv = inst.components.inventory
    local stored = 0

    -- 收集所有成品料理（避免在迭代中修改背包）
    local to_store = {}
    for i = 1, inv.maxslots do
        local item = inv:GetItemInSlot(i)
        if item and item:IsValid() and item:HasTag("preparedfood") then
            to_store[#to_store + 1] = item
        end
    end

    for _, item in ipairs(to_store) do
        if item:IsValid() and Storage.StoreItem(inst, center, item) then
            stored = stored + 1
        end
    end

    return stored
end

return Storage
