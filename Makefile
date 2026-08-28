# Maintenance automation for EyrAgents. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.

SHELL := /bin/bash
PACKAGES := claude-code codex opencode
SHELLCHECK_FILES := claude-code/.claude/statusline.sh \
  claude-code/.claude/hooks/spar-handoff-approve.sh \
  claude-code/.local/bin/spar-claude \
  codex/.local/bin/spar-codex \
  $(wildcard scripts/*.sh tests/*.sh)

.PHONY: help stow unstow dry-run restow verify clean lint

help:
	@echo "Targets:"
	@echo "  stow      Stow all packages into ~"
	@echo "  unstow    Remove all package symlinks"
	@echo "  dry-run   Preview stow actions without making changes"
	@echo "  restow    Re-stow after repo content changes"
	@echo "  verify    Check every intended deployment and run the full verification suite"
	@echo "  clean     Safely prepare managed paths for stow"
	@echo "  lint      ShellCheck over all managed Bash scripts"

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
# GNU Stow ignores .gitignore by default; the three package-internal copies
# control fresh-clone state and are intentionally not deployed.
# Pin layering: structured config contracts live in tests/config-contracts.py;
# prose, script, and skill content pins live here as greps. Negative
# (tombstone) greps carry a dated ledger entry and retire after two years
# unless re-justified there.
verify:
	@fail=0; \
	for command in git node python3 jq readlink realpath sha256sum stat; do \
	  command -v "$$command" > /dev/null || { echo "FAIL: required verifier missing: $$command"; fail=1; }; \
	done; \
	[[ $$fail == 0 ]] || exit $$fail; \
	for src in $$(git ls-files --cached --others --exclude-standard -- $(PACKAGES)); do \
	  [[ "$$src" == */.gitignore ]] && continue; \
	  target="$$HOME/$${src#*/}"; \
	  target_resolved=$$(readlink -f -- "$$target"); \
	  src_resolved=$$(readlink -f -- "$$src"); \
	  if [[ -n $$target_resolved && -n $$src_resolved && $$target_resolved == "$$src_resolved" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done; \
	for pair in "$$HOME/.claude/CLAUDE.md=claude-code/.claude/CLAUDE.md" \
	  "$$HOME/.claude/settings.json=claude-code/.claude/settings.json" \
	  "$$HOME/.claude/statusline.sh=claude-code/.claude/statusline.sh" \
	  "$$HOME/.claude/hooks/spar-handoff-approve.sh=claude-code/.claude/hooks/spar-handoff-approve.sh" \
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
	  "$$HOME/.config/opencode/package.json=opencode/.config/opencode/package.json" \
	  "$$HOME/.config/opencode/package-lock.json=opencode/.config/opencode/package-lock.json" \
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
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   bash -n statusline.sh"; else echo "FAIL: bash -n statusline.sh"; fail=1; fi; \
	bash -n tests/statusline-state.sh && bash tests/statusline-state.sh || { echo "FAIL: statusline runtime-state controls"; fail=1; }; \
	if bash -n scripts/prepare-stow.sh tests/prepare-stow.sh && bash tests/prepare-stow.sh; then \
	  echo "ok:   non-destructive stow preparation"; \
	else echo "FAIL: non-destructive stow preparation"; fail=1; fi; \
	bash -n tests/spar-bridges.sh && bash tests/spar-bridges.sh || { echo "FAIL: spar bridge payload controls"; fail=1; }; \
	bash -n tests/project-config-isolation.sh && bash tests/project-config-isolation.sh || { echo "FAIL: project config isolation"; fail=1; }; \
	for b in spar-claude spar-codex spar-payload-scan; do \
	  if [[ -x "$$HOME/.local/bin/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if [[ $$(grep -Fc -- '--tools ' claude-code/.local/bin/spar-claude) == 1 ]] && \
	  grep -Fqx '    --tools "Read,Glob,Grep" \' claude-code/.local/bin/spar-claude; then \
	  echo "ok:   spar-claude read-only tool whitelist"; \
	else echo "FAIL: spar-claude read-only tool whitelist missing"; fail=1; fi; \
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
	if grep -Fqx -- '- Persistent file-content changes use native edit tools, so each change surfaces a reviewable diff. An `apply_patch` call modifies exactly one file; never bundle multiple files into one patch.' claude-code/.claude/rules/shared-guidance.md; then \
	  echo "ok:   one-file apply_patch guidance"; \
	else echo "FAIL: one-file apply_patch guidance missing"; fail=1; fi; \
	if grep -Fq 'Plan approval authorizes the listed edits, verification, reviewer calls, and deployment steps, never a commit.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Execute one approved commit unit at a time.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Before every commit, run `/commit`' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Commit only after H approves that exact candidate.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Trivial work may skip a formal plan, but never the exact pre-commit review.' claude-code/.claude/rules/shared-guidance.md; then \
	  echo "ok:   autonomous-work commit checkpoints"; \
	else echo "FAIL: autonomous-work commit checkpoints drifted"; fail=1; fi; \
	if grep -Fq 'do not alter, stage, or temporarily revert the unrelated hunks' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Approve and commit` first, followed by `Request revisions`, `Comment / question`, and `Stop`' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Any change to one of them requires a refreshed packet and selector.' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq 'temporarily revert the unrelated hunks with the file edit tools' claude-code/.claude/skills/commit/SKILL.md; then \
	  echo "ok:   exact-diff commit review preserves unrelated hunks"; \
	else echo "FAIL: exact-diff commit review drifted"; fail=1; fi; \
	if ! grep -Fq 'disable-model-invocation' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq 'disable-model-invocation' claude-code/.claude/skills/spar/SKILL.md; then \
	  echo "ok:   Claude managed skills are model-invocable"; \
	else echo "FAIL: Claude managed skill invocation gate drifted"; fail=1; fi; \
	if node --experimental-strip-types tests/reviewed-writes.mjs && \
	  ! grep -Fq 'spar-scratch' opencode/.config/opencode/plugins/reviewed-writes.ts; then \
	  echo "ok:   opencode one-file patch plugin"; \
	else echo "FAIL: opencode one-file patch plugin drifted"; fail=1; fi; \
	if grep -Fq '/var/tmp/spar-<session-id>/' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '/var/tmp/spar-<session-id>/' codex/.agents/skills/spar/SKILL.md && \
	  grep -Fq '/var/tmp/spar-<session-id>/' opencode/.config/opencode/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer-id' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer-id' codex/.agents/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer-id' opencode/.config/opencode/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer bridge'\''s `init` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'reviewer bridge'\''s `clean` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'bridge'\''s `flush` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'bridge'\''s `status` mode' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'spar-scratch' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'spar-scratch' codex/.agents/skills/spar/SKILL.md && \
	  ! grep -Fq 'spar-scratch' opencode/.config/opencode/skills/spar/SKILL.md; then \
	  echo "ok:   spar skills use private OS temp handoffs"; \
	else echo "FAIL: spar scratch protocol drifted"; fail=1; fi; \
	if grep -Fq '**Brainstorming:**' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'spar-brainstorm.md' claude-code/.local/bin/spar-claude && \
	  grep -Fq 'spar-brainstorm.md' codex/.local/bin/spar-codex && \
	  grep -Fq 'artifact round 1' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'well-formed terminal verdict with zero blockers means GO' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'at most three calls total' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'nine calls across execution gates overall' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'only H'"'"'s approval of that exact candidate authorizes its commit' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'decision-ready, not option approval' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'Any content edit after GO re-enters once' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '**Final integration gate:**' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'never individual edits, commands, or tests' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'leave the worktree intact' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'never alter or exempt that artifact merely to pass' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'do not collapse these modes into plan review' opencode/.config/opencode/commands/spar.md; then \
	  echo "ok:   spar brainstorming and stage-gate contracts"; \
	else echo "FAIL: spar brainstorming or stage-gate contracts drifted"; fail=1; fi; \
	if grep -Fq 'beginning with a target brief' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '`Evidence Pack` section' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'literal captured output' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'You review offline' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'exact decision requested' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'Raw reviewer transcripts are never required' claude-code/.claude/skills/spar/SKILL.md; then \
	  echo "ok:   spar target, evidence, and ruling packets"; \
	else echo "FAIL: spar review context protocol drifted"; fail=1; fi; \
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
	spar_shared_lines=$$(awk '/^## Reviewer incantations$$/{skip=1; next} /^## /{skip=0} !skip' claude-code/.claude/skills/spar/SKILL.md | grep -v -e 'allowed-tools' -e 'Co-Authored-By' | wc -l); \
	if (( spar_shared_lines > 0 && spar_shared_lines <= 67 )); then \
	  echo "ok:   spar shared protocol stays within the 37+30 line budget ($$spar_shared_lines)"; \
	else echo "FAIL: spar shared protocol exceeds the 37+30 line budget ($$spar_shared_lines)"; fail=1; fi; \
	tripwire=$$(sed -n 's/.*version tripwire source: //p' docs/maintenance.md | head -1); \
	if [[ -n $$tripwire ]]; then \
	  if command -v mise > /dev/null && command -v claude > /dev/null; then \
	    current="claude=$$(claude --version 2>/dev/null | awk '{print $$1}') "; \
	    current+=$$(mise ls --current 2>/dev/null | awk '$$1=="codex"||$$1=="opencode"{printf "%s=%s ", $$1, $$2}'); \
	    if [[ -n $$current && $$current != "$$tripwire " ]]; then \
	      echo "WARN: installed versions ($$current) differ from the ledger probe triple ($$tripwire); permission probes may be stale (docs/maintenance.md)"; \
	    fi; \
	  else \
	    echo "note: version tripwire skipped; mise and claude are required"; \
	  fi; \
	fi; \
	exit $$fail

clean:
	bash scripts/prepare-stow.sh

lint:
	shellcheck -s bash $(SHELLCHECK_FILES)
	@echo "ok:   shellcheck clean"
