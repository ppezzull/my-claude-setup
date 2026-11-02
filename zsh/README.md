# zsh — la funzione claude()

`claude-function.zsh` va sourcing da `~/.zshrc` (l'installer lo appende in
maniera idempotente). Semantica:

| Quando scrivi `claude` | Cosa succede |
|---|---|
| Nessun agente nella cartella | crea sessione tmux `a-<cartella>` |
| Agente esiste, nessuno attaccato | ti riattacca (torni dal tuo agente) |
| Agente base già presidiato | crea `a-<cartella>-1` (o si attacca a una libera) |

Gli argomenti passano dritti: `claude -c`, `claude --resume`, `claude -p ...`
funzionano dentro la sessione. Nota: se l'agente della cartella è già vivo,
`--resume` viene ignorato (vince l'attach, che è già un resume migliore).

`a-<cartella>-1` e successive = agenti paralleli sulla stessa working copy:
se devono toccare gli stessi file, usa `claude --worktree <nome>` in uno dei due.
