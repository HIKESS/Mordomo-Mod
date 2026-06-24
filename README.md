# Mordomo — Warly Chef Solo (DST Mod)

Um mod **solo e autossuficiente** para *Don't Starve Together* que traz o **Warly** como
NPC companheiro **apenas cozinheiro** — sem combate, sem equipar armas, sem criar cozinha
automática.

> Extraído e fundido a partir dos mods **NPC Friend** (`3684000581`) e **Admin Control**
> (`3678857150`) do repositório [HIKESS/Mods](https://github.com/HIKESS/Mods).

---

## ✨ O que este mod faz

- **Warly só cozinha.** Ele não luta, não equipa armas, não desvia para combate.
- **Não cria cozinha automaticamente.** Ao contrário do mod original (que criava
  cookpot + geladeira + 2 baús ao entrar no mundo), o Mordomo **não cria nada** —
  Warly usa as panelas e geladeiras que já existem no seu mundo.
- **Guarda comida na geladeira mais próxima (freezer prioritário).**
  Isto corrige o bug do mod original, onde o Warly guardava a comida cozida somente na
  geladeira que ele mesmo criava (e acabava guardando em baús quando ela não existia).
  Agora a busca é: **geladeira mais próxima com espaço → se nenhuma, baú mais próximo.**
- **Menu de comandos.** Pressione a tecla configurável (padrão **M**) para abrir o
  painel Mordomo:
  - **Follow** — Warly te segue
  - **Cook Here** — Warly cozinha nesta área (procura panelas/ingredientes/geladeiras)
  - **Stop Work** — Warly para de trabalhar
  - **Unfollow** — Dispensa Warly

---

## 🎮 Como usar

1. Instale o mod (coloque a pasta `Mordomo-Mod` na pasta `mods/` do DST).
2. Ative-o na tela de mods do servidor.
3. **Modo Automático (padrão):** Warly nasce perto do host no primeiro dia.
   **Modo Manual:** use o comando de console `c_spawn_warly()` para invocá-lo.
4. Coloque uma **panela de cozinha** (cookpot / portablecookpot) e uma **geladeira**
   (icebox) perto de onde quer que Warly trabalhe, e coloque ingredientes na geladeira/baú.
5. Pressione **M** → **Cook Here**. Warly vai planejar o melhor prato, pegar os
   ingredientes, cozinhar e guardar a comida na geladeira mais próxima.

---

## ⚙️ Configurações (modinfo)

| Opção | Padrão | Descrição |
|-------|--------|-----------|
| `spawn_mode` | `auto` | `auto` = nasce perto do host no 1º dia; `manual` = via console/tecla |
| `hotkey` | `M` | Tecla para abrir o menu Mordomo |
| `cook_range` | `17` | Raio (em blocos) que Warly procura panelas e ingredientes |
| `cook_speed_mult` | `0.5` | Multiplicador de tempo de cozinha (0.5 = 2x mais rápido) |
| `debug` | `off` | Logs detalhados no console |

---

## 📁 Estrutura

```
Mordomo-Mod/
├── modinfo.lua                         # Metadados + opções de config
├── modmain.lua                         # Entrada: prefabs, RPC, auto-spawn, hotkey
├── modicon.tex / modicon.xml
└── scripts/
    ├── mordomo/
    │   ├── tuning.lua                  # Constantes (Warly stats, cozinha, armazenamento)
    │   ├── speech.lua                  # Linhas de fala do Warly
    │   ├── commands.lua                # Handlers Follow / CookHere / StopWork / Unfollow
    │   ├── storage.lua                 # ★ Correção: freezer prioritário p/ guardar comida
    │   ├── cooking_planner.lua         # Planejador de receitas (reutilizado, legível)
    │   ├── cooking_ingredient_finder.lua
    │   ├── cooking_recipe_scorer.lua
    │   ├── cooking_recipes.lua
    │   └── structure_util.lua          # Busca de geladeiras/baús/panelas
    ├── prefabs/
    │   └── mordomo_warly.lua           # ★ NPC Warly (só cozinha, sem cozinha auto)
    ├── brains/
    │   └── mordomo_warly_brain.lua     # ★ Cérebro: cozinhar + seguir + idle (limpo, novo)
    ├── stategraphs/
    │   └── SGmordomo_warly.lua         # ★ Stategraph: idle/run/pickup/cook/give/...
    └── screens/
        └── mordomo_menu.lua            # ★ Painel de menu (UI do admin control)
```

Arquivos marcados com ★ são novos/reastruturados; os demais são reutilizados do mod
original (apenas com os `require` renomeados para o namespace `mordomo/`).

---

## 🔧 O que foi removido / alterado vs. mod original

| Item | Mod original | Mordomo |
|------|--------------|---------|
| Criação de cozinha (cookpot+icebox+2 baús) | ✅ ao entrar no mundo | ❌ removido |
| Combate / equipar armas | ✅ | ❌ removido (só cozinha) |
| Armazenamento de comida | geladeira própria do NPC (bug) | ★ geladeira mais próxima (freezer priority) |
| Menu admin (reviver, controlar tudo, etc.) | ✅ (admin control) | ❌ removido — só Follow + Cooking |
| Dependência entre mods | npc friend + admin control | ✅ nenhum (mod solo) |
| Outros 19 personagens NPC | ✅ | ❌ apenas Warly |

---

## 🌍 Idiomas

O mod detecta o idioma do DST e mostra descrições em **Português**, **Inglês** ou
**Chinês**. As falas do Warly estão em Português.

---

## 📝 Notas técnicas

- **Animações:** usa o banco `wilson` + build `warly` embutidos no DST (sem assets extras).
- **Pipeline de cozinha:** reutiliza o planejador de receitas original (legível, não
  ofuscado), que escolhe o prato de maior valor com base nos ingredientes disponíveis.
- **Correção do freezer:** em `storage.lua`, `StoreItem` ordena as geladeiras por
  distância ao centro de cozinha e tenta a mais próxima com espaço primeiro; só recorre
  a baús se nenhuma geladeira tiver espaço.
- **Cérebro novo:** o `mordomo_warly_brain.lua` é uma máquina de estados por tick
  (`DoPeriodicTask`), não usa a árvore de comportamento ofuscada do original.

---

## 🧪 Comandos de console (modo manual)

- `c_spawn_warly()` — invoca Warly perto de você
- `c_mordomo_despawn()` — remove todos os Warly do mundo

---

## 📜 Licença / Créditos

Derivado dos mods **NPC Friend** e **Admin Control** de [HIKESS/Mods](https://github.com/HIKESS/Mods).
Mantido por **HIKESS**.
