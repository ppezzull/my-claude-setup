# tmux — persistenza degli agenti

Il server tmux è un demone: gli agenti non vivono nel terminale. Il LaunchAgent
lo avvia al login; `continuum` salva tutto ogni 15 minuti e lo ripristina al
boot del server; `resurrect` mappa il processo `claude` su `claude -c` così
ogni pane riprende la conversazione.

## File

| File | Destinazione | Cosa fa |
|---|---|---|
| `tmux.conf` | `~/.tmux.conf` | dracula theme + resurrect/continuum + `@resurrect-processes ' ~claude->claude -c'` |
| `tmux-agents-boot.sh` | `~/bin/` | avvia il server al login. **PATH esplicito**: launchd parte con ambiente minimale — senza, gli MCP (npx) muoiono dentro le sessioni |
| `com.ppezz.tmux-agents.plist` | `~/Library/LaunchAgents/` | `RunAtLoad` → boot script |

## Verify dopo l'install

```bash
tmux ls                                  # server vivo
tmux show -gv @continuum-restore         # on
# dentro una sessione:
command -v npx && echo "MCP ok"          # PATH buono
```

## Note operative

- `tmux new -A -s nome` = "attacca se esiste, altrimenti crea" — cuore di tutto
- Save/restore manuali: `prefix C-s` / `prefix C-r`
- I salvataggi vivono in `~/.tmux/resurrect/`
- Se una sessione resta "appesa" dopo restore: `tmux kill-session -t <nome>` e
  ricrea — il contesto è nel transcript, `claude -c` lo riprende
