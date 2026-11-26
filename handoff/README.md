# Handoff: `/clear` senza perdere il filo

Quando una sessione arriva a 15 MB di transcript (la misura che la HUD mostra
accanto al contesto), i turni diventano lenti e costosi. Prima si faceva a
mano: "salva stato, pendenti e prossimi passi in /tmp", `/clear`, "continue
from /tmp". Ora il processo è lo stesso, ma proposto.

## Come funziona

1. Il transcript supera i 15 MB. A fine risposta Claude **chiede** se fare
   l'handoff (una volta ogni 5 MB: a 15, a 20, a 25...).
2. Dici di sì. Claude scrive `/tmp/<cartella>-handoff-<data>.md` con la skill
   `handoff`: obiettivo, stato, pendenti, prossimi passi, file chiavi, decisioni.
3. Fai `/clear`. Il file viene caricato nella sessione nuova: scrivi e Claude
   riparte da lì.

Niente avviene senza il tuo sì. Se dici di no, la proposta torna 5 MB dopo.

## I pezzi

| File | Cosa fa |
|---|---|
| `handoff.py` | hook: `--hook prompt` propone, `--hook start` carica il file dopo `/clear` |
| `skill/SKILL.md` | il formato del file di handoff |

L'installer li collega con symlink a `~/.claude/scripts/handoff.py` e
`~/.claude/skills/handoff`, e aggiunge due hook a `~/.claude/settings.json`
(`UserPromptSubmit` e `SessionStart` con matcher `clear`).

Nel flavor GLM anche la misura MB nella HUD diventa rossa da 15 MB in su.

## Regolare

| Variabile | Default | Cosa cambia |
|---|---|---|
| `HANDOFF_MB` | `15` | da quanti MB di transcript propone |
| `HANDOFF_STEP_MB` | `5` | ogni quanti MB ripropone, se hai detto di no |
| `HANDOFF_TTL_HOURS` | `24` | per quanto tempo un file è ancora caricato dopo `/clear` |

## Limiti noti

- Il file si collega alla cartella per nome (`CraftLead`), non per percorso:
  due cartelle omonime si vedono i file l'una dell'altra.
- `/tmp` si svuota al riavvio: l'handoff serve a attraversare un `/clear`, non
  è un backup.
- Dopo `/clear` Claude aspetta un tuo messaggio: non riparte da solo.

## Verifica

```bash
echo '{"session_id":"t","cwd":"'$PWD'","transcript_path":"handoff/README.md","prompt":"ciao"}' \
  | HANDOFF_MB=0.001 python3 ~/.claude/scripts/handoff.py --hook prompt
```

Stampa il contesto della proposta (il file README pesa più di 0.001 MB).
