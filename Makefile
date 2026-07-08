# Maintenance automation for dotfiles-ai. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.

SHELL := /bin/bash
PACKAGES := claude-code opencode

.PHONY: help stow unstow dry-run restow verify clean

help:
	@echo "Targets:"
	@echo "  stow      Stow all packages into ~"
	@echo "  unstow    Remove all package symlinks"
	@echo "  dry-run   Preview stow actions without making changes"
	@echo "  restow    Re-stow after repo content changes"
	@echo "  verify    Check symlinks, JSON validity, and statusline syntax"
	@echo "  clean     Remove files that would conflict with stow (README Prepare steps)"

stow:
	stow -v -t ~ $(PACKAGES)

unstow:
	stow -D -v -t ~ $(PACKAGES)

dry-run:
	stow -v -n -t ~ $(PACKAGES)

restow:
	stow -R -v -t ~ $(PACKAGES)

verify:
	@fail=0; \
	for link in ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/statusline.sh ~/.config/opencode/opencode.json; do \
	  if [[ -L "$$link" ]]; then echo "ok:   symlink $$link"; else echo "FAIL: missing symlink $$link"; fail=1; fi; \
	done; \
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   bash -n statusline.sh"; else echo "FAIL: bash -n statusline.sh"; fail=1; fi; \
	if command -v jq > /dev/null; then \
	  for f in claude-code/.claude/settings.json opencode/.config/opencode/opencode.json opencode/.config/opencode/tui.json; do \
	    if jq empty "$$f" > /dev/null 2>&1; then echo "ok:   valid JSON $$f"; else echo "FAIL: invalid JSON $$f"; fail=1; fi; \
	  done; \
	else echo "note: jq not found, skipping JSON validity checks"; fi; \
	exit $$fail

clean:
	-rm -f ~/.claude/agents ~/.claude/rules ~/.claude/skills
	-rm -f ~/.config/opencode ~/.config/opencode/agents ~/.config/opencode/commands \
	  ~/.config/opencode/modes ~/.config/opencode/plugins ~/.config/opencode/skills \
	  ~/.config/opencode/themes ~/.config/opencode/tools
	-rm -f ~/.claude/settings.json
