-- scripts/screens/mordomo_menu.lua
-- Mordomo-Mod 命令菜单（从 admin control 面板 UI 模式提炼）
-- ────────────────────────────────────────────────────────────
-- 一个轻量级 Screen 面板，包含 4 个按钮：Follow / Cook Here / Stop Work / Unfollow。
-- 由 modmain 注册的热键（默认 M）打开。
-- 点击按钮 → 向服务端发送 "Mordomo"/"Command" RPC → commands.lua 处理。
--
-- UI 结构沿用 admin control 的 AdminPanelScreen 模式：
--   · self:AddChild(Widget) 创建根节点（带屏幕居中锚点）
--   · 半透明黑色遮罩覆盖全屏，点击外部关闭
--   · 面板框架使用 DST 内置 scoreboard 纹理

local Screen      = GLOBAL.require("widgets/screen")
local Widget      = GLOBAL.require("widgets/widget")
local ImageButton = GLOBAL.require("widgets/imagebutton")
local Text        = GLOBAL.require("widgets/text")
local Image       = GLOBAL.require("widgets/image")

-- 菜单按钮定义（对应 commands.lua 的命令名）
local MENU_BUTTONS = {
    { label = "Follow (Seguir)",        cmd = "Follow",   desc = "Warly te segue" },
    { label = "Cook Here (Cozinhar)",   cmd = "CookHere", desc = "Warly cozinha nesta area" },
    { label = "Stop Work (Parar)",      cmd = "StopWork", desc = "Warly para de trabalhar" },
    { label = "Unfollow (Dispensar)",   cmd = "Unfollow", desc = "Dispensa Warly" },
}

--- 创建一个标准长按钮（沿用 admin control 的 carny 按钮样式）
local function MakeButton(parent, label, x, y, onclick)
    local btn = parent:AddChild(ImageButton(
        "images/global_redux.xml",
        "button_carny_long_normal.tex",
        "button_carny_long_hover.tex",
        "button_carny_long_disabled.tex",
        "button_carny_long_down.tex"
    ))
    btn:ForceImageSize(360, 42)
    btn:SetText(label)
    btn:SetFont(GLOBAL.CHATFONT)
    btn:SetTextSize(20)
    btn:SetPosition(x, y)
    btn:SetOnClick(onclick)
    btn.scale_on_focus = false
    return btn
end

MordomoMenu = GLOBAL.Class(Screen, function(self, owner)
    Screen._ctor(self, "MordomoMenu")
    self.owner = owner or GLOBAL.ThePlayer

    -- 半透明黑色遮罩（点击外部关闭）
    self.black = self:AddChild(Image("images/global.xml", "square.tex"))
    self.black:SetVRegPoint(GLOBAL.ANCHOR_MIDDLE)
    self.black:SetHRegPoint(GLOBAL.ANCHOR_MIDDLE)
    self.black:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
    self.black:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
    self.black:SetScaleMode(GLOBAL.SCALEMODE_FILLSCREEN)
    self.black:SetTint(0, 0, 0, 0.45)
    self.black.OnMouseButton = function(_, button, down)
        if not down then
            self:Close()
        end
        return true
    end

    -- 根节点（屏幕居中）
    self.root = self:AddChild(Widget("root"))
    self.root:SetVAnchor(GLOBAL.ANCHOR_MIDDLE)
    self.root:SetHAnchor(GLOBAL.ANCHOR_MIDDLE)
    self.root:SetScaleMode(GLOBAL.SCALEMODE_PROPORTIONAL)
    self.root:SetMaxPropUpscale(GLOBAL.MAX_HUD_SCALE)

    -- 面板容器
    self.panel = self.root:AddChild(Widget("panel"))

    -- 面板背景框
    self.panel_bg = self.panel:AddChild(Image("images/scoreboard.xml", "scoreboard_frame.tex"))
    self.panel_bg:ScaleToSize(520, 480)

    -- 关闭按钮
    self.close_btn = self.panel:AddChild(ImageButton("images/global_redux.xml", "close.tex"))
    self.close_btn:SetPosition(230, 210)
    self.close_btn:SetScale(0.55)
    self.close_btn:SetOnClick(function() self:Close() end)
    self.close_btn.scale_on_focus = false

    -- 标题
    self.title = self.panel:AddChild(Text(GLOBAL.UIFONT, 30, "Mordomo — Warly"))
    self.title:SetPosition(0, 200)
    self.title:SetColour(0.95, 0.85, 0.55, 1)

    -- 副标题
    self.subtitle = self.panel:AddChild(Text(GLOBAL.CHATFONT, 18, "Escolha um comando para o chefe"))
    self.subtitle:SetPosition(0, 165)
    self.subtitle:SetColour(0.8, 0.8, 0.8, 1)

    -- 按钮 + 描述
    local start_y = 120
    local step_y  = 75
    for i, def in ipairs(MENU_BUTTONS) do
        local y = start_y - (i - 1) * step_y
        MakeButton(self.panel, def.label, 0, y, function()
            self:SendCommand(def.cmd)
        end)
        local desc = self.panel:AddChild(Text(GLOBAL.CHATFONT, 15, def.desc))
        desc:SetPosition(0, y - 28)
        desc:SetColour(0.65, 0.65, 0.65, 1)
    end

    -- 底部提示
    self.hint = self.panel:AddChild(Text(GLOBAL.CHATFONT, 15, "M ou Esc para fechar"))
    self.hint:SetPosition(0, -210)
    self.hint:SetColour(0.55, 0.55, 0.55, 1)
end)

--- 发送命令到服务端
function MordomoMenu:SendCommand(cmd)
    local userid = self.owner and self.owner.userid or ""
    -- 参数格式："command|owner_userid:char_type:slot_index"
    local payload = string.format("%s|%s:warly:0", cmd, userid)
    local rpc = GLOBAL.GetModRPC and GLOBAL.GetModRPC("Mordomo", "Command")
    if rpc then
        GLOBAL.SendModRPCToServer(rpc, payload)
    end
    self:Close()
end

function MordomoMenu:Close()
    GLOBAL.TheFrontEnd:PopScreen()
end

function MordomoMenu:OnControl(control, down)
    if MordomoMenu._base.OnControl(self, control, down) then return true end
    -- Esc / 右键关闭
    if not down and (control == GLOBAL.CONTROL_CANCEL or control == GLOBAL.CONTROL_MENU_BACK) then
        self:Close()
        return true
    end
    return false
end

function MordomoMenu:OnBecomeActive()
    MordomoMenu._base.OnBecomeActive(self)
end

return MordomoMenu
