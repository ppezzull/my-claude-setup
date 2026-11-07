# Makefile — comodi shortcuts per my-claude-setup
# uso: make <target>   (default: medium)

.PHONY: help minimal medium full verify update hud

help:
	@grep -E '^# usage:|^minimal|medium|^full|^verify|^update' -B0 Makefile | head -12
	@echo "targets: minimal medium full verify update"

## minimal: solo persistenza agenti (tmux + funzione claude)
minimal:
	./install.sh --minimal $(ARGS)

## medium (default): persistenza + HUD
medium: default
default:
	./install.sh --medium $(ARGS)

## full: tutto, bus inter-session incluso
full:
	./install.sh --full $(ARGS)

## verify: controlli funzionali post-install
verify:
	@echo "— tmux server:"; tmux ls 2>/dev/null || echo "  NON in esecuzione!"
	@echo "— continuum restore: $$(tmux show -gv @continuum-restore 2>/dev/null || echo assente)"
	@echo "— tmux.conf symlink: $$(readlink ~/.tmux.conf 2>/dev/null || echo 'NO symlink')"
	@echo "— wrapper symlink: $$(readlink ~/.claude/scripts/glm-wrapper.ts 2>/dev/null || echo 'NO symlink')"
	@echo "— fork renderer 0.1.0: $$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0 >/dev/null 2>&1 && echo ok || echo MANCANTE)"
	@echo "— boot service:"
	@if [ "$$(uname -s)" = Darwin ]; then launchctl print "gui/$$(id -u)/com.ppezz.tmux-agents" 2>/dev/null | grep -m1 "state =" || echo "  MANCANTE"; else systemctl --user is-active tmux-agents.service 2>/dev/null || echo "  MANCANTE"; fi
	@echo "— HUD render di prova:"
	@echo '{"model":{"display_name":"test"}}' | "$$(command -v bun || echo $$HOME/.bun/bin/bun)" ~/.claude/scripts/glm-wrapper.ts 2>/dev/null | head -1 || echo "  RENDER FALLITO"

## update: git pull su tutti i repo dello stack (deploy = symlink)
update:
	git -C . pull --ff-only
	git -C $(HOME)/Desktop/Personal/My-Tmux-conf pull --ff-only 2>/dev/null || true
	git -C $(HOME)/Desktop/Personal/glm-claude-hud pull --ff-only 2>/dev/null || true
	git -C $(HOME)/.tmux/plugins/tpm pull --ff-only 2>/dev/null || true
	@echo "repo aggiornati (i symlink rendono effettivi i cambi)"
