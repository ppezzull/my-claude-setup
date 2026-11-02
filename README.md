# my-claude-setup

Il mio setup Claude Code completo: agenti persistenti che sopravvivono a reboot e
chiusura tab, HUD con quota GLM, e bus inter-session per la flotta di macchine.

```
Warp (lavoro interattivo)          Mac (persistenza locale)
├─ cd progetto && claude  ────────► tmux server (demone, LaunchAgent al login)
│   (funzione zsh trasparente)        ├─ a-<cartella>     agente 1
│                                     ├─ a-<cartella>-2   agente 2 (parallelo)
│   chiudi il tab = detach            └─ continuum: auto-save 15' + auto-restore
│                                     └─ reboot → panes ripartono con claude -c
│
└─ HUD (statusline)                    Bus inter-session (hub su nebula :9473)
    glm-wrapper.ts → claude-hud fork   ├─ maintenance (Mac)   ├─ nebula / pezserv
    quota GLM + context sintetizzato   └─ crafthost          └─ deleghe via sync
```

## Le 3 regole d'uso (il 101)

1. **Partire**: `cd progetto && claude` — come sempre
2. **Andarsene**: chiudi il tab. L'agente continua dietro
3. **Tornare**: `cd progetto && claude` — ti riattacca al TUO agente, contesto intatto

Extra: secondo terminale sulla stessa cartella = secondo agente (`a-<dir>-2`),
automatico. Reboot del Mac: accendi, aspetti 10 secondi, regola 3.

## Componenti

| Cartella | Cosa | Dettagli |
|---|---|---|
| `tmux/` | tmux.conf (continuum+resurrect, restore `claude -c`), boot script, LaunchAgent | [tmux/README](tmux/README.md) |
| `zsh/` | funzione `claude()` — la trasparenza multi-sessione | [zsh/README](zsh/README.md) |
| `hud/` | wrapper [glm-claude-hud](https://github.com/ppezzull/glm-claude-hud) + fork [claude-hud](https://github.com/ppezzull/claude-hud) | [hud/README](hud/README.md) |
| `bus/` | federazione inter-session ([craftale-agency/interserver](https://github.com/craftale-agency/interserver)) | [bus/README](bus/README.md) |
| `settings/` | `settings.example.json` sanificato (env, hook, statusLine) | — |

## Install (Mac nuovo)

```bash
git clone git@github.com:ppezzull/my-claude-setup.git ~/Desktop/Personal/my-claude-setup
cd ~/Desktop/Personal/my-claude-setup && ./install.sh
```

L'installer è idempotente: si può rilanciare. I secret NON sono nel repo —
vedi `settings/settings.example.json` per i placeholder da riempire a mano.

## Principi del setup

- **Stesso comando di sempre**: zero comandi tmux da ricordare, tutto incapsulato
- **Spostamenti, mai cancellazioni**: ogni operazione loggata
- **Secret solo come riferimento al gestore**, mai valori nei file
- **Fork > upstream** quando l'upstream manca di funzioni (claude-hud rate_limits)
- Il bus e l'HUD sono already-documentati nei rispettivi repo; qui la colla
