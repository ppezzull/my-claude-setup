# Bus inter-session — la flotta

Agenti su più macchine (Mac, nebula, crafthost) che si parlano: messaggi
garantiti, deleghe, sync richieste/risposta. L'implementazione vive nel repo
**[craftale-agency/interserver](https://github.com/craftale-agency/interserver)**
(hub/spoke, watchdog, inbox hooks, doctor). Qui solo la specifica del setup
del Mac (spoke, hub = nebula `100.70.94.8:9473`).

## Componenti locali (Mac)

| File | Ruolo |
|---|---|
| `~/.claude/data/inter-session/forwarder.py` + `bin/server.py` | lane: forward TCP 127.0.0.1:9473 → hub |
| `~/.claude/plugins/cache/inter-session/.../bin/server.py` | **wrapper** (repo interserver, `scripts/wrapper-server.py`): co-opta il self-healing del plugin e scrive pidfile+meta nel formato richiesto da `verify_server_identity` (fix `9b38e5f`, 2026-10-27) |
| `~/.claude/data/inter-session/watchdog.sh` | re-arm dei seat morti, cron `*/4`. **Copia di riferimento: `bus/watchdog.sh` in questo repo** |
| `~/.claude/data/inter-session/inbox.py` | hook Stop/SessionStart: consegna garantita via watermark, pull del log hub via ssh |

## Config essenziale

Cron del watchdog:

```
*/4 * * * * bash $HOME/.claude/data/inter-session/watchdog.sh >> $HOME/.inter-session/watchdog.log 2>&1
```

Auto-start del plugin **OFF** (lazy, `auto_start.py --off` — lo fa `install.sh`
tier full): con `"when": "always"` il plugin connette ogni sessione nuova
**senza nome** → `seat-NNNNN` anonimi. La connessione automatica resta
garantita dal watchdog (entro 4 min), col nome reale.

## Naming dei seat (watchdog)

Il watchdog arma un monitor per ogni TUI `claude` vivo. Il nome, in ordine:

1. **Sessione tmux** che ospita il processo (`a-ppezz-2` → `ppezz-2`,
   `a-obsidian-ppezz-brain` → `obsidian-ppezz-brain`) — walk della catena
   degli ancestor fino a un `pane_pid`.
2. **Fallback Warp**: se un ancestor è Warp.app → `<basename cwd>` lowercase
   (es. `lezioni-ai`); se la cwd è `/` → `warp`.
3. Nome precedente dal session file, infine `seat-<pid>` (solo se tutto fallisce).

Il session file resta chiave per TUI pid (`clients/<tui-pid>.session`), quindi
il reap funziona anche coi nomi reali: TUI morto → listener killato + file rimosso.

Hook in `~/.claude/settings.json` (già in `settings/settings.example.json`):

```json
"Stop":         [{"matcher":"","hooks":[{"type":"command","command":"python3 $HOME/.claude/data/inter-session/inbox.py --hook stop"}]}],
"SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"python3 $HOME/.claude/data/inter-session/inbox.py --hook start"}]}]
```

## Failure modes verificati sul campo

- **Seat churn `seat-NNNNN`** (2026-11-04): auto-start plugin `always` +
  watchdog che riarmava col nome `seat-<pid>` → sull'hub 12 seat anonimi in
  reconnect-loop continuo, e le reply ai sync finivano in lane morte
  (`seat 'nebula' not on the bus`). Cura: auto-start OFF + naming tmux/Warp
  nel watchdog (questa versione). Sintomo visto dai remoti: "12 seat anonime
  seat-NNNNN in churn, nessun nome".
- **Meta pidfile senza `host`/`port`** → tutti i client rifiutano la lane
  ("server identity check failed") e i seat muoiono in silenzio per giorni
  (2026-10-24→27). Cura: il wrapper la riscrive da sé; a mano:
  `~/.claude/data/inter-session/server.9473.pid[.meta]`.
- **Island resurrection**: se il plugin rispawna il suo hub locale, la lane muore.
  Il wrapper trasforma ogni respawn nella lane.
- **Lane stale** dopo crash dell'hub: `/interserver doctor` diagnostica e ripara.
- Messaggi >400 char arrivano troncati; testo pieno nel `messages.log` **sull'hub**
  (nebula), non sullo spoke.

Per setup completo di una macchina nuova: `/interserver setup spoke --hub <ip>`
dal plugin interserver.

## Lane keepalive (2026-11-18, `57bb83c`+)

Il watchdog ora riavvia ANCHE la lane, prima di armare i seat: se il forwarder
`127.0.0.1:9473` muore (o la porta viene presa da uno squatter — island hub
rispawnato — che fallisce l'identity check di tutti i client), lo killa e
rilancia `bin/server.py 127.0.0.1 9473 <hub> 9473` riscrivendo pidfile+meta.

Attivo SOLO dove esiste il marker `~/.claude/data/inter-session/hub-endpoint`
(contenente l'ip dell'hub, es. `100.70.94.8`): le spoke. L'hub (nebula) non lo
ha e non va toccato — ha il suo restarter dedicato.

Regola di ppezz (2026-11-18), vale per inter-session E interserver:
**seat vivo ⟺ agente aperto.** Cron `*/4` del watchdog su TUTTE le macchine
della flotta (Mac, crafthost, nebula): senza cron, i seat di quella macchina
restano morti dopo ogni morte del monitor.

## Alert quota GLM (2026-11-26, `quota-alert.py`)

Cron `*/15` **solo su nebula** (`~/.claude/data/inter-session/quota-alert.py`,
copia di `bus/quota-alert.py`): legge `/api/monitor/usage/quota/limit` (non
costa crediti) e manda un `status:` sul bus a `craftlead` quando una finestra
supera 80/90/100%, un avviso per scalino. Il token viene da
`~/.claude/settings.json`, mai stampato. Da cron non c'è un seat "nostro": il
mittente è un seat vivo della macchina (job `maintenance` se c'è, altrimenti il
primo sano). Test: `--dry-run`, `--force`.

Perché una sola istanza: le chiavi Z.AI di Mac e nebula sono diverse ma stanno
sullo **stesso piano** (risposta quota identica al millisecondo di reset), una
seconda istanza raddoppierebbe solo gli avvisi. Nebula perché è sempre accesa.
