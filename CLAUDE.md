# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Cos'è questo repo

Il setup Claude Code personale di ppezz, versione documentata e installabile: agenti persistenti via tmux, HUD statusline GLM, bus inter-session. Non è codice eseguito direttamente — è **configurazione + installer + documentazione**. I file qui dentro sono la fonte; l'installazione li copia nelle loro destinazioni (`~/.tmux.conf`, `~/bin/`, `~/Library/LaunchAgents/`, `~/.zshrc`, plugin cache).

## Comandi

```bash
./install.sh          # installa/aggiorna tutto (idempotente, rilanciabile)
bash -n install.sh    # syntax check dell'installer dopo edit
```

Non ci sono build/test: la verifica è funzionale (vedi i README delle cartelle per i comandi di verify — `tmux ls`, `tmux show -gv @continuum-restore`, render di prova dell'HUD con echo-pipe a bun).

## Architettura — come i pezzi si incastrano

La catena di persistenza, dall'alto in basso:

1. **`zsh/claude-function.zsh`** — l'entry point utente: `claude` diventa una sessione tmux `a-<cartella>` (suffisso `-2`, `-3` per agenti paralleli). La selezione sessione usa `tmux list-clients` per distinguere "agente libero da riattaccare" da "agente presidiato, creane un altro".
2. **`tmux/`** — il demone che tiene tutto in vita: `tmux.conf` (continuum auto-save 15' + auto-restore, `@resurrect-processes ' ~claude->claude -c'` per riprendere le conversazioni), `tmux-agents-boot.sh` (PATH esplicito — launchd parte con ambiente minimale e senza questo gli MCP npx muoiono dentro le sessioni), la plist RunAtLoad.
3. **`hud/`** — due repo esterni che collaborano: il wrapper [ppezzull/glm-claude-hud](https://github.com/ppezzull/glm-claude-hud) (quota GLM, sintesi context dal transcript, scala colori, seat name) deployato via **symlink** (`git pull` = deploy), e il fork [ppezzull/claude-hud](https://github.com/ppezzull/claude-hud) v0.1.0 clonato come versione nel cache del plugin (il wrapper sceglie la versione più alta → il fork batte l'upstream, che NON ha il supporto rate_limits della riga Usage).
4. **`bus/`** — federazione inter-session; l'implementazione sta in [craftale-agency/interserver](https://github.com/craftale-agency/interserver), qui solo la specifica del Mac (spoke verso hub nebula :9473) e i failure mode verificati.
5. **`settings/settings.example.json`** — sanificato: i secret sono placeholder, i valori veri non entrano MAI nel repo.

## Regole del repo

- **Mai valori di secret nei file** — solo riferimento al gestore (il filtro dell'installer non basta: controllare i diff di settings.example.json a mano).
- Modifiche chirurgiche: i file qui riflettono la macchina — se cambi qualcosa su ~/.tmux.conf o la funzione zsh **riporta la modifica qui**, altrimenti il repo diverge dal reale.
- `install.sh` deve restare idempotente: ogni blocco guarda se la destinazione esiste già prima di toccarla.

## Gotcha documentati (non reinventarli)

- Plugin claude-hud auto-aggiornato all'upstream = riga Usage sparita (2026-10-29) → ri-clonare il fork come 0.1.0.
- Meta pidfile del bus senza `host`/`port` = seat morti silenziosi per giorni (2026-10-24→27) → fix nel wrapper `9b38e5f` di interserver.
- Sessione tmux nata prima di un fix di PATH mantiene l'ambiente vecchio: va ricreata, non basta rilanciare claude dentro.
