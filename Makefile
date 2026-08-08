# Maintenance automation for dotfiles-ai. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.

SHELL := /bin/bash
PACKAGES := claude-code opencode

.PHONY: help stow unstow dry-run restow verify clean lint

help:
	@echo "Targets:"
	@echo "  stow      Stow all packages into ~"
	@echo "  unstow    Remove all package symlinks"
	@echo "  dry-run   Preview stow actions without making changes"
	@echo "  restow    Re-stow after repo content changes"
	@echo "  verify    Check symlinks, JSON validity, statusline syntax, skill sync, and stray configs"
	@echo "  clean     Remove files that would conflict with stow (README Prepare steps)"
	@echo "  lint      ShellCheck over statusline.sh (.shellcheckrc holds the disable list)"

stow:
	stow -v -t ~ $(PACKAGES)

unstow:
	stow -D -v -t ~ $(PACKAGES)

dry-run:
	stow -v -n -t ~ $(PACKAGES)

restow:
	stow -R -v -t ~ $(PACKAGES)

# Stow may tree-fold a parent directory (e.g. ~/.config/opencode) into a
# single directory symlink, so per-file "test -L" checks false-negative.
# Compare resolved paths instead: linked is linked, folded or not.
verify:
	@fail=0; \
	for pair in "$$HOME/.claude/CLAUDE.md=claude-code/.claude/CLAUDE.md" \
	  "$$HOME/.claude/settings.json=claude-code/.claude/settings.json" \
	  "$$HOME/.claude/statusline.sh=claude-code/.claude/statusline.sh" \
	  "$$HOME/.claude/rules/shared-guidance.md=claude-code/.claude/rules/shared-guidance.md" \
	  "$$HOME/.claude/skills/commit/SKILL.md=claude-code/.claude/skills/commit/SKILL.md" \
	  "$$HOME/.config/opencode/opencode.json=opencode/.config/opencode/opencode.json" \
	  "$$HOME/.config/opencode/tui.json=opencode/.config/opencode/tui.json" \
	  "$$HOME/.config/opencode/AGENTS.md=opencode/.config/opencode/AGENTS.md" \
	  "$$HOME/.config/opencode/commands/commit.md=opencode/.config/opencode/commands/commit.md" \
	  "$$HOME/.config/opencode/skills/commit/SKILL.md=opencode/.config/opencode/skills/commit/SKILL.md"; do \
	  target="$${pair%%=*}"; src="$${pair##*=}"; \
	  if [[ "$$(readlink -f "$$target")" == "$$(readlink -f "$$src")" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done; \
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   bash -n statusline.sh"; else echo "FAIL: bash -n statusline.sh"; fail=1; fi; \
	if command -v jq > /dev/null; then \
	  for f in claude-code/.claude/settings.json opencode/.config/opencode/opencode.json opencode/.config/opencode/tui.json .claude/settings.json opencode.json; do \
	    if jq empty "$$f" > /dev/null 2>&1; then echo "ok:   valid JSON $$f"; else echo "FAIL: invalid JSON $$f"; fail=1; fi; \
	  done; \
	  if jq -e '.permission.bash | to_entries | (map(.key) | index("* > *")) as $$i | if $$i == null then false else .[$$i:] | all(.value != "allow") end' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode bash permission order (no allow after guards)"; \
	  else echo "FAIL: opencode bash permission order (guards and denies must be the final entries)"; fail=1; fi; \
	else echo "note: jq not found, skipping JSON validity checks"; fi; \
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	if diff -q \
	  <(grep -v -e 'disable-model-invocation' -e 'allowed-tools' -e 'Co-Authored-By' claude-code/.claude/skills/commit/SKILL.md) \
	  <(grep -v -e 'Co-Authored-By' opencode/.config/opencode/skills/commit/SKILL.md) > /dev/null; then \
	  echo "ok:   commit skill copies in sync"; \
	else echo "FAIL: commit skill copies drifted (allowed diffs: disable-model-invocation, allowed-tools, Co-Authored-By)"; fail=1; fi; \
	exit $$fail

clean:
	-rm -f ~/.claude/agents ~/.claude/rules ~/.claude/skills
	-rm -f ~/.config/opencode ~/.config/opencode/agents ~/.config/opencode/commands \
	  ~/.config/opencode/modes ~/.config/opencode/plugins ~/.config/opencode/skills \
	  ~/.config/opencode/themes ~/.config/opencode/tools
	-rm -f ~/.claude/settings.json

lint:
	shellcheck -s bash claude-code/.claude/statusline.sh
	@echo "ok:   shellcheck clean"
