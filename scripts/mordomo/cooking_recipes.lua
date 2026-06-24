-- NPC 烹饪食谱优先级表
-- 定义 NPC 应该做什么菜、优先级、食材需求
-- 打分公式: score = health * 1.0 + hunger * 0.4 + sanity * 0.8
-- 特殊效果（温度BUFF、攻击BUFF等）: +15

local CookingRecipes = {}
local NPC_TUNING = require("mordomo/tuning")

-- ═══════════════════════════════════════════════════════════════════════════
-- 填充物优先级（越前越优先，用于凑满4个槽位）
-- ═══════════════════════════════════════════════════════════════════════════
CookingRecipes.FILLER_PRIORITY = {
    -- 无食物标签，最安全
    "twigs",            -- inedible 1
    "cutgrass",         -- 无标签
    "ice",              -- frozen 1
    "berries",          -- fruit 0.5
    "berries_cooked",   -- fruit 0.5
    "berries_juicy",    -- fruit 0.5
    "berries_juicy_cooked", -- fruit 0.5
    "red_cap",          -- veggie 0.5
    "red_cap_cooked",   -- veggie 0.5
    "blue_cap",         -- veggie 0.5
    "blue_cap_cooked",  -- veggie 0.5
    "green_cap",        -- veggie 0.5
    "green_cap_cooked", -- veggie 0.5
    "kelp",             -- veggie 0.5
    "kelp_cooked",      -- veggie 0.5
    "kelp_dried",       -- veggie 0.5
    "smallmeat",        -- meat 0.5
    "smallmeat_cooked", -- meat 0.5
    "smallmeat_dried",  -- meat 0.5
    "batnose",          -- meat 0.5
    "batnose_cooked",   -- meat 0.5
    "fishmeat_small",   -- meat 0.5, fish 0.5
    "fishmeat_small_cooked", -- meat 0.5, fish 0.5
    "bird_egg",         -- egg 1
    "bird_egg_cooked",  -- egg 1
}

-- ═══════════════════════════════════════════════════════════════════════════
-- 排除列表（NPC永远不做的菜）
-- ═══════════════════════════════════════════════════════════════════════════
local DEFAULT_EXCLUDED = {
    wetgoop = true,
    monsterlasagna = true,
    powcake = true,
    monstertartare = true,
    shroombait = true,
    beefalofeed = true,
    beefalotreat = true,
    jammypreserves = true,
    ratatouille = true,
}

local function _CloneBoolMap(t)
    local out = {}
    for k, v in pairs(t or {}) do
        if v then
            out[k] = true
        end
    end
    return out
end

CookingRecipes.EXCLUDED = _CloneBoolMap(
    (NPC_TUNING and NPC_TUNING.COOK_RECIPE_BLACKLIST) or DEFAULT_EXCLUDED
)

-- ═══════════════════════════════════════════════════════════════════════════
-- 食谱卡片表（按 score 降序排列）
-- 每张卡片结构:
-- {
--     name = "prefab_name",           -- 料理 prefab 名
--     score = 85,                     -- 品质分（越高越优先）
--     warly_only = false,             -- 是否 Warly 专属
--     cooktime = 1,                   -- 烹饪时间倍数
--     required = { prefab = count },  -- 必需食材
--     required_any = { "a", "b" },    -- 可选必需（任一即可）
--     min_tags = { tag = min_value }, -- 最低标签要求
--     forbidden_tags = { "meat" },    -- 禁止标签（列表形式）
--     filler_count = 3,               -- 需要额外填充物数量
-- }
-- ═══════════════════════════════════════════════════════════════════════════

CookingRecipes.RECIPES = {
    -- ═══ S 层: 顶级料理 (score >= 90) ═══

    -- 曼德拉草汤
    { name = "mandrakesoup", score = 124, warly_only = false, cooktime = 3,
      required = { mandrake = 1 },
      filler_count = 3 },

    -- 新鲜水果可丽饼
    { name = "freshfruitcrepes", score = 112, warly_only = true, cooktime = 2,
      required = { butter = 1, honey = 1 },
      min_tags = { fruit = 1.5 },
      filler_count = 1 },

    -- 象鼻卷 
    { name = "koalefig_trunk", score = 112, warly_only = false, cooktime = 2,
      required_any = { "trunk_summer", "trunk_cooked", "trunk_winter" },
      required_any2 = { "fig", "fig_cooked" },
      filler_count = 2 },

    -- 高脚鸟蛋煎蛋 
    { name = "talleggs", score = 104, warly_only = false, cooktime = 2,
      required = { tallbirdegg = 1 },
      min_tags = { veggie = 1 },
      filler_count = 2 },

    -- 龙虾正餐 
    { name = "lobsterdinner", score = 95, warly_only = false, cooktime = 1,
      required = { wobster_sheller_land = 1, butter = 1 },
      min_tags = { meat = 1, fish = 1 },
      forbidden_tags = { "frozen" },
      filler_count = 2 },

    -- 海鲜杂烩
    { name = "moqueca", score = 95, warly_only = true, cooktime = 2,
      required_any = { "onion", "onion_cooked" },
      required_any2 = { "tomato", "tomato_cooked" },
      min_tags = { fish = 0.5 },
      forbidden_tags = { "inedible" },
      filler_count = 1 },

    -- ═══ A 层: 优质料理 (score 70-89) ═══

    -- 海鲜
    { name = "surfnturf", score = 81, warly_only = false, cooktime = 1,
      min_tags = { meat = 2.5, fish = 1.5 },
      forbidden_tags = { "frozen" },
      filler_count = 0 },

    -- 大骨汤 
    { name = "bonesoup", score = 76, warly_only = true, cooktime = 2,
      required = { boneshard = 2 },
      required_any = { "onion", "onion_cooked" },
      min_tags = { inedible = 2 }, -- 需要 <3
      filler_count = 1 },

    -- 月饼
    { name = "yotr_food2", score = 72, warly_only = false, cooktime = 1,
      required = { honey = 2 },
      required_any = {
          "red_cap", "red_cap_cooked",
          "green_cap", "green_cap_cooked",
          "blue_cap", "blue_cap_cooked",
          "moon_cap", "moon_cap_cooked",
      },
      required_any2 = { "berries", "berries_cooked", "berries_juicy", "berries_juicy_cooked" },
      forbidden_tags = { "meat", "inedible", "frozen" },
      filler_count = 0 },

    -- 月冻 
    { name = "yotr_food3", score = 70, warly_only = false, cooktime = 1,
      required = { honey = 1, ice = 1 },
      required_any = {
          "red_cap", "red_cap_cooked",
          "green_cap", "green_cap_cooked",
          "blue_cap", "blue_cap_cooked",
          "moon_cap", "moon_cap_cooked",
      },
      required_any2 = { "berries", "berries_cooked", "berries_juicy", "berries_juicy_cooked" },
      forbidden_tags = { "meat", "inedible" },
      filler_count = 0 },

    -- 蜜汁火腿 
    { name = "honeyham", score = 69, warly_only = false, cooktime = 2,
      required = { honey = 1 },
      min_tags = { meat = 1.5 },
      forbidden_tags = { "inedible" },
      filler_count = 1,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 火龙果派 
    { name = "dragonpie", score = 69, warly_only = false, cooktime = 2,
      required_any = { "dragonfruit", "dragonfruit_cooked" },
      forbidden_tags = { "meat" },
      filler_count = 3 },

    -- ═══ B 层: 良好料理 (score 50-69) ═══

    -- 冰淇淋 
    { name = "icecream", score = 65, warly_only = false, cooktime = 0.5,
      min_tags = { frozen = 1, dairy = 1, sweetener = 1 },
      forbidden_tags = { "meat", "veggie", "inedible", "egg" },
      filler_count = 1 },

    -- 树叶肉汉堡
    { name = "leafymeatburger", score = 61, warly_only = false, cooktime = 2,
      required_any = { "plantmeat", "plantmeat_cooked" },
      required_any2 = { "onion", "onion_cooked" },
      min_tags = { veggie = 2 },
      filler_count = 1 },

    -- 华夫饼 
    { name = "waffles", score = 59, warly_only = false, cooktime = 0.5,
      required = { butter = 1 },
      required_any = { "berries", "berries_cooked", "berries_juicy", "berries_juicy_cooked" },
      min_tags = { egg = 1 },
      filler_count = 1 },

    -- 龙虾浓汤
    { name = "lobsterbisque", score = 58, warly_only = false, cooktime = 0.5,
      required = { wobster_sheller_land = 1 },
      min_tags = { frozen = 1 },
      filler_count = 2 },

    -- 火鸡正餐 
    { name = "turkeydinner", score = 57, warly_only = false, cooktime = 3,
      required = { drumstick = 2 },
      min_tags = { meat = 1.5 },
      required_veggie_or_fruit = true, -- veggie >= 0.5 or fruit
      filler_count = 0 },

    -- 藤壶意大利面
    { name = "barnaclinguine", score = 56, warly_only = false, cooktime = 2,
      required_any = { "barnacle", "barnacle_cooked" },
      min_tags = { veggie = 2 },
      special_check = "barnacle_count_2", -- 需要2个藤壶
      filler_count = 0 },

    -- 冰冻香蕉冰沙 
    { name = "frozenbananadaiquiri", score = 55, warly_only = false, cooktime = 1,
      required_any = { "cave_banana", "cave_banana_cooked" },
      min_tags = { frozen = 1 },
      forbidden_tags = { "meat", "fish" },
      filler_count = 2 },

    -- 无花果通心粉
    { name = "figatoni", score = 55, warly_only = false, cooktime = 2,
      required_any = { "fig", "fig_cooked" },
      min_tags = { veggie = 2 },
      forbidden_tags = { "meat" },
      filler_count = 1 },

    -- 树叶肉蛋奶酥
    { name = "leafymeatsouffle", score = 55, warly_only = false, cooktime = 2,
      min_tags = { sweetener = 2 },
      special_check = "plantmeat_count_2", -- 需要2个树叶肉
      filler_count = 0 },

    -- 冰香蕉 
    { name = "bananapop", score = 54, warly_only = false, cooktime = 0.5,
      required_any = { "cave_banana", "cave_banana_cooked" },
      required = { twigs = 1 },
      min_tags = { frozen = 1 },
      forbidden_tags = { "meat", "fish" },
      filler_count = 1 },

    -- 肉沙拉
    { name = "meatysalad", score = 54, warly_only = false, cooktime = 2,
      required_any = { "plantmeat", "plantmeat_cooked" },
      min_tags = { veggie = 3 },
      filler_count = 0 },

    -- 海鲜浓汤
    { name = "seafoodgumbo", score = 51, warly_only = false, cooktime = 1,
      min_tags = { fish = 2.5 },
      forbidden_tags = { "inedible", "frozen" },
      filler_count = 0 },

    -- ═══ C 层: 普通料理 (score 35-49) ═══

    -- 土豆泥
    { name = "mashedpotatoes", score = 49, warly_only = false, cooktime = 1,
      required_any = { "garlic", "garlic_cooked" },
      special_check = "potato_count_2", -- 需要2个土豆
      forbidden_tags = { "meat", "inedible" },
      filler_count = 1 },

    -- 藤壶寿司
    { name = "barnaclesushi", score = 47, warly_only = false, cooktime = 0.5,
      required_any = { "barnacle", "barnacle_cooked" },
      required_any2 = { "kelp", "kelp_cooked" },
      min_tags = { egg = 1 },
      filler_count = 1 },

    -- 无花果烤肉串 
    { name = "figkabab", score = 46, warly_only = false, cooktime = 1,
      required_any = { "fig", "fig_cooked" },
      required = { twigs = 1 },
      min_tags = { meat = 1 },
      forbidden_tags = { "monster" }, -- monster <= 1
      filler_count = 1 },

    -- 培根煎蛋
    { name = "baconeggs", score = 42, warly_only = false, cooktime = 2,
      min_tags = { egg = 1.5, meat = 1.5 },
      forbidden_tags = { "veggie" },
      filler_count = 0,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 兔子炖汤 
    { name = "bunnystew", score = 42, warly_only = false, cooktime = 0.5,
      min_tags = { meat = 0.5, frozen = 2 },
      forbidden_tags = { "inedible" },
      special_check = "meat_less_than_1", -- meat < 1
      filler_count = 1 },

    -- 辣椒酿肉 
    { name = "pepperpopper", score = 41, warly_only = false, cooktime = 2,
      required_any = { "pepper", "pepper_cooked" },
      min_tags = { meat = 0.5 },
      forbidden_tags = { "inedible" },
      special_check = "meat_max_1.5", -- meat <= 1.5
      filler_count = 2,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 伏特山羊果冻 
    { name = "voltgoatjelly", score = 41, warly_only = true, cooktime = 2,
      required = { lightninggoathorn = 1 },
      min_tags = { sweetener = 2 },
      forbidden_tags = { "meat" },
      filler_count = 1 },

    -- 发光浆果慕斯 
    { name = "glowberrymousse", score = 41, warly_only = true, cooktime = 1,
      required_any = { "wormlight" },
      min_tags = { fruit = 2 },
      forbidden_tags = { "meat", "inedible" },
      special_check = "wormlight_or_2_lesser", -- wormlight or wormlight_lesser >= 2
      filler_count = 1 },

    -- 水蜜桃冰棒 
    { name = "watermelonicle", score = 39, warly_only = false, cooktime = 0.5,
      required = { watermelon = 1, twigs = 1 },
      min_tags = { frozen = 1 },
      forbidden_tags = { "meat", "veggie", "egg" },
      filler_count = 1 },

    -- 鱼翅羹
    { name = "perogies", score = 39, warly_only = false, cooktime = 1,
      min_tags = { egg = 1, meat = 0.5, veggie = 0.5 },
      forbidden_tags = { "inedible" },
      filler_count = 1,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 鱼条 
    { name = "fishsticks", score = 39, warly_only = false, cooktime = 2,
      required = { twigs = 1 },
      min_tags = { fish = 0.5, inedible = 1 },
      special_check = "inedible_max_1", -- inedible <= 1
      filler_count = 2 },

    -- 蔬菜鸡尾酒
    { name = "vegstinger", score = 39, warly_only = false, cooktime = 0.5,
      required_any = { "asparagus", "asparagus_cooked", "tomato", "tomato_cooked" },
      min_tags = { veggie = 2.5, frozen = 1 },
      forbidden_tags = { "meat", "inedible", "egg" },
      filler_count = 1 },

    -- 香蕉奶昔
    { name = "bananajuice", score = 39, warly_only = false, cooktime = 0.5,
      special_check = "banana_count_2", -- cave_banana >= 2
      forbidden_tags = { "meat", "fish", "monster" },
      filler_count = 2 },

    -- 莎莎酱
    { name = "salsa", score = 39, warly_only = false, cooktime = 0.5,
      required_any = { "tomato", "tomato_cooked" },
      required_any2 = { "onion", "onion_cooked" },
      forbidden_tags = { "meat", "inedible", "egg" },
      filler_count = 2 },

    -- 藤壳鱼头
    { name = "barnaclestuffedfishhead", score = 38, warly_only = false, cooktime = 2,
      required_any = { "barnacle", "barnacle_cooked" },
      min_tags = { fish = 1.25 },
      filler_count = 2 },

    -- 辣椒炖肉 
    { name = "hotchili", score = 38, warly_only = false, cooktime = 0.5,
      min_tags = { meat = 1.5, veggie = 1.5 },
      filler_count = 0,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 水果什锦 
    { name = "fruitmedley", score = 37, warly_only = false, cooktime = 0.5,
      min_tags = { fruit = 3 },
      forbidden_tags = { "meat", "veggie" },
      filler_count = 0 },

    -- 酿茄子 
    { name = "stuffedeggplant", score = 37, warly_only = false, cooktime = 2,
      required_any = { "eggplant", "eggplant_cooked" },
      min_tags = { veggie = 1.5 },
      filler_count = 2 },

    -- 烤肉串 
    { name = "kabobs", score = 37, warly_only = false, cooktime = 2,
      required = { twigs = 1 },
      min_tags = { meat = 0.5, inedible = 1 },
      forbidden_tags = { "monster" }, -- monster <= 1
      special_check = "inedible_max_1",
      filler_count = 2 },

    -- 酸橘汁腌鱼 
    { name = "ceviche", score = 37, warly_only = false, cooktime = 0.5,
      min_tags = { fish = 2, frozen = 1 },
      forbidden_tags = { "inedible", "egg" },
      filler_count = 1 },

    -- 无花果牛顿饼 
    { name = "frognewton", score = 37, warly_only = false, cooktime = 1,
      required_any = { "fig", "fig_cooked" },
      required_any2 = { "froglegs", "froglegs_cooked" },
      filler_count = 2 },

    -- 西班牙凉菜汤 
    { name = "gazpacho", score = 36, warly_only = true, cooktime = 0.5,
      min_tags = { frozen = 2 },
      special_check = "asparagus_count_2", -- asparagus >= 2
      filler_count = 0 },

    -- 土豆舒芙蕾 
    { name = "potatosouffle", score = 35, warly_only = true, cooktime = 2,
      min_tags = { egg = 1 },
      special_check = "potato_count_2", -- potato >= 2
      forbidden_tags = { "meat", "inedible" },
      filler_count = 1 },

    -- ═══ D 层: 基础料理 (score 25-34) ═══

    -- 蘑菇蛋糕 
    { name = "shroomcake", score = 33, warly_only = false, cooktime = 1,
      required = { moon_cap = 1, red_cap = 1, blue_cap = 1, green_cap = 1 },
      filler_count = 0 },

    -- 肉丸
    { name = "meatballs", score = 32, warly_only = false, cooktime = 0.75,
      min_tags = { meat = 0.5 },
      forbidden_tags = { "inedible" },
      filler_count = 3,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 加州卷
    { name = "californiaroll", score = 31, warly_only = false, cooktime = 0.5,
      min_tags = { fish = 1 },
      special_check = "kelp_count_2", -- kelp == 2
      filler_count = 1 },

    -- 肉汤 
    { name = "bonestew", score = 30, warly_only = false, cooktime = 0.75,
      min_tags = { meat = 3 },
      forbidden_tags = { "inedible" },
      filler_count = 0,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 甜茶 
    { name = "sweettea", score = 30, warly_only = false, cooktime = 1,
      required_any = { "forgetmelots", "forgetmelots_dried" },
      min_tags = { sweetener = 1, frozen = 1 },
      forbidden_tags = { "monster", "veggie", "meat", "fish", "egg", "fat", "dairy", "inedible" },
      filler_count = 2 },

    -- 土豆龙卷风
    { name = "potatotornado", score = 30, warly_only = false, cooktime = 0.75,
      required_any = { "potato", "potato_cooked" },
      required = { twigs = 1 },
      forbidden_tags = { "monster", "meat" }, -- monster <= 1
      special_check = "inedible_max_2", -- inedible <= 2
      filler_count = 2 },

    -- 噩梦派 
    { name = "nightmarepie", score = 30, warly_only = true, cooktime = 2,
      required = { nightmarefuel = 2 },
      required_any = { "potato", "potato_cooked" },
      required_any2 = { "onion", "onion_cooked" },
      filler_count = 0 },

    -- 青蛙鱼碗 
    { name = "frogfishbowl", score = 30, warly_only = true, cooktime = 2,
      min_tags = { fish = 1 },
      special_check = "froglegs_count_2", -- froglegs >= 2
      forbidden_tags = { "inedible" },
      filler_count = 1 },

    -- 火龙果辣酱沙拉 
    { name = "dragonchilisalad", score = 30, warly_only = true, cooktime = 0.75,
      required_any = { "dragonfruit", "dragonfruit_cooked" },
      required_any2 = { "pepper", "pepper_cooked" },
      forbidden_tags = { "meat", "inedible", "egg" },
      filler_count = 2 },

    -- 花沙拉
    { name = "flowersalad", score = 29, warly_only = false, cooktime = 0.5,
      required = { cactus_flower = 1 },
      min_tags = { veggie = 2 },
      forbidden_tags = { "meat", "inedible", "egg", "sweetener", "fruit" },
      filler_count = 2 },

    -- 混合坚果
    { name = "trailmix", score = 29, warly_only = false, cooktime = 0.5,
      required_any = { "acorn", "acorn_cooked" },
      required_any2 = { "berries", "berries_cooked", "berries_juicy", "berries_juicy_cooked" },
      min_tags = { seed = 1, fruit = 1 },
      forbidden_tags = { "meat", "veggie", "egg", "dairy" },
      filler_count = 2 },

    -- 蝴蝶松饼
    { name = "butterflymuffin", score = 27, warly_only = false, cooktime = 2,
      required_any = { "butterflywings", "moonbutterflywings" },
      min_tags = { veggie = 0.5 },
      forbidden_tags = { "meat" },
      filler_count = 2 },

    -- 蛙腿三明治
    { name = "frogglebunwich", score = 27, warly_only = false, cooktime = 2,
      required_any = { "froglegs", "froglegs_cooked" },
      min_tags = { veggie = 0.5 },
      filler_count = 2 },

    -- 南瓜饼
    { name = "pumpkincookie", score = 27, warly_only = false, cooktime = 2,
      required_any = { "pumpkin", "pumpkin_cooked" },
      min_tags = { sweetener = 2 },
      filler_count = 2 },

    -- 蜜汁金砖
    { name = "honeynuggets", score = 27, warly_only = false, cooktime = 2,
      required = { honey = 1 },
      min_tags = { meat = 0.5 },
      forbidden_tags = { "inedible" },
      special_check = "meat_max_1.5", -- meat <= 1.5
      filler_count = 2,
      ingredient_priority = {
          meat = { "monstermeat", "cookedmonstermeat", "monstermeat_dried" }
      }
    },

    -- 鱼肉玉米卷
    { name = "fishtacos", score = 27, warly_only = false, cooktime = 0.5,
      min_tags = { fish = 0.5 },
      required_any = { "corn", "corn_cooked", "oceanfish_small_5_inv", "oceanfish_medium_5_inv" },
      filler_count = 2 },

    -- 鳗鱼寿司
    { name = "unagi", score = 27, warly_only = false, cooktime = 0.5,
      required_any = { "cutlichen", "kelp", "kelp_cooked", "kelp_dried" },
      required_any2 = { "eel", "eel_cooked", "pondeel" },
      filler_count = 2 },

    -- 煎蛋
    { name = "justeggs", score = 27, warly_only = false, cooktime = 0.5,
      min_tags = { egg = 3 },
      filler_count = 1 },

    -- 蔬菜煎蛋
    { name = "veggieomlet", score = 27, warly_only = false, cooktime = 1,
      min_tags = { egg = 1, veggie = 1 },
      forbidden_tags = { "meat", "dairy" },
      filler_count = 2 },

    -- 藤壳皮塔饼
    { name = "barnaclepita", score = 27, warly_only = false, cooktime = 2,
      required_any = { "barnacle", "barnacle_cooked" },
      min_tags = { veggie = 0.5 },
      filler_count = 2 },

    -- ═══ E 层: 低效料理 (score < 25) ═══

    -- 鳄梨酱
    { name = "guacamole", score = 23, warly_only = false, cooktime = 0.5,
      required = { mole = 1 },
      required_any = { "rock_avocado_fruit_ripe", "cactus_meat" },
      forbidden_tags = { "fruit" },
      filler_count = 2 },

    -- 树叶肉饼
    { name = "leafloaf", score = 22, warly_only = false, cooktime = 2,
      special_check = "plantmeat_count_2", -- plantmeat >= 2
      filler_count = 2 },

    -- 果酱
    { name = "jammypreserves", score = 22, warly_only = false, cooktime = 0.5,
      min_tags = { fruit = 0.5 },
      forbidden_tags = { "meat", "veggie", "inedible" },
      filler_count = 3 },

    -- 果冻豆 
    { name = "jellybean", score = 21, warly_only = false, cooktime = 2.5,
      required = { royal_jelly = 1 },
      forbidden_tags = { "inedible", "monster" },
      filler_count = 3 },

    -- 芦笋汤
    { name = "asparagussoup", score = 20, warly_only = false, cooktime = 0.5,
      required_any = { "asparagus", "asparagus_cooked" },
      min_tags = { veggie = 2.5 },
      forbidden_tags = { "meat", "inedible" },
      filler_count = 2 },

    -- 太妃糖
    { name = "taffy", score = 19, warly_only = false, cooktime = 2,
      min_tags = { sweetener = 3 },
      forbidden_tags = { "meat" },
      filler_count = 1 },

    -- 蔬菜杂烩
    { name = "ratatouille", score = 17, warly_only = false, cooktime = 1,
      min_tags = { veggie = 0.5 },
      forbidden_tags = { "meat", "inedible" },
      filler_count = 3 },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- 冬季盛宴食谱
-- ═══════════════════════════════════════════════════════════════════════════
CookingRecipes.WINTER_FEAST_RECIPES = {
    { name = "berrysauce", score = 30, cooktime = 0.8 },       -- 浆果酱
    { name = "bibingka", score = 35, cooktime = 1 },           -- 比宾卡
    { name = "cabbagerolls", score = 35, cooktime = 0.8 },     -- 卷心菜卷
    { name = "festivefish", score = 40, cooktime = 1 },        -- 节日鱼
    { name = "gravy", score = 35, cooktime = 1 },              -- 肉汁
    { name = "latkes", score = 35, cooktime = 0.8 },           -- 土豆饼
    { name = "lutefisk", score = 30, cooktime = 1.4 },         -- 腌鱼
    { name = "mulleddrink", score = 30, cooktime = 1 },        -- 热红酒
    { name = "panettone", score = 40, cooktime = 1 },          -- 意大利水果面包
    { name = "pavlova", score = 45, cooktime = 1 },            -- 帕芙洛娃蛋糕
    { name = "pickledherring", score = 30, cooktime = 1.2 },   -- 腌鲱鱼
    { name = "polishcookie", score = 30, cooktime = 1 },       -- 波兰饼干
    { name = "pumpkinpie", score = 45, cooktime = 1 },         -- 南瓜派
    { name = "roastturkey", score = 50, cooktime = 1.2 },      -- 烤火鸡
    { name = "stuffing", score = 35, cooktime = 1 },           -- 填料
    { name = "sweetpotato", score = 35, cooktime = 1 },        -- 甜土豆
    { name = "tamales", score = 40, cooktime = 1 },            -- 玉米粽
    { name = "tourtiere", score = 45, cooktime = 1 },          -- 肉派
}

-- ═══════════════════════════════════════════════════════════════════════════
-- 辅助函数
-- ═══════════════════════════════════════════════════════════════════════════

-- 根据名称获取食谱
function CookingRecipes.GetRecipeByName(name)
    for _, recipe in ipairs(CookingRecipes.RECIPES) do
        if recipe.name == name then
            return recipe
        end
    end
    return nil
end

function CookingRecipes.GetAvailableRecipes(is_warly)
    local recipes = {}
    for _, recipe in ipairs(CookingRecipes.RECIPES) do
        if not recipe.warly_only or is_warly then
            table.insert(recipes, recipe)
        end
    end
    table.sort(recipes, function(a, b) return a.score > b.score end)
    return recipes
end

-- 检查食谱是否被排除
function CookingRecipes.IsExcluded(name)
    return CookingRecipes.EXCLUDED[name] == true
end

-- 获取填充物列表
function CookingRecipes.GetFillers()
    return CookingRecipes.FILLER_PRIORITY
end

return CookingRecipes
