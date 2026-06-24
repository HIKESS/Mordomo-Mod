-- scripts/npc/npc_cooking_ingredient_finder.lua
-- CookingPlanner 子模块：食材扫描/统计/选择逻辑
-- 通过 AttachTo(CookingPlanner) 注入静态方法
-- ────────────────────────────────────────────────────────────

local cooking        = require("cooking")
local CookingRecipes = require("mordomo/cooking_recipes")
local NPC_TUNING     = require("mordomo/tuning")

local IngredientFinder = {}

-- ════════════════════════════════════════════════════════════
--  本模块所需常量与辅助函数
-- ════════════════════════════════════════════════════════════
local DEBUG_COOKING      = NPC_TUNING.DEBUG_COOKING or false
local INGREDIENT_BLACKLIST = NPC_TUNING.COOK_INGREDIENT_BLACKLIST or {}

local DEFAULT_INGREDIENT_PRIORITY = {
    meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" },
}

local function CookLog(...)
    if NPC_TUNING.DEBUG_COOKING then
        print("[烹饪调试]", ...)
    end
end

local function Log(...)
    if DEBUG_COOKING then
        print("[CookingPlanner]", ...)
    end
end

--- 获取食材的标签数据
local function GetIngredientTags(prefab)
    local data = cooking.ingredients[prefab]
    if data and data.tags then
        return data.tags
    end
    if prefab:sub(1, 6) == "cooked" then
        local resolved = prefab:sub(7) .. "_cooked"
        data = cooking.ingredients[resolved]
        if data and data.tags then
            return data.tags
        end
    end
    return nil
end

--- 计算一组食材的标签总和
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

--- 生成槽位唯一键
local function SlotKey(container, slot)
    return tostring(container.GUID) .. "_" .. tostring(slot)
end

-- ════════════════════════════════════════════════════════════
--  AttachTo: 注入食材扫描/选择方法到 CookingPlanner
-- ════════════════════════════════════════════════════════════

function IngredientFinder.AttachTo(CookingPlanner)

    --- 扫描所有容器中的可用食材
    function CookingPlanner.ScanIngredients(containers)
        local pool = {}
        
        for _, container in ipairs(containers) do
            if container:IsValid() and container.components.container then
                local cont = container.components.container
                for slot = 1, cont:GetNumSlots() do
                    local item = cont:GetItemInSlot(slot)
                    if item and item:IsValid() then
                        local prefab = item.prefab
                        if INGREDIENT_BLACKLIST[prefab] then
                            CookLog(string.format("ScanIngredients 跳过黑名单食材: prefab=%s, container=%s", prefab, tostring(container)))
                        else
                            if cooking.IsCookingIngredient(prefab) then
                                local count = 1
                                if item.components.stackable then
                                    count = item.components.stackable:StackSize()
                                end

                                if not pool[prefab] then
                                    pool[prefab] = { total = 0, locations = {} }
                                end
                                pool[prefab].total = pool[prefab].total + count
                                table.insert(pool[prefab].locations, {
                                    container = container,
                                    slot = slot,
                                    count = count,
                                })
                                CookLog(string.format("ScanIngredients 食材: prefab=%s, count=%d, container=%s", prefab, count, tostring(container)))
                            end
                        end
                    end
                end
            end
        end
        
        if DEBUG_COOKING then
            Log("=== Scanned Ingredients ===")
            for prefab, data in pairs(pool) do
                Log(string.format("  %s: total=%d, locations=%d", prefab, data.total, #data.locations))
            end
        end
        
        return pool
    end

    --- 统计容器中已有的各成品菜数量
    function CookingPlanner.CountExistingDishes(containers)
        local counts = {}
        
        for _, container in ipairs(containers) do
            if container:IsValid() and container.components.container then
                local cont = container.components.container
                for slot = 1, cont:GetNumSlots() do
                    local item = cont:GetItemInSlot(slot)
                    if item and item:IsValid() then
                        local prefab = item.prefab
                        if CookingRecipes.GetRecipeByName(prefab) or item:HasTag("preparedfood") then
                            local count = 1
                            if item.components.stackable then
                                count = item.components.stackable:StackSize()
                            end
                            counts[prefab] = (counts[prefab] or 0) + count
                        end
                    end
                end
            end
        end
        
        if DEBUG_COOKING then
            Log("=== Existing Dishes ===")
            for prefab, count in pairs(counts) do
                Log(string.format("  %s: %d", prefab, count))
            end
        end
        
        return counts
    end

    --- 为食谱选择具体的4个食材实例
    function CookingPlanner.SelectIngredients(recipe_card, ingredient_pool)
        CookLog("══ SelectIngredients 开始 ══ 食谱:", recipe_card.name)
        for prefab, data in pairs(ingredient_pool) do
            CookLog(string.format("  食材池: %s x%d", prefab, data.total))
        end
        local selected = {}
        local used = {}
        local pool_used = {}
        
        local function TakeFromPool(prefab, count)
            local data = ingredient_pool[prefab]
            if not data then return false end
            
            local already_used = pool_used[prefab] or 0
            local available = data.total - already_used
            if available < count then return false end
            
            local needed = count
            for _, loc in ipairs(data.locations) do
                if needed <= 0 then break end
                
                local key = SlotKey(loc.container, loc.slot)
                local slot_used = used[key] or 0
                local slot_available = loc.count - slot_used
                
                if slot_available > 0 then
                    local take = math.min(needed, slot_available)
                    table.insert(selected, {
                        container = loc.container,
                        slot = loc.slot,
                        prefab = prefab,
                        take_count = take,
                    })
                    used[key] = slot_used + take
                    pool_used[prefab] = (pool_used[prefab] or 0) + take
                    needed = needed - take
                end
            end
            
            return needed <= 0
        end
        
        local function HasAvailable(prefab, count)
            local data = ingredient_pool[prefab]
            if not data then return false end
            local already_used = pool_used[prefab] or 0
            return (data.total - already_used) >= count
        end
        
        local function GetAvailable(prefab)
            local data = ingredient_pool[prefab]
            if not data then return 0 end
            local already_used = pool_used[prefab] or 0
            return data.total - already_used
        end
        
        -- 1. 满足 required
        if recipe_card.required then
            for prefab, count in pairs(recipe_card.required) do
                if not TakeFromPool(prefab, count) then
                    Log("SelectIngredients: required failed for", prefab)
                    return nil
                end
            end
        end
        
        -- 2. 满足 required_any
        if recipe_card.required_any then
            local found = false
            for _, prefab in ipairs(recipe_card.required_any) do
                if HasAvailable(prefab, 1) then
                    if TakeFromPool(prefab, 1) then
                        found = true
                        break
                    end
                end
            end
            if not found then
                Log("SelectIngredients: required_any failed")
                return nil
            end
        end
        
        -- 3. 满足 required_any2
        if recipe_card.required_any2 then
            local found = false
            for _, prefab in ipairs(recipe_card.required_any2) do
                if HasAvailable(prefab, 1) then
                    if TakeFromPool(prefab, 1) then
                        found = true
                        break
                    end
                end
            end
            if not found then
                Log("SelectIngredients: required_any2 failed")
                return nil
            end
        end
        
        -- 4. 计算当前已选食材的标签
        local function GetCurrentTags()
            local prefab_list = {}
            for _, sel in ipairs(selected) do
                for _ = 1, sel.take_count do
                    table.insert(prefab_list, sel.prefab)
                end
            end
            return CalculateTags(prefab_list)
        end
        
        -- 5. 满足 min_tags
        if recipe_card.min_tags then
            local current_tags = GetCurrentTags()
            for tag, min_val in pairs(recipe_card.min_tags) do
                local current = current_tags[tag] or 0
                CookLog(string.format("  [min_tags] 标签=%s, 需要≥%.1f, 当前=%.1f", tag, min_val, current))
                while current < min_val do
                    local found = false
                    
                    local priority_list = recipe_card.ingredient_priority and recipe_card.ingredient_priority[tag]
                    local priority_source = "食谱定义"
                    if not priority_list then
                        local skip_default = false
                        if tag == "meat" and recipe_card.special_check then
                            if recipe_card.special_check:find("meat_less_than") then
                                skip_default = true
                                CookLog("    跳过全局默认优先级: special_check=" .. recipe_card.special_check)
                            end
                        end
                        if not skip_default then
                            priority_list = DEFAULT_INGREDIENT_PRIORITY[tag]
                            priority_source = "全局默认"
                        end
                    end
                    if priority_list then
                        CookLog(string.format("    优先级列表(%s): %s", priority_source, table.concat(priority_list, ", ")))
                        for _, prefab in ipairs(priority_list) do
                            local avail = HasAvailable(prefab, 1)
                            if avail then
                                local tags = GetIngredientTags(prefab)
                                if tags and tags[tag] and tags[tag] > 0 then
                                    local forbidden = false
                                    local forbidden_reason = ""
                                    if recipe_card.forbidden_tags then
                                        for _, ftag in ipairs(recipe_card.forbidden_tags) do
                                            if tags[ftag] and tags[ftag] > 0 then
                                                forbidden = true
                                                forbidden_reason = "forbidden_tag=" .. ftag
                                                break
                                            end
                                        end
                                    end
                                    if not forbidden and tags.monster and tags.monster > 0 then
                                        local all_tags = GetCurrentTags()
                                        local cur_monster = all_tags.monster or 0
                                        if cur_monster + tags.monster >= 2 then
                                            forbidden = true
                                            forbidden_reason = string.format("monster累积=%d+%d≥2", cur_monster, tags.monster)
                                        end
                                    end
                                    if not forbidden then
                                        if TakeFromPool(prefab, 1) then
                                            current = current + tags[tag]
                                            found = true
                                            CookLog(string.format("    ✓ 优先选中: %s (标签%s=%.1f, 当前累计=%.1f)", prefab, tag, tags[tag], current))
                                            break
                                        else
                                            CookLog(string.format("    ✗ %s: TakeFromPool失败", prefab))
                                        end
                                    else
                                        CookLog(string.format("    ✗ %s: 被禁止 (%s)", prefab, forbidden_reason))
                                    end
                                else
                                    CookLog(string.format("    ✗ %s: 无%s标签或标签值≤0", prefab, tag))
                                end
                            else
                                CookLog(string.format("    ✗ %s: 不在食材池中", prefab))
                            end
                        end
                    else
                        CookLog("    无优先级列表")
                    end
                    
                    if not found then
                        CookLog("    优先级未命中，进入回退循环...")
                        for prefab, data in pairs(ingredient_pool) do
                            if HasAvailable(prefab, 1) then
                                local tags = GetIngredientTags(prefab)
                                if tags and tags[tag] and tags[tag] > 0 then
                                    local forbidden = false
                                    if recipe_card.forbidden_tags then
                                        for _, ftag in ipairs(recipe_card.forbidden_tags) do
                                            if tags[ftag] and tags[ftag] > 0 then
                                                forbidden = true
                                                break
                                            end
                                        end
                                    end
                                    if not forbidden and tags.monster and tags.monster > 0 then
                                        local all_tags = GetCurrentTags()
                                        if (all_tags.monster or 0) + tags.monster >= 2 then
                                            forbidden = true
                                        end
                                    end
                                    if not forbidden then
                                        if TakeFromPool(prefab, 1) then
                                            current = current + tags[tag]
                                            found = true
                                            CookLog(string.format("    ✓ 回退选中: %s (标签%s=%.1f, 当前累计=%.1f)", prefab, tag, tags[tag], current))
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    if not found then
                        Log("SelectIngredients: min_tags failed for", tag)
                        return nil
                    end
                    if #selected > 4 then
                        return nil
                    end
                end
            end
        end
        
        -- 6. 用填充物填满到4个
        local total_count = 0
        for _, sel in ipairs(selected) do
            total_count = total_count + sel.take_count
        end
        
        local function GetCurrentMonsterValue()
            local monster_val = 0
            for _, sel in ipairs(selected) do
                local tags = GetIngredientTags(sel.prefab)
                if tags and tags.monster then
                    monster_val = monster_val + (tags.monster * sel.take_count)
                end
            end
            return monster_val
        end

        local function GetCurrentInedibleValue()
            local inedible_val = 0
            for _, sel in ipairs(selected) do
                local tags = GetIngredientTags(sel.prefab)
                if tags and tags.inedible then
                    inedible_val = inedible_val + (tags.inedible * sel.take_count)
                end
            end
            return inedible_val
        end

        local function GetCurrentMeatValue()
            local meat_val = 0
            for _, sel in ipairs(selected) do
                local tags = GetIngredientTags(sel.prefab)
                if tags and tags.meat then
                    meat_val = meat_val + (tags.meat * sel.take_count)
                end
            end
            return meat_val
        end

        local function ViolatesSpecialCheck(candidate_tags)
            if not recipe_card.special_check or not candidate_tags then return false end
            local sc = recipe_card.special_check
            if sc == "inedible_max_1" then
                if candidate_tags.inedible and candidate_tags.inedible > 0 then
                    if GetCurrentInedibleValue() + candidate_tags.inedible > 1 then
                        CookLog(string.format("    ✗ special_check inedible_max_1: 当前=%.1f + %.1f > 1",
                            GetCurrentInedibleValue(), candidate_tags.inedible))
                        return true
                    end
                end
            elseif sc == "inedible_max_2" then
                if candidate_tags.inedible and candidate_tags.inedible > 0 then
                    if GetCurrentInedibleValue() + candidate_tags.inedible > 2 then
                        CookLog(string.format("    ✗ special_check inedible_max_2: 当前=%.1f + %.1f > 2",
                            GetCurrentInedibleValue(), candidate_tags.inedible))
                        return true
                    end
                end
            elseif sc == "meat_max_1.5" then
                if candidate_tags.meat and candidate_tags.meat > 0 then
                    if GetCurrentMeatValue() + candidate_tags.meat > 1.5 then
                        CookLog(string.format("    ✗ special_check meat_max_1.5: 当前=%.1f + %.1f > 1.5",
                            GetCurrentMeatValue(), candidate_tags.meat))
                        return true
                    end
                end
            elseif sc:find("meat_less_than") then
                if candidate_tags.meat and candidate_tags.meat > 0 then
                    local limit = tonumber(sc:match("meat_less_than_([%d%.]+)")) or 1
                    if GetCurrentMeatValue() + candidate_tags.meat >= limit then
                        CookLog(string.format("    ✗ special_check %s: 当前=%.1f + %.1f >= %.1f",
                            sc, GetCurrentMeatValue(), candidate_tags.meat, limit))
                        return true
                    end
                end
            end
            return false
        end

        local fillers = CookingRecipes.GetFillers()
        while total_count < 4 do
            local found = false
            local current_monster = GetCurrentMonsterValue()
            
            for _, filler in ipairs(fillers) do
                if HasAvailable(filler, 1) then
                    local tags = GetIngredientTags(filler)
                    local forbidden = false
                    if recipe_card.forbidden_tags and tags then
                        for _, ftag in ipairs(recipe_card.forbidden_tags) do
                            if tags[ftag] and tags[ftag] > 0 then
                                forbidden = true
                                break
                            end
                        end
                    end
                    
                    if not forbidden and tags and tags.monster and tags.monster > 0 then
                        if current_monster + tags.monster >= 2 then
                            Log("SelectIngredients: skip filler", filler, "- would trigger monsterlasagna")
                            forbidden = true
                        end
                    end

                    if not forbidden and ViolatesSpecialCheck(tags) then
                        Log("SelectIngredients: skip filler", filler, "- violates special_check:", recipe_card.special_check)
                        forbidden = true
                    end
                    
                    if not forbidden then
                        if TakeFromPool(filler, 1) then
                            total_count = total_count + 1
                            found = true
                            break
                        end
                    end
                end
            end
            
            if not found then
                current_monster = GetCurrentMonsterValue()
                
                for prefab, data in pairs(ingredient_pool) do
                    if HasAvailable(prefab, 1) then
                        local tags = GetIngredientTags(prefab)
                        local forbidden = false
                        if recipe_card.forbidden_tags and tags then
                            for _, ftag in ipairs(recipe_card.forbidden_tags) do
                                if tags[ftag] and tags[ftag] > 0 then
                                    forbidden = true
                                    break
                                end
                            end
                        end
                        
                        if not forbidden and tags and tags.monster and tags.monster > 0 then
                            if current_monster + tags.monster >= 2 then
                                Log("SelectIngredients: skip ingredient", prefab, "- would trigger monsterlasagna")
                                forbidden = true
                            end
                        end

                        if not forbidden and ViolatesSpecialCheck(tags) then
                            Log("SelectIngredients: skip ingredient", prefab, "- violates special_check:", recipe_card.special_check)
                            forbidden = true
                        end
                        
                        if not forbidden then
                            if TakeFromPool(prefab, 1) then
                                total_count = total_count + 1
                                found = true
                                break
                            end
                        end
                    end
                end
            end
            
            if not found then
                Log("SelectIngredients: cannot fill to 4")
                return nil
            end
        end
        
        -- 7. 最终检查 forbidden_tags
        if recipe_card.forbidden_tags then
            local final_tags = GetCurrentTags()
            for _, ftag in ipairs(recipe_card.forbidden_tags) do
                if final_tags[ftag] and final_tags[ftag] > 0 then
                    Log("SelectIngredients: forbidden_tags check failed for", ftag)
                    return nil
                end
            end
        end
        
        -- 8. 验证长度
        local final_count = 0
        for _, sel in ipairs(selected) do
            final_count = final_count + sel.take_count
        end
        if final_count ~= 4 then
            Log("SelectIngredients: final count != 4:", final_count)
            return nil
        end
        
        CookLog(string.format("  ══ %s 最终选材 ══", recipe_card.name))
        for _, sel in ipairs(selected) do
            CookLog(string.format("    → %s x%d (slot %d)", sel.prefab, sel.take_count, sel.slot))
        end
        
        return selected
    end

end -- IngredientFinder.AttachTo

return IngredientFinder
