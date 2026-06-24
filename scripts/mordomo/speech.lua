-- scripts/mordomo/speech.lua
-- Mordomo-Mod Warly 台词表（精简版，仅厨师相关场景）
-- ────────────────────────────────────────────────────────────
-- 结构与原 NPCFriends 一致：每个场景为 { _default = "...", warly = "..." }
-- GetLine(scene_table, char_type) 优先取角色专属台词，否则取 _default。

local Speech = {}

Speech.FOLLOW = {
    _default = "Vamos cozinhar!",
    warly    = "Ah, finalmente! Vamos preparar algo delicioso, mon ami!",
}

Speech.DISMISS = {
    _default = "Tudo bem, ate logo.",
    warly    = "Como queira. Meu fogao estara esperando.",
}

Speech.GREET = {
    _default = "Ola!",
    warly    = "Bonjour! O Warly esta pronto para cozinhar!",
}

Speech.RECRUIT_FULL = {
    _default = "Nao posso acompanhar mais ninguem.",
    warly    = "Meus bracos estao ocupados demais para mais um mestre!",
}

Speech.NO_COOKPOT = {
    _default = "Nao vejo nenhuma panela por aqui.",
    warly    = "Mon ami, nao ha panela de cozinha por perto! Preciso de uma para trabalhar.",
}

Speech.NO_INGREDIENTS = {
    _default = "Faltam ingredientes.",
    warly    = "Mesmo um chef nao cozinha do nada! Preciso de ingredientes.",
}

Speech.COOKING_DONE = {
    _default = "Pronto!",
    warly    = "Voila! Mais um prato magnifico do chef Warly!",
}

Speech.COOKING_START = {
    _default = "Vou comecar a cozinhar.",
    warly    = "Deixa comigo! A cozinha eh o meu palco.",
}

Speech.STORE_FOOD = {
    _default = "Guardei a comida.",
    warly    = "Prato guardado na geladeira, bem fresquinho!",
}

Speech.IDLE = {
    _default = "...",
    warly    = "Que aroma delicioso... hmm, o que vou cozinhar agora?",
}

Speech.IDLE_UNRECRUITED = {
    _default = "...",
    warly    = "Warly esta a postos. Me chame se precisar de um chefe de cozinha!",
}

Speech.STOP_WORK = {
    _default = "Tudo bem, vou parar.",
    warly    = "Entendido. Vou descansar os utencilios por enquanto.",
}

Speech.EAT = {
    _default = "*nom nom*",
    warly    = "Mmm, nao esta mal... mas daria um toque de alecrim.",
}

Speech.REFUSE_FOOD = {
    _default = "Nao, obrigado.",
    warly    = "Nao, obrigado. Prefiro cozinhar a minha propria comida!",
}

--- 从台词表中取一行
--- @param scene table  场景台词表
--- @param char string  角色类型（"warly"）
--- @return string|nil
function Speech.GetLine(scene, char)
    if not scene then return nil end
    if char and scene[char] then return scene[char] end
    return scene._default
end

return Speech
