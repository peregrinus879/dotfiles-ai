# Maintenance automation for EyrAgents. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.

SHELL := /bin/bash
PACKAGES := claude-code codex opencode
SHELLCHECK_FILES := claude-code/.claude/statusline.sh \
  claude-code/.claude/hooks/spar-handoff-approve.sh \
  claude-code/.local/bin/spar-claude \
  codex/.local/bin/spar-codex \
  $(wildcard scripts/*.sh tests/*.sh)

.PHONY: help stow unstow dry-run restow migrate-codex-config verify clean lint

help:
	@echo "Targets:"
	@echo "  stow      Stow all packages into ~"
	@echo "  unstow    Remove all package symlinks"
	@echo "  dry-run   Preview raw Stow actions without running preparation"
	@echo "  restow    Re-stow after repo content changes"
	@echo "  migrate-codex-config  Safely convert Codex config to host-local state"
	@echo "  verify    Check every intended deployment and run the full verification suite"
	@echo "  clean     Safely prepare managed paths for stow"
	@echo "  lint      ShellCheck over all managed Bash scripts"

stow: clean
	stow -v -t ~ $(PACKAGES)

unstow:
	stow -D -v -t ~ $(PACKAGES)

dry-run:
	stow -v -n -t ~ $(PACKAGES)

restow: clean
	stow -R -v -t ~ $(PACKAGES)

migrate-codex-config:
	bash scripts/prepare-stow.sh --migrate-codex-config

# Stow may tree-fold package subdirectories, so compare resolved managed-child
# paths rather than requiring leaf links. Preparation keeps runtime-state roots
# such as ~/.config/opencode real.
# GNU Stow ignores .gitignore by default; the three package-internal copies
# control fresh-clone state and are intentionally not deployed.
# Structured config contracts live in tests/config-contracts.py; stable
# semantic script and skill safety and synchronization checks live here.
verify:
	@fail=0; \
	for command in cmp find git id jq mktemp mv node python3 readlink realpath sha256sum stat stow sync; do \
	  command -v "$$command" > /dev/null || { echo "FAIL: required verifier missing: $$command"; fail=1; }; \
	done; \
	[[ $$fail == 0 ]] || exit $$fail; \
	while IFS= read -r -d '' src; do \
	  [[ "$$src" == */.gitignore ]] && continue; \
	  target="$$HOME/$${src#*/}"; \
	  if [[ ! -e $$src && ! -L $$src ]]; then \
	    if git diff --quiet -- "$$src"; then \
	      echo "FAIL: tracked package source is missing without a pending deletion: $$src"; fail=1; \
	    elif [[ -L $$target ]]; then \
	      echo "FAIL: retired package endpoint remains linked: $$target"; fail=1; \
	    elif [[ ! -e $$target ]]; then \
	      echo "ok:   retired package endpoint absent: $$target"; \
	    elif [[ -f $$target && -O $$target ]]; then \
	      echo "ok:   retired package endpoint is owner-controlled: $$target"; \
	    else \
	      echo "FAIL: retired package endpoint has an unsupported replacement: $$target"; fail=1; \
	    fi; \
	    continue; \
	  fi; \
	  target_resolved=$$(readlink -f -- "$$target"); \
	  src_resolved=$$(readlink -f -- "$$src"); \
	  if [[ -n $$target_resolved && -n $$src_resolved && $$target_resolved == "$$src_resolved" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done < <(git ls-files -z --cached --others --exclude-standard -- $(PACKAGES)); \
	for pair in "$$HOME/.claude/CLAUDE.md=claude-code/.claude/CLAUDE.md" \
	  "$$HOME/.claude/settings.json=claude-code/.claude/settings.json" \
	  "$$HOME/.claude/statusline.sh=claude-code/.claude/statusline.sh" \
	  "$$HOME/.claude/hooks/spar-handoff-approve.sh=claude-code/.claude/hooks/spar-handoff-approve.sh" \
	  "$$HOME/.claude/rules/shared-guidance.md=claude-code/.claude/rules/shared-guidance.md" \
	  "$$HOME/.claude/skills/commit/SKILL.md=claude-code/.claude/skills/commit/SKILL.md" \
	  "$$HOME/.claude/skills/spar/SKILL.md=claude-code/.claude/skills/spar/SKILL.md" \
	  "$$HOME/.codex/config.toml=codex/.codex/config.toml" \
	  "$$HOME/.codex/AGENTS.md=codex/.codex/AGENTS.md" \
	  "$$HOME/.agents/skills/commit/SKILL.md=codex/.agents/skills/commit/SKILL.md" \
	  "$$HOME/.agents/skills/spar/SKILL.md=codex/.agents/skills/spar/SKILL.md" \
	  "$$HOME/.config/opencode/opencode.json=opencode/.config/opencode/opencode.json" \
	  "$$HOME/.config/opencode/plugins/package.json=opencode/.config/opencode/plugins/package.json" \
	  "$$HOME/.config/opencode/plugins/reviewed-writes.ts=opencode/.config/opencode/plugins/reviewed-writes.ts" \
	  "$$HOME/.config/opencode/tui.json=opencode/.config/opencode/tui.json" \
	  "$$HOME/.config/opencode/commands/commit.md=opencode/.config/opencode/commands/commit.md" \
	  "$$HOME/.config/opencode/commands/spar.md=opencode/.config/opencode/commands/spar.md" \
	  "$$HOME/.config/opencode/skills/commit/SKILL.md=opencode/.config/opencode/skills/commit/SKILL.md" \
	  "$$HOME/.config/opencode/skills/spar/SKILL.md=opencode/.config/opencode/skills/spar/SKILL.md"; do \
	  target="$${pair%%=*}"; src="$${pair##*=}"; \
	  target_resolved=$$(readlink -f -- "$$target"); \
	  src_resolved=$$(readlink -f -- "$$src"); \
	  if [[ -n $$target_resolved && -n $$src_resolved && $$target_resolved == "$$src_resolved" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done; \
	if [[ -d "$$HOME/.config/opencode" && ! -L "$$HOME/.config/opencode" ]]; then \
	  echo "ok:   OpenCode config root is a real directory"; \
	else echo "FAIL: OpenCode config root is not a real directory"; fail=1; fi; \
	for path in package.json package-lock.json bun.lock bun.lockb; do \
	  target="$$HOME/.config/opencode/$$path"; \
	  if [[ ! -L $$target && ( ! -e $$target || -f $$target ) ]]; then \
	    echo "ok:   OpenCode host-local file state: $$path"; \
	  else echo "FAIL: OpenCode generated file is linked or has the wrong type: $$target"; fail=1; fi; \
	done; \
	target="$$HOME/.config/opencode/node_modules"; \
	if [[ ! -L $$target && ( ! -e $$target || -d $$target ) ]]; then \
	  echo "ok:   OpenCode host-local dependency state"; \
	else echo "FAIL: OpenCode dependency state is linked or has the wrong type: $$target"; fail=1; fi; \
	for path in package.json package-lock.json bun.lock bun.lockb node_modules; do \
	  target="opencode/.config/opencode/$$path"; \
	  if [[ ! -e $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: generated OpenCode root state reached the package source: $$target"; fail=1; fi; \
	done; \
	for path in package-lock.json bun.lock bun.lockb node_modules; do \
	  target="opencode/.config/opencode/plugins/$$path"; \
	  if [[ ! -e $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: generated state appeared below the tracked plugin marker: $$target"; fail=1; fi; \
	done; \
	for b in spar-claude spar-codex spar-payload-scan; do \
	  if [[ -x "$$HOME/.local/bin/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   statusline shell syntax"; else echo "FAIL: statusline shell syntax"; fail=1; fi; \
	bash -n tests/statusline-state.sh && bash tests/statusline-state.sh || { echo "FAIL: statusline runtime-state controls"; fail=1; }; \
	bash -n scripts/prepare-stow.sh tests/commit-candidate.sh tests/prepare-stow.sh tests/spar-bridges.sh || { echo "FAIL: managed shell syntax"; fail=1; }; \
	bash tests/commit-candidate.sh || { echo "FAIL: fingerprint-bound commit candidate controls"; fail=1; }; \
	bash tests/prepare-stow.sh || { echo "FAIL: non-destructive stow preparation"; fail=1; }; \
	if python3 -I -c 'from pathlib import Path; p=Path("claude-code/.local/bin/spar-payload-scan"); compile(p.read_bytes(), str(p), "exec")'; then \
	  echo "ok:   spar payload scanner syntax"; \
	else echo "FAIL: spar payload scanner syntax"; fail=1; fi; \
	bash -n tests/spar-bridges.sh && bash tests/spar-bridges.sh || { echo "FAIL: spar bridge payload controls"; fail=1; }; \
	bash -n tests/project-config-isolation.sh && bash tests/project-config-isolation.sh || { echo "FAIL: project config isolation"; fail=1; }; \
	if [[ $$(grep -Fc -- '--tools ' claude-code/.local/bin/spar-claude) == 1 ]] && \
	  grep -Fqx '    --tools "Read,Glob,Grep" \' claude-code/.local/bin/spar-claude && \
	  ! grep -Fq -- '--allowedTools' claude-code/.local/bin/spar-claude; then \
	  echo "ok:   spar-claude read-only tool whitelist"; \
	else echo "FAIL: spar-claude read-only tool whitelist missing"; fail=1; fi; \
	for path in .gitignore scripts/activate-spar-gate.sh tests/spar-gate.sh \
	  spar-gate/bin/spar-claude spar-gate/bin/spar-codex spar-gate/bin/spar-payload-scan \
	  spar-gate/launcher spar-gate/public-vectors.json; do \
	  if [[ ! -e $$path && ! -L $$path ]]; then echo "ok:   activation artifact absent: $$path"; \
	  else echo "FAIL: activation artifact remains: $$path"; fail=1; fi; \
	done; \
	if grep -Fqx '#!/bin/bash -p' claude-code/.local/bin/spar-claude && \
	  grep -Fqx '#!/bin/bash -p' codex/.local/bin/spar-codex && \
	  grep -Fqx '#!/usr/bin/python3 -I' claude-code/.local/bin/spar-payload-scan; then \
	  echo "ok:   spar bridge interpreter isolation"; \
	else echo "FAIL: spar bridge interpreter isolation drifted"; fail=1; fi; \
	for b in claude-code/.local/bin/spar-claude codex/.local/bin/spar-codex; do \
	  if grep -Fq "HANDOFF_RE='^/var/tmp/spar-" "$$b" && grep -Fq 'validate_handoff()' "$$b" && \
	    grep -Fq 'stat -c '\''%h'\''' "$$b" && grep -Fq 'stat -c '\''%a'\''' "$$b" && \
	    grep -Fq 'realpath -e --' "$$b" && grep -Fq 'clean_handoff()' "$$b" && \
	    grep -Fq 'flush_handoff()' "$$b" && grep -Fq 'sync -f --' "$$b" && \
	    grep -Fq '[[ -e $$root || -L $$root ]] || return 0' "$$b"; then \
	    echo "ok:   $${b##*/} private handoff lifecycle"; \
	  else echo "FAIL: $${b##*/} private handoff lifecycle drifted"; fail=1; fi; \
	done; \
	python3 tests/config-contracts.py || { echo "FAIL: config syntax or security contract drifted"; fail=1; }; \
	python3 tests/docs-contracts.py || { echo "FAIL: documentation ownership or workflow contract drifted"; fail=1; }; \
	skill_frontmatter_keys() { \
	  awk 'NR == 1 { next } /^---$$/ { exit } /^[A-Za-z0-9_-]+:/ { key=$$1; sub(/:$$/, "", key); print key }' "$$1"; \
	}; \
	frontmatter_ok=1; \
	for s in \
	  claude-code/.claude/skills/commit/SKILL.md \
	  codex/.agents/skills/commit/SKILL.md \
	  opencode/.config/opencode/skills/commit/SKILL.md \
	  codex/.agents/skills/spar/SKILL.md \
	  opencode/.config/opencode/skills/spar/SKILL.md; do \
	  diff -q <(skill_frontmatter_keys "$$s") <(printf 'name\ndescription\n') > /dev/null || frontmatter_ok=0; \
	done; \
	diff -q <(skill_frontmatter_keys claude-code/.claude/skills/spar/SKILL.md) <(printf 'name\ndescription\nallowed-tools\n') > /dev/null || frontmatter_ok=0; \
	if [[ $$frontmatter_ok == 1 ]]; then \
	  echo "ok:   workflow skill frontmatter contracts"; \
	else echo "FAIL: workflow skill frontmatter drifted"; fail=1; fi; \
	if grep -Fqx -- '- Persistent file-content changes use native edit tools, so each change surfaces a reviewable diff. Before a grouped patch runs, validate every source and move destination against the applicable containment and sensitive-path controls. When no all-target validator enforces those checks, modify exactly one file per patch call.' claude-code/.claude/rules/shared-guidance.md; then \
	  echo "ok:   all-target apply_patch guidance"; \
	else echo "FAIL: all-target apply_patch guidance missing"; fail=1; fi; \
	if node --experimental-strip-types tests/reviewed-writes.mjs; then \
	  echo "ok:   opencode all-target patch plugin"; \
	else echo "FAIL: opencode all-target patch plugin drifted"; fail=1; fi; \
	if grep -Fq '/var/tmp/spar-<session-id>/' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer-id' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer bridge'\''s `init` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer bridge'\''s `clean` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'bridge'\''s `flush` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'bridge'\''s `status` mode' claude-code/.claude/skills/spar/SKILL.md; then \
	  echo "ok:   spar skills use private OS temp handoffs"; \
	else echo "FAIL: spar handoff protocol drifted"; fail=1; fi; \
	if grep -Fq 'spar-brainstorm.md' claude-code/.local/bin/spar-claude && \
	  grep -Fq 'spar-brainstorm.md' codex/.local/bin/spar-codex && \
	  grep -Fq 'only H'"'"'s approval of each exact candidate authorizes a commit' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'leaving the worktree intact' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'never alter or exempt that artifact merely to pass' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'plan and build are primary checkpoints' opencode/.config/opencode/commands/spar.md; then \
	  echo "ok:   spar authority and artifact-integrity controls"; \
	else echo "FAIL: spar authority or artifact-integrity controls drifted"; fail=1; fi; \
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	for s in commit spar; do \
	  synced=1; \
	  for copy in "codex/.agents/skills/$$s/SKILL.md" "opencode/.config/opencode/skills/$$s/SKILL.md"; do \
	    diff -q \
	      <(awk '/^## Reviewer incantations$$/{skip=1; next} /^## /{skip=0} !skip' "claude-code/.claude/skills/$$s/SKILL.md" | grep -v -e 'allowed-tools' -e 'Co-Authored-By') \
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
	shellcheck -s bash $(SHELLCHECK_FILES)
	@echo "ok:   shellcheck clean"
