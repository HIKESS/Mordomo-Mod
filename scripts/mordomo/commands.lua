-- scripts/mordomo/commands.lua
-- Mordomo-Mod 命令处理 —— 从 NPCFriends/admin control 提炼的 Follow + Cooking
-- ────────────────────────────────────────────────────────────
-- 命令列表（菜单仅暴露这 3 个，对应 admin 菜单的 Follow / Cooking 两个功能）：
--   Follow    : 让 Warly 跟随玩家
--   Unfollow  : 解除跟随
--   CookHere  : 以 Warly 当前位置为烹饪中心，自动找锅/食材/存储
--   StopWork  : 停止烹饪，清空烹饪中心
--
-- 命令通过 modmain 注册的 "MordomoCommand" RPC 触发，
-- 参数格式："command|owner_userid:char_type:slot_index"

local Speech = require("mordomo/speech")
local TUNING = require("mordomo/tuning")

local MordomoCommands = {}

-- ════════════════════════════════════════════════════════════
--  辅助函数
-- ════════════════════════════════════════════════════════════

local function SayLine(npc, scene, fallback)
    if not npc or not npc.components or not npc.components.talker then return end
    local line = Speech.GetLine(scene, npc and npc.npc_character_type)
    if line == nil then line = fallback end
    if line then
        npc.components.talker:ShutUp()
        npc.components.talker:Say(line)
    end
end

local function SetUnrecruitedWander(npc)
    if not npc then return end
    if npc.components.locomotor then
        npc.components.locomotor:Stop()
    end
    if npc.components.follower then
        npc.components.follower:SetLeader(nil)
    end
    npc._owner_userid = nil
    if npc.owner_userid then
        npc.owner_userid:set("")
    end
    local x, _, z = npc.Transform:GetWorldPosition()
    if npc.components.knownlocations then
        npc.components.knownlocations:RememberLocation("home", Vector3(x, 0, z))
    end
    if npc.sg and not npc.sg:HasStateTag("dead") then
        npc.sg:GoToState("idle")
    end
end

local function ClearWorkCenter(npc)
    if not npc then return end
    npc._cooking_center = nil
end

-- ════════════════════════════════════════════════════════════
--  Follow：让 Warly 跟随玩家
-- ════════════════════════════════════════════════════════════
local function CmdFollow(player, target_npc)
    if not target_npc or not target_npc:IsValid() then return end

    -- 已在跟随该玩家：仅刷新 owner 记录
    local current_leader = target_npc.components.follower and target_npc.components.follower.leader
    if current_leader and current_leader.userid == player.userid then
        target_npc._owner_userid = player.userid
        if target_npc.owner_userid then
            target_npc.owner_userid:set(player.userid or "")
        end
        SayLine(target_npc, Speech.FOLLOW)
        return
    end

    -- 跟随人数上限检查
    local max_followers = TUNING.MAX_NPC_FOLLOWERS or 2
    local cur_count = 0
    if player.components.leader then
        cur_count = player.components.leader:CountFollowers("mordomo_npc")
    end
    if cur_count >= max_followers then
        SayLine(target_npc, Speech.RECRUIT_FULL)
        if target_npc.sg and target_npc.sg:HasStateTag("idle") then
            target_npc.sg:GoToState("refuseeat")
        end
        return
    end

    -- 切换为跟随：先停下当前工作
    ClearWorkCenter(target_npc)
    target_npc._work_paused = true

    if target_npc.components.follower then
        target_npc.components.follower:SetLeader(player)
        target_npc._owner_userid = player.userid
        if target_npc.owner_userid then
            target_npc.owner_userid:set(player.userid or "")
        end
    end

    SayLine(target_npc, Speech.FOLLOW)
end

-- ════════════════════════════════════════════════════════════
--  Unfollow：解除跟随
-- ════════════════════════════════════════════════════════════
local function CmdUnfollow(player, target_npc)
    if not target_npc or not target_npc:IsValid() then return end
    SetUnrecruitedWander(target_npc)
    target_npc._work_paused = true
    SayLine(target_npc, Speech.DISMISS)
end

-- ════════════════════════════════════════════════════════════
--  CookHere：以当前位置为烹饪中心开始做饭
-- ════════════════════════════════════════════════════════════
local function CmdCookHere(player, target_npc)
    if not target_npc or not target_npc:IsValid() then return end
    if not target_npc._is_warly then return end -- 仅 Warly 可烹饪

    target_npc._work_paused = false

    -- 烹饪时先解除跟随（原地工作）
    if target_npc.components.follower and target_npc.components.follower.leader then
        SetUnrecruitedWander(target_npc)
    end

    local nx, _, nz = target_npc.Transform:GetWorldPosition()
    target_npc._cooking_center = { x = nx, z = nz }

    -- 检查附近是否有锅
    local range = TUNING.COOK_RANGE_DEFAULT or 17
    local pots = TheSim:FindEntities(nx, 0, nz, range, { "stewer" })
    local has_pot = false
    for _, pot in ipairs(pots) do
        if pot:IsValid() and pot.components.stewer then
            has_pot = true
            break
        end
    end

    if has_pot then
        SayLine(target_npc, Speech.COOKING_START)
    else
        SayLine(target_npc, Speech.NO_COOKPOT)
    end
end

-- ════════════════════════════════════════════════════════════
--  StopWork：停止烹饪
-- ════════════════════════════════════════════════════════════
local function CmdStopWork(player, target_npc)
    if not target_npc or not target_npc:IsValid() then return end
    target_npc._work_paused = true
    ClearWorkCenter(target_npc)
    SetUnrecruitedWander(target_npc)
    SayLine(target_npc, Speech.STOP_WORK)
end

-- ════════════════════════════════════════════════════════════
--  命令分发表
-- ════════════════════════════════════════════════════════════
local HANDLERS = {
    Follow    = CmdFollow,
    Unfollow  = CmdUnfollow,
    CookHere  = CmdCookHere,
    StopWork  = CmdStopWork,
}

-- ════════════════════════════════════════════════════════════
--  主入口：HandleCommand
--  参数格式："command|owner_userid:char_type:slot_index"
-- ════════════════════════════════════════════════════════════
function MordomoCommands.HandleCommand(player, params_str)
    if not TheWorld.ismastersim then return end
    if not player or not params_str then return end

    local command, owner_param = params_str:match("^([^|]+)|(.+)$")
    if not command or not owner_param then return end

    local parts = {}
    for seg in owner_param:gmatch("[^:]+") do parts[#parts + 1] = seg end
    local owner_userid = parts[1]
    local char_type    = parts[2]   -- "warly"
    local slot_index   = tonumber(parts[3])

    -- 查找目标 NPC：优先 owner/leader 匹配，其次任意 mordomo NPC
    local target_npc = nil
    local fallback   = nil
    for _, ent in pairs(Ents) do
        if ent:IsValid() and ent:HasTag("mordomo_npc") then
            if fallback == nil then fallback = ent end
            local leader = ent.components.follower and ent.components.follower.leader
            local ent_owner = ent.owner_userid and ent.owner_userid:value()
            if (leader and leader.userid == owner_userid)
               or (ent_owner and ent_owner ~= "" and ent_owner == owner_userid) then
                target_npc = ent
                break
            elseif target_npc == nil then
                if (char_type and ent.npc_character_type == char_type) then
                    target_npc = ent
                end
            end
        end
    end
    target_npc = target_npc or fallback
    if not target_npc then return end

    -- 权限校验：owner / leader / 空闲 NPC 才可命令
    local leader = target_npc.components.follower and target_npc.components.follower.leader
    local actual_owner = target_npc._owner_userid
        or (target_npc.owner_userid and target_npc.owner_userid:value() ~= "" and target_npc.owner_userid:value())
        or nil
    local is_owner  = actual_owner and actual_owner ~= "" and actual_owner == player.userid
    local is_leader = leader and leader.userid == player.userid
    local npc_is_free = (actual_owner == nil or actual_owner == "") and leader == nil
    if not is_owner and not is_leader and not npc_is_free then
        -- Follow 命令允许抢占空闲 NPC，其余命令需要权限
        if not (command == "Follow" and leader == nil) then
            return
        end
    end

    local handler = HANDLERS[command]
    if handler then
        handler(player, target_npc)
    end
end

return MordomoCommands
