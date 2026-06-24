-- scripts/npc/npc_cooking_planner.lua
-- NPC 烹饪规划器 —— 选择最优食谱并规划取材路线
-- ────────────────────────────────────────────────────────────

local cooking        = require("cooking")
local CookingRecipes = require("mordomo/cooking_recipes")
local NPC_TUNING     = require("mordomo/tuning")

local CookingPlanner = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  注入子模块方法
-- ═══════════════════════════════════════════════════════════════════════════
require("mordomo/cooking_ingredient_finder").AttachTo(CookingPlanner)
require("mordomo/cooking_recipe_scorer").AttachTo(CookingPlanner)

-- ═══════════════════════════════════════════════════════════════════════════
--  配置常量
-- ═══════════════════════════════════════════════════════════════════════════
local DEBUG_COOKING      = NPC_TUNING.DEBUG_COOKING or false

local function CookLog(...)
    if NPC_TUNING.DEBUG_COOKING then
        print("[烹饪调试]", ...)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  以下工具函数保留在主文件供内部使用
-- ═══════════════════════════════════════════════════════════════════════════

local function Log(...)
    if DEBUG_COOKING then
        print("[CookingPlanner]", ...)
    end
end

--- 获取食材的标签数据
--- @param prefab string 食材 prefab 名
--- @return table|nil { tag = value, ... }
local function GetIngredientTags(prefab)
    local data = cooking.ingredients[prefab]
    if data and data.tags then
        return data.tags
    end
    -- DST别名解析：cookedX → X_cooked（DST命名不一致）
    -- 已知别名：cookedmonstermeat→monstermeat_cooked, cookedmeat→meat_cooked, cookedsmallmeat→smallmeat_cooked
    if prefab:sub(1, 6) == "cooked" then
        local resolved = prefab:sub(7) .. "_cooked"
        data = cooking.ingredients[resolved]
        if data and data.tags then
            return data.tags
        end
    end
    return nil
end

--- 检查物品是否是原材料（非成品料理）
--- @param prefab string
--- @return boolean
local function IsRawIngredient(prefab)
    -- 有食材标签的是原材料（支持DST别名）
    if cooking.IsCookingIngredient(prefab) then
        return true
    end
    -- 排除已有的成品料理
    if CookingRecipes.GetRecipeByName(prefab) then
        return false
    end
    return false
end

--- 检查物品是否是成品料理
--- @param prefab string
--- @return boolean
local function IsPreparedFood(prefab)
    return CookingRecipes.GetRecipeByName(prefab) ~= nil
end

--- 计算一组食材的标签总和
--- @param prefab_list table { prefab, prefab, ... }
--- @return table { tag = total_value, ... }
local function CalculateTags(prefab_list)
    local tags = {}
    for _, prefab in ipairs(prefab_list) do
        local ing_tags = GetIngredientTags(prefab)
        if ing_tags then
            for tag, val in pairs(ing_tags) do
                tags[tag] = (tags[tag] or 0) + val
            end
        end
    end
    return tags
end

--- 生成槽位唯一键（用于防止重复选取）
local function SlotKey(container, slot)
    return tostring(container.GUID) .. "_" .. tostring(slot)
end

-- ═══════════════════════════════════════════════════════════════════════════
--  食材扫描/统计/选择逻辑已提取到 npc_cooking_ingredient_finder.lua
--  食谱评分/匹配逻辑已提取到 npc_cooking_recipe_scorer.lua
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
--  FindAvailableCookpot: 查找可用烹饪锅
-- ═══════════════════════════════════════════════════════════════════════════
--- @param cookpots table {entity, ...}
--- @return entity|nil
function CookingPlanner.FindAvailableCookpot(cookpots)
    -- 优先找空闲的锅
    for _, pot in ipairs(cookpots) do
        if pot:IsValid() and pot.components.stewer then
            local stewer = pot.components.stewer
            if not stewer:IsCooking() and not stewer:IsDone() then
                Log("FindAvailableCookpot: found idle pot", pot.prefab)
                return pot
            end
        end
    end
    
    -- 其次找已完成的锅（行为层会先收菜再做）
    for _, pot in ipairs(cookpots) do
        if pot:IsValid() and pot.components.stewer and pot.components.stewer:IsDone() then
            Log("FindAvailableCookpot: found done pot", pot.prefab)
            return pot
        end
    end
    
    Log("FindAvailableCookpot: no available pot")
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
--  PlanCooking: 顶层规划函数
-- ═══════════════════════════════════════════════════════════════════════════
--- @param inst entity NPC 实体
--- @param containers table {entity,...} 所有可访问的容器
--- @param cookpots table {entity,...} 所有可访问的烹饪锅
--- @param is_warly boolean 是否为 Warly NPC
--- @return table|nil plan
function CookingPlanner.PlanCooking(inst, containers, cookpots, is_warly)
    Log("=== PlanCooking Start ===")
    Log("  NPC:", inst.prefab or "?", "is_warly:", tostring(is_warly))
    Log("  containers:", #containers, "cookpots:", #cookpots)
    
    -- 1. 找可用锅
    local cookpot = CookingPlanner.FindAvailableCookpot(cookpots)
    if not cookpot then
        Log("PlanCooking: no available cookpot")
        return nil
    end
    
    -- 2. 检查背包空间（需要至少4个空槽位装食材）
    local inv = inst.components.inventory
    if not inv then
        Log("PlanCooking: no inventory")
        return nil
    end
    
    local free_slots = 0
    for i = 1, inv.maxslots do
        if not inv:GetItemInSlot(i) then
            free_slots = free_slots + 1
        end
    end
    
    if free_slots < 4 then
        Log("PlanCooking: not enough free slots:", free_slots)
        return nil
    end
    
    -- 3. 扫描食材
    local pool = CookingPlanner.ScanIngredients(containers)
    if not next(pool) then
        Log("PlanCooking: no ingredients found")
        return nil
    end
    
    -- 4. 统计已有菜品
    local existing = CookingPlanner.CountExistingDishes(containers)
    
    -- 5. 确定烹饪锅类型名称
    --    大厨专属食谱只注册在 "portablecookpot" 上，
    --    NPC大厨不区分锅的类型，统一按 "portablecookpot" 验证以支持专属食谱
    local cooker_name = is_warly and "portablecookpot" or cookpot.prefab
    
    -- 6. 找最优食谱
    local recipe = CookingPlanner.FindBestRecipe(pool, existing, is_warly, cooker_name)
    if not recipe then
        Log("PlanCooking: no valid recipe")
        return nil
    end
    
    -- 7. 获取已选择的食材（在 FindBestRecipe 中附加）
    local ingredients = recipe._selected_ingredients
    if not ingredients then
        Log("PlanCooking: no selected ingredients")
        return nil
    end
    
    -- 8. 按容器分组生成取材路线
    local route = {}
    local container_map = {}  -- container.GUID -> index in route
    
    for _, ing in ipairs(ingredients) do
        local guid = ing.container.GUID
        local idx = container_map[guid]
        if not idx then
            idx = #route + 1
            route[idx] = { container = ing.container, items = {} }
            container_map[guid] = idx
        end
        table.insert(route[idx].items, {
            slot = ing.slot,
            prefab = ing.prefab,
            take_count = ing.take_count,
        })
    end
    
    local plan = {
        recipe_name = recipe.name,
        cookpot = cookpot,
        pickup_route = route,
    }
    
    Log("=== PlanCooking Success ===")
    Log("  recipe:", recipe.name, "score:", recipe.score)
    Log("  cookpot:", cookpot.prefab)
    Log("  route steps:", #route)
    for i, step in ipairs(route) do
        Log(string.format("    [%d] container: %s", i, step.container.prefab or "?"))
        for _, item in ipairs(step.items) do
            Log(string.format("        slot %d: %s x%d", item.slot, item.prefab, item.take_count))
        end
    end
    
    CookLog(string.format("PlanCooking: recipe=%s, ingredients=%d, route_steps=%d", recipe.name, 4, #route))
    return plan
end

return CookingPlanner
