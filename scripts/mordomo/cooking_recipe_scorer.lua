-- scripts/npc/npc_cooking_recipe_scorer.lua
-- CookingPlanner 子模块：食谱评分/匹配逻辑
-- 通过 AttachTo(CookingPlanner) 注入静态方法
-- ────────────────────────────────────────────────────────────

local cooking        = require("cooking")
local CookingRecipes = require("mordomo/cooking_recipes")
local NPC_TUNING     = require("mordomo/tuning")

local RecipeScorer = {}

local DEBUG_COOKING = NPC_TUNING.DEBUG_COOKING or false

local function Log(...)
    if DEBUG_COOKING then
        print("[CookingPlanner]", ...)
    end
end

-- ════════════════════════════════════════════════════════════
--  AttachTo: 注入食谱匹配方法到 CookingPlanner
-- ════════════════════════════════════════════════════════════

function RecipeScorer.AttachTo(CookingPlanner)

    --- 匹配最优可做食谱
    function CookingPlanner.FindBestRecipe(ingredient_pool, existing_dishes, is_warly, cooker_name)
        local recipes = CookingRecipes.GetAvailableRecipes(is_warly)
        
        -- 肉丸优先
        if not existing_dishes["meatballs"] or existing_dishes["meatballs"] < 1 then
            local meatball_card = CookingRecipes.GetRecipeByName("meatballs")
            if meatball_card and not CookingRecipes.IsExcluded("meatballs") then
                local ingredients = CookingPlanner.SelectIngredients(meatball_card, ingredient_pool)
                if ingredients then
                    local names = {}
                    for _, ing in ipairs(ingredients) do
                        for _ = 1, ing.take_count do
                            table.insert(names, ing.prefab)
                        end
                    end
                    local product = cooking.CalculateRecipe(cooker_name, names)
                    if product == "meatballs" then
                        Log("FindBestRecipe: 怪物肉优先 → meatballs")
                        meatball_card._selected_ingredients = ingredients
                        return meatball_card
                    end
                end
            end
        end
        
        for _, recipe in ipairs(recipes) do
            repeat
                if CookingRecipes.IsExcluded(recipe.name) then
                    break
                end
                
                if existing_dishes[recipe.name] and existing_dishes[recipe.name] >= (NPC_TUNING.COOK_SAME_DISH_MAX or 10) then
                    Log("FindBestRecipe: skip", recipe.name, "- too many existing")
                    break
                end
                
                if recipe.required then
                    local pass = true
                    for prefab, count in pairs(recipe.required) do
                        local data = ingredient_pool[prefab]
                        if not data or data.total < count then
                            pass = false
                            break
                        end
                    end
                    if not pass then
                        break
                    end
                end
                
                if recipe.required_any then
                    local found = false
                    for _, prefab in ipairs(recipe.required_any) do
                        if ingredient_pool[prefab] and ingredient_pool[prefab].total >= 1 then
                            found = true
                            break
                        end
                    end
                    if not found then
                        break
                    end
                end
                
                if recipe.required_any2 then
                    local found = false
                    for _, prefab in ipairs(recipe.required_any2) do
                        if ingredient_pool[prefab] and ingredient_pool[prefab].total >= 1 then
                            found = true
                            break
                        end
                    end
                    if not found then
                        break
                    end
                end
                
                local ingredients = CookingPlanner.SelectIngredients(recipe, ingredient_pool)
                if not ingredients then
                    break
                end
                
                local names = {}
                for _, ing in ipairs(ingredients) do
                    for _ = 1, ing.take_count do
                        table.insert(names, ing.prefab)
                    end
                end
                
                local product, cooktime = cooking.CalculateRecipe(cooker_name, names)
                if product == recipe.name then
                    Log("FindBestRecipe: selected", recipe.name, "score:", recipe.score)
                    recipe._selected_ingredients = ingredients
                    return recipe
                elseif product and product ~= recipe.name then
                    if not CookingRecipes.IsExcluded(product) then
                        local actual_count = existing_dishes[product] or 0
                        local max_count = NPC_TUNING.COOK_SAME_DISH_MAX or 10
                        if actual_count < max_count then
                            local actual_card = CookingRecipes.GetRecipeByName(product)
                            if actual_card then
                                Log("FindBestRecipe:", recipe.name, "→ 接受随机结果:", product)
                                actual_card._selected_ingredients = ingredients
                                return actual_card
                            else
                                Log("FindBestRecipe:", recipe.name, "→ 接受未知食谱(mod?):", product)
                                return {
                                    name = product,
                                    score = recipe.score,
                                    _selected_ingredients = ingredients,
                                }
                            end
                        else
                            Log("FindBestRecipe:", recipe.name, "→ 随机结果", product, "已超限额, 跳过")
                        end
                    end
                    Log("FindBestRecipe:", recipe.name, "validation failed, got:", product or "nil")
                else
                    Log("FindBestRecipe:", recipe.name, "validation failed, got:", product or "nil")
                end
            until true
        end
        
        Log("FindBestRecipe: no valid recipe found")
        return nil
    end

end -- RecipeScorer.AttachTo

return RecipeScorer
