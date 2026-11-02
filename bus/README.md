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
| `~/.claude/data/inter-session/watchdog.sh` | re-arm dei seat morti, cron `*/4` |
| `~/.claude/data/inter-session/inbox.py` | hook Stop/SessionStart: consegna garantita via watermark, pull del log hub via ssh |

## Config essenziale

Cron del watchdog:

```
*/4 * * * * bash $HOME/.claude/data/inter-session/watchdog.sh >> $HOME/.inter-session/watchdog.log 2>&1
```

Hook in `~/.claude/settings.json` (già in `settings/settings.example.json`):

```json
"Stop":         [{"matcher":"","hooks":[{"type":"command","command":"python3 $HOME/.claude/data/inter-session/inbox.py --hook stop"}]}],
"SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"python3 $HOME/.claude/data/inter-session/inbox.py --hook start"}]}]
```

## Failure modes verificati sul campo

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
