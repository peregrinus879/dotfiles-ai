# Maintenance automation for dotfiles-ai. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.

SHELL := /bin/bash
PACKAGES := claude-code codex opencode

.PHONY: help stow unstow dry-run restow verify clean lint

help:
	@echo "Targets:"
	@echo "  stow      Stow all packages into ~"
	@echo "  unstow    Remove all package symlinks"
	@echo "  dry-run   Preview stow actions without making changes"
	@echo "  restow    Re-stow after repo content changes"
	@echo "  verify    Check symlinks, JSON validity, statusline syntax, skill sync, and stray configs"
	@echo "  clean     Safely prepare managed paths for stow"
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
	for command in python3 jq readlink realpath stat; do \
	  if command -v "$$command" > /dev/null; then :; \
	  else echo "FAIL: required verifier missing: $$command"; fail=1; fi; \
	done; \
	[[ $$fail == 0 ]] || exit $$fail; \
	for pair in "$$HOME/.claude/CLAUDE.md=claude-code/.claude/CLAUDE.md" \
	  "$$HOME/.claude/settings.json=claude-code/.claude/settings.json" \
	  "$$HOME/.claude/statusline.sh=claude-code/.claude/statusline.sh" \
	  "$$HOME/.claude/rules/shared-guidance.md=claude-code/.claude/rules/shared-guidance.md" \
	  "$$HOME/.claude/skills/commit/SKILL.md=claude-code/.claude/skills/commit/SKILL.md" \
	  "$$HOME/.claude/skills/spar/SKILL.md=claude-code/.claude/skills/spar/SKILL.md" \
	  "$$HOME/.local/bin/spar-claude=claude-code/.local/bin/spar-claude" \
	  "$$HOME/.local/bin/spar-payload-scan=claude-code/.local/bin/spar-payload-scan" \
	  "$$HOME/.codex/config.toml=codex/.codex/config.toml" \
	  "$$HOME/.codex/AGENTS.md=codex/.codex/AGENTS.md" \
	  "$$HOME/.agents/skills/commit/SKILL.md=codex/.agents/skills/commit/SKILL.md" \
	  "$$HOME/.agents/skills/spar/SKILL.md=codex/.agents/skills/spar/SKILL.md" \
	  "$$HOME/.local/bin/spar-codex=codex/.local/bin/spar-codex" \
	  "$$HOME/.config/opencode/opencode.json=opencode/.config/opencode/opencode.json" \
	  "$$HOME/.config/opencode/plugins/reviewed-writes.ts=opencode/.config/opencode/plugins/reviewed-writes.ts" \
	  "$$HOME/.config/opencode/tui.json=opencode/.config/opencode/tui.json" \
	  "$$HOME/.config/opencode/AGENTS.md=opencode/.config/opencode/AGENTS.md" \
	  "$$HOME/.config/opencode/commands/commit.md=opencode/.config/opencode/commands/commit.md" \
	  "$$HOME/.config/opencode/commands/spar.md=opencode/.config/opencode/commands/spar.md" \
	  "$$HOME/.config/opencode/skills/commit/SKILL.md=opencode/.config/opencode/skills/commit/SKILL.md" \
	  "$$HOME/.config/opencode/skills/spar/SKILL.md=opencode/.config/opencode/skills/spar/SKILL.md"; do \
	  target="$${pair%%=*}"; src="$${pair##*=}"; \
	  target_resolved=$$(readlink -f -- "$$target") || target_resolved=""; \
	  src_resolved=$$(readlink -f -- "$$src") || src_resolved=""; \
	  if [[ -n $$target_resolved && -n $$src_resolved && $$target_resolved == "$$src_resolved" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done; \
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   bash -n statusline.sh"; else echo "FAIL: bash -n statusline.sh"; fail=1; fi; \
	if bash -n scripts/prepare-stow.sh tests/prepare-stow.sh && bash tests/prepare-stow.sh; then \
	  echo "ok:   non-destructive stow preparation"; \
	else echo "FAIL: non-destructive stow preparation"; fail=1; fi; \
	if bash -n tests/spar-bridges.sh && bash tests/spar-bridges.sh; then :; \
	else echo "FAIL: spar bridge payload controls"; fail=1; fi; \
	for b in spar-claude spar-codex spar-payload-scan; do \
	  if [[ -x "$$HOME/.local/bin/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if [[ $$(grep -Fc -- '--tools ' claude-code/.local/bin/spar-claude) == 1 ]] && \
	  grep -Fqx '    --tools "Read,Glob,Grep" \' claude-code/.local/bin/spar-claude; then \
	  echo "ok:   spar-claude read-only tool whitelist"; \
	else echo "FAIL: spar-claude read-only tool whitelist missing"; fail=1; fi; \
	for b in claude-code/.local/bin/spar-claude codex/.local/bin/spar-codex; do \
	  if grep -Fq 'HANDOFF_RE=' "$$b" && grep -Fq 'validate_handoff()' "$$b" && \
	    grep -Fq 'stat -c '\''%h'\''' "$$b" && grep -Fq 'stat -c '\''%a'\''' "$$b" && \
	    grep -Fq 'realpath -e --' "$$b" && grep -Fq 'clean_handoff()' "$$b" && \
	    grep -Fq '[[ -e $$root || -L $$root ]] || return 0' "$$b"; then \
	    echo "ok:   $${b##*/} private handoff lifecycle"; \
	  else echo "FAIL: $${b##*/} private handoff lifecycle drifted"; fail=1; fi; \
	done; \
	if python3 tests/config-contracts.py; then :; \
	else echo "FAIL: config syntax or security contract drifted"; fail=1; fi; \
	if grep -Fqx -- '- Persistent file-content changes use native edit tools, so each file gets its own approval prompt and diff. An `apply_patch` call modifies exactly one file; never bundle multiple files into one patch.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fqx -- '- An `apply_patch` call must modify exactly one file; never bundle multiple files into one patch.' opencode/.config/opencode/AGENTS.md; then \
	  echo "ok:   one-file apply_patch guidance"; \
	else echo "FAIL: one-file apply_patch guidance missing"; fail=1; fi; \
	if grep -Fq 'The go-ahead authorizes those listed commits unless H explicitly excludes commits.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Never accumulate changes from multiple planned commits.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Treat a trivial tracked change as one implicit atomic commit: edit, verify, commit, report.' claude-code/.claude/rules/shared-guidance.md && \
	  ! grep -Fq 'Commits: only when asked' claude-code/.claude/rules/shared-guidance.md; then \
	  echo "ok:   phased-work commit checkpoints"; \
	else echo "FAIL: phased-work commit checkpoints drifted"; fail=1; fi; \
	if [[ -f opencode/.config/opencode/plugins/reviewed-writes.ts ]] && \
	  grep -Fq 'unique.size !== 1' opencode/.config/opencode/plugins/reviewed-writes.ts && \
	  ! grep -Fq 'spar-scratch' opencode/.config/opencode/plugins/reviewed-writes.ts; then \
	  echo "ok:   opencode one-file patch plugin"; \
	else echo "FAIL: opencode one-file patch plugin drifted"; fail=1; fi; \
	if grep -Fq '/tmp/spar-<session-id>/' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '/tmp/spar-<session-id>/' codex/.agents/skills/spar/SKILL.md && \
	  grep -Fq '/tmp/spar-<session-id>/' opencode/.config/opencode/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer bridge'\''s `init` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer bridge'\''s `clean` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'spar-scratch' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'spar-scratch' codex/.agents/skills/spar/SKILL.md && \
	  ! grep -Fq 'spar-scratch' opencode/.config/opencode/skills/spar/SKILL.md; then \
	  echo "ok:   spar skills use private OS temp handoffs"; \
	else echo "FAIL: spar scratch protocol drifted"; fail=1; fi; \
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	for s in commit spar; do \
	  synced=1; \
	  for copy in "codex/.agents/skills/$$s/SKILL.md" "opencode/.config/opencode/skills/$$s/SKILL.md"; do \
	    diff -q \
	      <(awk '/^## Reviewer incantations$$/{skip=1; next} /^## /{skip=0} !skip' "claude-code/.claude/skills/$$s/SKILL.md" | grep -v -e 'disable-model-invocation' -e 'allowed-tools' -e 'Co-Authored-By') \
	      <(awk '/^## Reviewer incantations$$/{skip=1; next} /^## /{skip=0} !skip' "$$copy" | grep -v -e 'Co-Authored-By') > /dev/null || synced=0; \
	  done; \
	  if [[ $$synced == 1 ]]; then \
	    echo "ok:   $$s skill copies in sync (shared sections)"; \
	  else echo "FAIL: $$s skill copies drifted (allowed diffs: tool frontmatter keys, Co-Authored-By, Reviewer incantations section)"; fail=1; fi; \
	done; \
	exit $$fail

clean:
	bash scripts/prepare-stow.sh

lint:
	shellcheck -s bash claude-code/.claude/statusline.sh claude-code/.local/bin/spar-claude codex/.local/bin/spar-codex
	@echo "ok:   shellcheck clean"
