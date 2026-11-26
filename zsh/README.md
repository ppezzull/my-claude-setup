# zsh — la funzione claude()

`claude-function.zsh` va sourcing da `~/.zshrc` (l'installer lo appende in
maniera idempotente). Semantica:

| Quando scrivi `claude` | Cosa succede |
|---|---|
| Nessun agente nella cartella | crea sessione tmux `a-<cartella>` |
| Agente esiste, nessuno attaccato | ti riattacca (torni dal tuo agente) |
| Agente base già presidiato | crea `a-<cartella>-1` (o si attacca a una libera) |
| Agente base chiuso, restano `-1`, `-2`... | li compatta verso il basso (`-1` diventa `a-<cartella>`, `-2` diventa `-1`, ...) e poi si attacca |

Gli argomenti passano dritti: `claude -c`, `claude --resume`, `claude -p ...`
funzionano dentro la sessione. Nota: se l'agente della cartella è già vivo,
`--resume` viene ignorato (vince l'attach, che è già un resume migliore).

`a-<cartella>-1` e successive = agenti paralleli sulla stessa working copy:
se devono toccare gli stessi file, usa `claude --worktree <nome>` in uno dei due.

I numeri non restano buchi: se l'agente base viene chiuso, al `claude` successivo
il più vecchio dei superstiti prende il nome pulito e gli altri scendono di uno.
L'agente non si accorge di nulla (rinomina della sessione tmux, nessun tasto
inviato); il suo nome sul bus inter-session segue il nuovo nome, con un paio di
attimi di assenza mentre il watchdog lo riarma.
