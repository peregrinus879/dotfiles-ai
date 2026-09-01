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
	  "$$HOME/.codex/config.toml=codex/.codex/config.toml" \
	  "$$HOME/.codex/AGENTS.md=codex/.codex/AGENTS.md" \
	  "$$HOME/.agents/skills/commit/SKILL.md=codex/.agents/skills/commit/SKILL.md" \
	  "$$HOME/.agents/skills/spar/SKILL.md=codex/.agents/skills/spar/SKILL.md" \
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
	for b in spar-claude spar-codex spar-payload-scan; do \
	  if [[ -x "$$HOME/.local/bin/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   bash -n statusline.sh"; else echo "FAIL: bash -n statusline.sh"; fail=1; fi; \
	bash -n tests/statusline-state.sh && bash tests/statusline-state.sh || { echo "FAIL: statusline runtime-state controls"; fail=1; }; \
	bash -n scripts/prepare-stow.sh tests/prepare-stow.sh tests/spar-bridges.sh || { echo "FAIL: managed shell syntax"; fail=1; }; \
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
	if grep -Fq 'Probe versions are historical evidence, not installed-version pins or routine synchronization targets.' AGENTS.md && \
	  grep -Fq 'Routine client updates require no dependency edit' README.md && \
	  grep -Fq 'Routine updates do not trigger config, code, dependency, test, or documentation edits.' docs/maintenance.md; then \
	  echo "ok:   tool release-maintenance policy documented"; \
	else echo "FAIL: tool release-maintenance policy drifted"; fail=1; fi; \
	if grep -Fqx -- '- Persistent file-content changes use native edit tools, so each change surfaces a reviewable diff. Before a grouped patch runs, validate every source and move destination against the applicable containment and sensitive-path controls. When no all-target validator enforces those checks, modify exactly one file per patch call.' claude-code/.claude/rules/shared-guidance.md; then \
	  echo "ok:   all-target apply_patch guidance"; \
	else echo "FAIL: all-target apply_patch guidance missing"; fail=1; fi; \
	if grep -Fq 'Plan approval authorizes the listed edits, verification, reviewer calls, and deployment steps, never a commit.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Execute one approved commit unit at a time.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Before every commit, run `/commit`' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Commit only after H approves that exact candidate.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Approve, commit, continue (Recommended) | Approve, commit, discuss | Revise | Reject' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Continue only with remaining work authorized by H' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'A clear task request authorizes value-based read-only spar reviewer calls inside its scope.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Plan and build are the primary `/spar` checkpoints, not mandatory gates' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'treat `/spar` build review as a primary checkpoint before push' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Trivial work may skip a formal plan, but never the exact pre-commit review.' claude-code/.claude/rules/shared-guidance.md; then \
	  echo "ok:   autonomous-work commit checkpoints"; \
	else echo "FAIL: autonomous-work commit checkpoints drifted"; fail=1; fi; \
	if grep -Fq 'do not alter, stage, or temporarily revert the unrelated hunks' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Approve, commit, continue (Recommended)` first, followed by `Approve, commit, discuss`, `Revise`, and `Reject`' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Any change to one of them requires a refreshed packet and selector.' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Repeat this complete compact cheat sheet in every review packet' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq '`<M-w>`: cycle the input, hunk list, and preview panes.' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq '`<M-p>`: toggle the preview. `<M-m>`: maximize or restore' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq '`<Enter>`: open the selected file and close the picker.' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Avoid `<Tab>`, which stages, and `<C-r>`, which restores' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'A `Revise` or `Reject` choice triggers a free-form follow-up when comments are not already present.' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq '`Revise` updates the current candidate but never authorizes a commit' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'remove all candidate-owned changes, then stop or build a new candidate from the comments' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'built-in custom answer is the comment path' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Proceed only after `Approve, commit, continue` or `Approve, commit, discuss`' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'read-only terminal fallback' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq '`<C-f>`' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq '`<C-c>`' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq '`<C-d>`' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq '`<C-u>`' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq '`<C-w>`' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq '`<C-b>`' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq 'temporarily revert the unrelated hunks with the file edit tools' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq 'Approve and commit (Recommended)' claude-code/.claude/skills/commit/SKILL.md; then \
	  echo "ok:   exact-diff commit review and LazyVim guidance"; \
	else echo "FAIL: exact-diff commit review drifted"; fail=1; fi; \
	if grep -Fq 'Screen the message, paths, complete diff, and intended new-file contents' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'A binary or opaque candidate artifact that cannot be reviewed semantically' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Bind the review to a credential-free logical destination and audience' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'A destination state can narrow the review only when it is confirmed current' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'never through `!` or pasted session content' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'transient authenticated transfer endpoints remain opaque transport data' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq 'Reconcile every inventoried commit-metadata, tag-metadata, path-version, action-metadata, and external-artifact record' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fq '## Candidate privacy screen' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq '## Publication review and push hint' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'A no-ref-update pull request or release is valid when stated explicitly.' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Use it to narrow the review only when it is confirmed current' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'every included commit and annotated tag' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'every action-metadata field and value' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Any count mismatch, unmatched record, truncation, decode failure, unsupported object' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'Never rely on a bare `git push`, a mutable local source ref, `push.default`, or `remote.*.push`' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'A differential-history review also requires an execution-time expected-old-value guard' claude-code/.claude/skills/commit/SKILL.md && \
	  grep -Fq 'message, audience, and scratch disposition' AGENTS.md && \
	  grep -Fq 'withholds publication-ready claims and push hints' AGENTS.md && \
	  grep -Fq 'withholds any publication-ready claim or push hint' README.md && \
	  grep -Fq 'Destination state narrows the review only when confirmed current' README.md && \
	  grep -Fq 'publication-review decision 2026-08-30' docs/maintenance.md && \
	  ! grep -Fq 'After committing, show the push command' claude-code/.claude/skills/commit/SKILL.md; then \
	  echo "ok:   commit privacy and publication review contracts"; \
	else echo "FAIL: commit privacy or publication review drifted"; fail=1; fi; \
	if ! grep -Fq 'disable-model-invocation' claude-code/.claude/skills/commit/SKILL.md && \
	  ! grep -Fq 'disable-model-invocation' claude-code/.claude/skills/spar/SKILL.md; then \
	  echo "ok:   Claude managed skills are model-invocable"; \
	else echo "FAIL: Claude managed skill invocation gate drifted"; fail=1; fi; \
	if node --experimental-strip-types tests/reviewed-writes.mjs && \
	  ! grep -Fq 'spar-scratch' opencode/.config/opencode/plugins/reviewed-writes.ts; then \
	  echo "ok:   opencode all-target patch plugin"; \
	else echo "FAIL: opencode all-target patch plugin drifted"; fail=1; fi; \
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
	  grep -Fq '**Review judgment:** Plan and build are the primary spar checkpoints, not mandatory gates.' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'fixed calls, rounds, fan-outs, and review depth never substitute for judgment' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '**Plan review:** Consider spar after research and analysis and before presenting the final plan.' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '**Build review:** Consider spar after all approved commits and before push.' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'complete `git diff --binary <base>..HEAD`' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'latest approved plan and Decision Rationale' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'only H'"'"'s approval of each exact candidate authorizes a commit' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'decision-ready input, not option approval' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'leaving the worktree intact' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'never alter or exempt that artifact merely to pass' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'hard ceiling of round 2' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'mandatory after all planned commits' claude-code/.claude/skills/spar/SKILL.md && \
	  ! grep -Fq 'repeating at most one call' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'plan and build are primary checkpoints' opencode/.config/opencode/commands/spar.md; then \
	  echo "ok:   spar value-based checkpoint contracts"; \
	else echo "FAIL: spar value-based checkpoint contracts drifted"; fail=1; fi; \
	if grep -Fq 'Begin the artifact with a target brief' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq '`Decision Rationale`' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'without repeating completed research' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'Include an `Evidence Pack`' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'literal captured output' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'You review offline' claude-code/.claude/skills/spar/SKILL.md && \
	  grep -Fq 'rather than reopening them solely because another approach exists' claude-code/.claude/skills/spar/SKILL.md && \
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
	exit $$fail

clean:
	bash scripts/prepare-stow.sh

lint:
	shellcheck -s bash $(SHELLCHECK_FILES)
	@echo "ok:   shellcheck clean"
