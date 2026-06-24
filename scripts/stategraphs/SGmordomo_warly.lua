-- scripts/stategraphs/SGmordomo_warly.lua
-- Mordomo-Mod Warly 专用状态图（精简版，仅厨师动作，无战斗/砍挖等）
-- ────────────────────────────────────────────────────────────
-- 设计：使用玩家角色标准动画名（idle_loop / run_loop / pickup / give 等），
-- anim bank = "wilson"，build = "warly"（均随 DST 内置）。
-- 状态：idle / run / pickup / cookaction / give / talk / refuseeat / frozen / death
-- 移动由 locomotor 推送的 "locomote" 事件驱动（标准 DST 模式）。

local State = State
local EventHandler = EventHandler
local TimeEvent = TimeEvent
local FRAMES = FRAMES

local SG = {}

local function GetAnim(inst, default_anim, override_bank)
    return inst.AnimState:GetCurrentAnimationLength()
end

-- 标准 locomote 事件处理：在非忙碌状态下，根据 locomotor 意图切换 idle↔run
local function HandleLocomote(inst)
    if inst.sg:HasStateTag("busy") or inst.sg:HasStateTag("dead") then
        return
    end
    local locomotor = inst.components.locomotor
    if locomotor == nil then return end
    if locomotor:WantsToMoveForward() then
        if not inst.sg:HasStateTag("moving") then
            inst.sg:GoToState("run")
        end
    else
        if not inst.sg:HasStateTag("idle") then
            inst.sg:GoToState("idle")
        end
    end
end

local actionhandlers = {}

local events = {
    EventHandler("locomote", HandleLocomote),
    EventHandler("freeze", function(inst)
        if not inst.sg:HasStateTag("busy") then
            inst.sg:GoToState("frozen")
        end
    end),
    EventHandler("attacked", function(inst)
        -- 厨师不战斗，受击仅播放受击动画后回 idle（若未在忙碌态）
        if not inst.sg:HasStateTag("busy") and not inst.sg:HasStateTag("nointerrupt") then
            inst.sg:GoToState("hit")
        end
    end),
    EventHandler("death", function(inst)
        inst.sg:GoToState("death")
    end),
    EventHandler("doaction", function(inst, data)
        if not inst.sg:HasStateTag("busy") and data and data.state then
            inst.sg:GoToState(data.state, data)
        end
    end),
}

local states = {
    -- ── idle ──────────────────────────────────────────────
    State({
        name = "idle",
        tags = { "idle", "canrotate" },
        onenter = function(inst, pushanim)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("idle_loop", true)
        end,
        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── run（locomotor 驱动的移动）────────────────────────
    State({
        name = "run",
        tags = { "moving", "canrotate" },
        onenter = function(inst)
            inst.components.locomotor:RunForward()
            inst.AnimState:PlayAnimation("run_loop", true)
        end,
        events = {
            EventHandler("animover", function(inst)
                -- 动画循环时重新检查 locomotor 意图，避免卡在 run
                HandleLocomote(inst)
            end),
        },
    }),

    -- ── walk（慢走，保留兼容；默认走 run）─────────────────
    State({
        name = "walk",
        tags = { "moving", "canrotate" },
        onenter = function(inst)
            inst.components.locomotor:WalkForward()
            inst.AnimState:PlayAnimation("walk_loop", true)
        end,
        events = {
            EventHandler("animover", function(inst)
                HandleLocomote(inst)
            end),
        },
    }),

    -- ── hit（受击，厨师不还手）────────────────────────────
    State({
        name = "hit",
        tags = { "hit", "busy" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("hit")
        end,
        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── pickup（从容器/地面取物品）────────────────────────
    State({
        name = "pickup",
        tags = { "doing", "busy", "nointerrupt" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("pickup")
        end,
        timeline = {
            TimeEvent(6 * FRAMES, function(inst)
                -- 在动画中点执行实际取物（由 brain 在进入此状态前缓冲动作）
                if inst._do_pickup_fn then
                    inst._do_pickup_fn(inst)
                    inst._do_pickup_fn = nil
                end
            end),
        },
        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── cookaction（在锅前烹饪/搅锅）──────────────────────
    State({
        name = "cookaction",
        tags = { "doing", "busy", "nointerrupt" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("dolongaction")
        end,
        timeline = {
            TimeEvent(10 * FRAMES, function(inst)
                if inst._do_cook_fn then
                    inst._do_cook_fn(inst)
                    inst._do_cook_fn = nil
                end
            end),
        },
        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── give（把食物存入冰箱/箱子）────────────────────────
    State({
        name = "give",
        tags = { "doing", "busy", "nointerrupt" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("give")
        end,
        timeline = {
            TimeEvent(8 * FRAMES, function(inst)
                if inst._do_give_fn then
                    inst._do_give_fn(inst)
                    inst._do_give_fn = nil
                end
            end),
        },
        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── refuseeat（拒绝/命令失败的反馈）──────────────────
    State({
        name = "refuseeat",
        tags = { "busy" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("refuseeat")
        end,
        events = {
            EventHandler("animover", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── frozen（被冰冻）──────────────────────────────────
    State({
        name = "frozen",
        tags = { "busy", "frozen" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("frozen")
        end,
        events = {
            EventHandler("onthaw", function(inst)
                inst.sg:GoToState("idle")
            end),
        },
    }),

    -- ── death（死亡）─────────────────────────────────────
    State({
        name = "death",
        tags = { "dead", "busy" },
        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst.AnimState:PlayAnimation("death")
            inst:RemoveTag("mordomo_npc")
            if inst.components.health then
                inst.components.health:SetInvincible(true)
            end
        end,
    }),
}

return StateGraph("SGmordomo_warly", states, events, "idle", actionhandlers)
