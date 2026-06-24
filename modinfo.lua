local _locale = locale or ""
local _is_pt = _locale == "pt" or _locale == "ptbr" or _locale == "br"
local _is_chinese = _locale == "zh" or _locale == "zhs" or _locale == "zht"
                 or _locale == "schinese" or _locale == "tchinese"

name = "Mordomo — Warly Chef Solo"
author = "HIKESS"
version = "1.0.0"

if _is_pt then
    description = [[Mordomo: Warly apenas como chefe de cozinha (NPC solo).
- Warly so cozinha (nao luta, nao equipa armas)
- Nao cria cozinha automatica (usa panelas/geladeiras do mundo)
- Guarda comida cozida na geladeira mais proxima (freezer prioritario)
- Menu com comandos Follow / Cook Here / Stop
Extraido dos mods NPC Friend + Admin Control (HIKESS/Mods).]]
elseif _is_chinese then
    description = [[Mordomo：仅作为厨师的沃利（单人 NPC mod）。
- 沃利只做饭（不战斗、不装备武器）
- 不自动创建厨房（使用世界中已有的锅/冰箱）
- 熟食存入最近的冰箱（freezer 优先）
- 菜单含 Follow / Cook Here / Stop 命令
从 NPC Friend + Admin Control (HIKESS/Mods) 提炼而来。]]
else
    description = [[Mordomo: Warly as a cooking-only solo NPC companion.
- Warly only cooks (no combat, no weapon equipping)
- Does NOT auto-create a kitchen (uses existing cookpots/fridges in the world)
- Stores cooked food in the nearest fridge (freezer priority)
- Menu with Follow / Cook Here / Stop commands
Extracted from the NPC Friend + Admin Control mods (HIKESS/Mods).]]
end

api_version = 10
dst_compatible = true
all_clients_require_mod = true
client_only_mod = false

icon_atlas = "modicon.xml"
icon = "modicon.tex"

forumthread = ""

configuration_options = {
    {
        name = "spawn_mode",
        label = _is_pt and "Modo de invocacao do Warly" or (_is_chinese and "Warly 召唤方式" or "Warly Spawn Mode"),
        hover = _is_pt and "auto = nasce perto do host no primeiro dia; manual = so via console/tecla"
              or (_is_chinese and "auto = 首日自动在主机旁生成；manual = 仅通过控制台/热键" or "auto = spawn near host on day 1; manual = console/hotkey only"),
        options = {
            { description = _is_pt and "Automatico" or (_is_chinese and "自动" or "Auto"),     data = "auto" },
            { description = _is_pt and "Manual" or (_is_chinese and "手动" or "Manual"),       data = "manual" },
        },
        default = "auto",
    },
    {
        name = "hotkey",
        label = _is_pt and "Tecla do menu" or (_is_chinese and "菜单热键" or "Menu Hotkey"),
        hover = _is_pt and "Tecla para abrir o menu Mordomo (Follow/Cook/Stop)"
              or (_is_chinese and "打开 Mordomo 菜单的按键" or "Key to open the Mordomo menu"),
        options = {
            { description = "M", data = "M" },
            { description = "N", data = "N" },
            { description = "B", data = "B" },
            { description = "V", data = "V" },
            { description = "J", data = "J" },
            { description = "K", data = "K" },
        },
        default = "M",
    },
    {
        name = "cook_range",
        label = _is_pt and "Alcance de cozinha" or (_is_chinese and "烹饪范围" or "Cook Range"),
        hover = _is_pt and "Raio (em blocos) que o Warly procura panelas e ingredientes"
              or (_is_chinese and "沃利寻找锅与食材的半径（格）" or "Radius (tiles) Warly searches for pots and ingredients"),
        options = {
            { description = "10", data = 10 },
            { description = "15", data = 15 },
            { description = "17", data = 17 },
            { description = "20", data = 20 },
            { description = "25", data = 25 },
            { description = "30", data = 30 },
        },
        default = 17,
    },
    {
        name = "cook_speed_mult",
        label = _is_pt and "Velocidade de cozinha" or (_is_chinese and "烹饪速度" or "Cook Speed"),
        hover = _is_pt and "Multiplicador de tempo de cozinha (0.5 = 2x mais rapido)"
              or (_is_chinese and "烹饪时间倍率（0.5 = 2 倍速）" or "Cook time multiplier (0.5 = 2x faster)"),
        options = {
            { description = "0.25 (4x)", data = 0.25 },
            { description = "0.5 (2x)",  data = 0.5 },
            { description = "0.75 (1.33x)", data = 0.75 },
            { description = "1.0 (1x)",  data = 1.0 },
        },
        default = 0.5,
    },
    {
        name = "debug",
        label = _is_pt and "Depuracao" or (_is_chinese and "调试" or "Debug"),
        hover = _is_pt and "Logs detalhados no console"
              or (_is_chinese and "在控制台输出详细日志" or "Verbose console logs"),
        options = {
            { description = _is_pt and "Desligado" or (_is_chinese and "关" or "Off"), data = false },
            { description = _is_pt and "Ligado" or (_is_chinese and "开" or "On"),    data = true },
        },
        default = false,
    },
}
