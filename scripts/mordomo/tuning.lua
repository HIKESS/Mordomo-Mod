-- scripts/mordomo/tuning.lua
-- Mordomo-Mod 调参常量（仅保留 Warly 厨师所需部分）
-- ────────────────────────────────────────────────────────────
-- 本文件为独立 Mod 的精简调参表，提供烹饪管线模块
-- (cooking_planner / ingredient_finder / recipe_scorer / recipes)
-- 与本 Mod 自定义脚本所需的全部常量。

local M = {}

-- ════════════════════════════════════════════════════════════
--  调试开关
-- ════════════════════════════════════════════════════════════
M.DEBUG_BEHAVIOR = false   -- 行为树调试输出
M.DEBUG_COOKING  = false   -- 烹饪管线调试输出

-- ════════════════════════════════════════════════════════════
--  移动 / 跟随
-- ════════════════════════════════════════════════════════════
M.RUN_SPEED          = 7        -- NPC 移动速度
M.MAX_NPC_FOLLOWERS  = 2        -- 单个玩家最多跟随的 Mordomo NPC 数

-- 跟随时的目标距离（格）
M.FOLLOW_TARGET_DIST = 3        -- 跟随目标距离
M.FOLLOW_LEASH_DIST  = 12       -- 超过该距离开始奔跑追赶

-- ════════════════════════════════════════════════════════════
--  Warly 角色属性（仅厨师相关）
-- ════════════════════════════════════════════════════════════
M.CHARACTER_STATS = {
    warly = {
        health        = 150,
        max_health    = 150,
        inventory_slots = 16,
        ghost_regen   = 2,
        cook_time_mult = 0.5,   -- 0.5 = 烹饪速度 2 倍
    },
}

-- ════════════════════════════════════════════════════════════
--  烹饪相关常量
-- ════════════════════════════════════════════════════════════
M.COOK_INTERVAL          = 2     -- 两次做饭最小间隔（秒）
M.COOK_SAME_DISH_MAX     = 3     -- 同菜超此数量降权
M.COOK_APPROACH_DIST     = 1.5   -- 接近锅/容器距离（格）
M.COOK_MAX_WAIT          = 120   -- 等锅最长时间（秒，超时放弃）
M.COOK_LEASH_RETURN_DIST = 5     -- 拴绳回位触发距离（格）

-- 厨师工作范围（CookHere 命令扫描锅/食材的半径，格）
M.COOK_RANGE_DEFAULT = 17
M.COOK_RANGE_MIN     = 10
M.COOK_RANGE_MAX     = 30

-- 工作半径（FarmHere 等通用，保留兼容字段）
M.FARM_WORK_RADIUS = M.COOK_RANGE_DEFAULT

-- ── 烹饪黑名单 ─────────────────────────────────────────────
-- 1) COOK_INGREDIENT_BLACKLIST: 不会被当作烹饪食材扫描
M.COOK_INGREDIENT_BLACKLIST = {
    mandrake          = true,
    glommerfuel       = true,
    log               = true,
    rot               = true,
    spoiled_food      = true,
    spoiled_fish      = true,
    spoiled_fish_small= true,
    rottenegg         = true,
    wetgoop           = true,
    monsterlasagna    = true,
    gears             = true,
}

-- 2) COOK_RECIPE_BLACKLIST: 即使可做也不会进入做菜计划
M.COOK_RECIPE_BLACKLIST = {
    wetgoop          = true,
    monsterlasagna   = true,
    powcake          = true,
    monstertartare   = true,
    shroombait       = true,
    beefalofeed      = true,
    beefalotreat     = true,
    jammypreserves   = true,
    ratatouille      = true,
}

-- ════════════════════════════════════════════════════════════
--  存储相关（修复“只存自家冰箱/乱存箱子”的 Bug）
-- ════════════════════════════════════════════════════════════
-- 熟食存储优先级：先找最近的冰箱（fridge/freezer），没有再退而求其次找箱子。
-- 这正是用户所要求的“freezer 更近优先”标签策略。
M.STORAGE_SEARCH_RADIUS = 18        -- 存储搜索半径（格）
M.STORAGE_FREEZER_TAGS  = { "fridge" }  -- 冰箱/冷冻箱优先标签
M.STORAGE_CHEST_TAGS    = { "chest" }   -- 退而求其次的箱子标签

return M
