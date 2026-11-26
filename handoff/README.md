# Handoff: `/clear` senza perdere il filo

Quando una sessione arriva a 15 MB di transcript (la misura che la HUD mostra
accanto al contesto), i turni diventano lenti e costosi. Prima si faceva a
mano: "salva stato, pendenti e prossimi passi in /tmp", `/clear`, "continue
from /tmp". Ora l'unica cosa da fare è dire sì.

## Come funziona

**A richiesta** (scelta del 26/11): chiedi "usa l'handoff" quando vuoi, ed è
l'unico modo normale di avviarlo.

1. Claude scrive `/tmp/<cartella>-handoff-<data>.md` con la skill `handoff`:
   obiettivo, stato, pendenti, prossimi passi, file chiavi, decisioni.
2. Alla fine della risposta la sessione fa da sola `/clear` e manda
   `continue from <file>`. Quella nuova carica il file e riparte da lì.

La **proposta automatica** esiste ma è spenta di default (`HANDOFF_MB=15000`):
con una soglia raggiungibile (es. `HANDOFF_MB=15`) Claude propone da solo a
fine risposta, una volta ogni `HANDOFF_STEP_MB` MB.

Per salvare lo stato **senza** ripartire da capo: si scrive
`/tmp/<cartella>-status-<data>.md`, che non avvia nulla.

## I pezzi

| File | Cosa fa |
|---|---|
| `handoff.py` | hook: `--hook prompt` propone, `--hook stop` avvia clear e ripresa, `--hook start` carica il file dopo `/clear` |
| `skill/SKILL.md` | il formato del file di handoff |

L'installer li collega con symlink a `~/.claude/scripts/handoff.py` e
`~/.claude/skills/handoff`, e aggiunge tre hook a `~/.claude/settings.json`
(`UserPromptSubmit`, `Stop`, e `SessionStart` con matcher `clear`).

Nel flavor GLM la misura MB nella HUD diventa rossa da 15 MB in su: indicatore
visivo, indipendente dalla soglia di proposta.

## Regolare

| Variabile | Default | Cosa cambia |
|---|---|---|
| `HANDOFF_MB` | `15000` | da quanti MB di transcript propone (default: mai, si chiede a mano) |
| `HANDOFF_STEP_MB` | `5` | ogni quanti MB ripropone, se hai detto di no |
| `HANDOFF_TTL_HOURS` | `24` | per quanto tempo un file è ancora caricato dopo `/clear` |

## Limiti noti

- Il clear e la ripresa automatici funzionano **solo dentro tmux**: sono tasti
  inviati al pane della sessione. Fuori da tmux il file resta salvato e il resto
  si fa a mano (`/clear`, poi `continue from <file>`).
- Se la sessione è ancora occupata dopo la risposta (messaggi dal bus in coda),
  non viene interrotta: si fa a mano, o si riscrive il file per riprovare.
- Il file si collega alla cartella per nome (`CraftLead`), non per percorso:
  due cartelle omonime si vedono i file l'una dell'altra.
- `/tmp` si svuota al riavvio: l'handoff serve a attraversare un `/clear`, non
  è un backup.

## Verifica

```bash
echo '{"session_id":"t","cwd":"'$PWD'","transcript_path":"handoff/README.md","prompt":"ciao"}' \
  | HANDOFF_MB=0.001 python3 ~/.claude/scripts/handoff.py --hook prompt
```

Stampa il contesto della proposta (il file README pesa più di 0.001 MB).
Per una prova completa, apri una sessione di prova con la soglia abbassata:

```bash
mkdir -p /tmp/handoff-prova && cd /tmp/handoff-prova
env HANDOFF_MB=0.001 claude --permission-mode acceptEdits
```

Scrivi due messaggi, di' sì alla proposta e guarda la sessione ripartire da sola.
