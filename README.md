# my-claude-setup

Il mio setup Claude Code "che non muore mai": agenti che sopravvivono alla
chiusura del tab e al riavvio del Mac, una statusline che mostra quanto
contesto e quota mi restano, e un bus che fa parlare le sessioni Claude tra
macchine diverse.

> Scritto per me stesso del futuro e per chiunque voglia copiarlo.
> Se una cosa qui dentro sembra ovvia: bene, deve esserlo.

## Le 3 regole (l'unica parte da ricordare)

1. **Partire** → `cd progetto && claude` — come sempre
2. **Andarsene** → chiudi il tab. L'agente continua a vivere dietro
3. **Tornare** → `cd progetto && claude` — ti riattacca al TUO agente, con tutto il contesto intatto

Tutto il resto è automatico:

- secondo terminale sulla stessa cartella → secondo agente (`a-<cartella>-1`)
- riavvio del Mac → accendi, aspetti ~10 secondi, regola 3 (tmux resuscita le sessioni da solo)

```
Warp (lavoro interattivo)          Mac (persistenza locale)
├─ cd progetto && claude  ────────► tmux server (demone, LaunchAgent al login)
│   (funzione zsh trasparente)        ├─ a-<cartella>     agente 1
│                                     ├─ a-<cartella>-1   agente 2 (parallelo)
│   chiudi il tab = detach            └─ continuum: auto-save 15' + auto-restore
│                                     └─ reboot → panes ripartono con claude -c
│
└─ HUD (statusline)                    Bus inter-session (hub su nebula :9473)
    glm-wrapper.ts → claude-hud fork   ├─ Mac (watchdog nomina i seat da tmux)
    quota GLM + context sintetizzato   └─ nebula / crafthost, deleghe via sync
```

## Cosa serve

- macOS o Linux (Windows: passare da WSL2)
- Claude Code installato
- Per il tier full: più macchine nello stesso tailnet (Tailscale)

## Cosa c'è dentro

| Cartella | Cosa fa | Dettagli |
|---|---|---|
| `tmux/` | tiene in vita gli agenti: conf, boot script, LaunchAgent/systemd | [tmux/README](tmux/README.md) |
| `zsh/` | la funzione `claude()` — fa sembrare tutto normale | [zsh/README](zsh/README.md) |
| `hud/` | statusline: quota GLM + sintesi contesto | [hud/README](hud/README.md) |
| `bus/` | le sessioni si parlano tra macchine | [bus/README](bus/README.md) |
| `settings/` | settings d'esempio per flavor `anthropic` e `glm` (mai secret veri) | — |

## Install

```bash
git clone git@github.com:ppezzull/my-claude-setup.git
cd my-claude-setup
./install.sh        # medium + anthropic (default)
```

**Tier** (quanto installare):

| Tier | Cosa ottieni |
|---|---|
| `--minimal` | agenti persistenti (tmux + funzione `claude()`) |
| `--medium` | + statusline HUD |
| `--full` | + bus inter-session (poi: `/interserver setup spoke --hub <ip>`) |

**Flavor** (con quale Claude):

| Flavor | Endpoint | Statusline |
|---|---|---|
| `--anthropic` *(default)* | ufficiale Anthropic (login o API key) | renderer diretto, nessun wrapper |
| `--glm` | piano GLM (z.ai) | wrapper con quota del piano |

Senza flag, l'installer **auto-detecta**: se il tuo `~/.claude/settings.json`
esistente punta a GLM, sceglie `glm`; altrimenti `anthropic`. Forzare:
`./install.sh --glm` oppure `make medium ARGS=--glm`.

L'installer è **idempotente**: rilanciarlo non rompe nulla.
I secret non sono nel repo — si riempiono i placeholder a mano
(`settings/settings.example.anthropic.json` o `.glm.json` come riferimento).

Shortcut: `make minimal | medium | full | verify | update`
(`update` = `git pull` su tutto lo stack; i symlink fanno il deploy da soli).

## Problemi noti (e la cura)

- **MCP "npx" morti dentro le sessioni tmux dopo il boot** → il boot script
  parte con ambiente minimale: il PATH esplicito dentro `tmux-agents-boot.sh`
  è quello che li tiene in vita. Non toglierlo.
- **Dopo un reboot il bus non si riconnette da solo** → `/interserver doctor`
  diagnostica e ripara (cancella il pidfile stale e rilancia la lane).
- **Seat con nomi strani (`seat-12345`) sull'hub** → il watchdog nomina i seat
  dalle sessioni tmux (`a-ppezz-2` → `ppezz-2`); se vedi nomi numerici, il
  lookup tmux è fallito e ha usato il fallback. Ignora, o riarmo con il watchdog.
- **Agente che non risponde dopo il riavvio** → dai a tmux 10 secondi per il
  restore, poi regola 3.

## Principi

- Stesso comando di sempre: zero comandi tmux da ricordare
- Spostamenti, mai cancellazioni: ogni operazione loggata
- Secret solo come riferimento al gestore, mai valori nei file
- Fork > upstream quando l'upstream manca di funzioni
- Il bus e l'HUD vivono nei loro repo; qui c'è la colla
