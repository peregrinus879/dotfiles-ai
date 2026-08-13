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
	  "$$HOME/.claude/skills/spar/SKILL.md=claude-code/.claude/skills/spar/SKILL.md" \
	  "$$HOME/.local/bin/spar-claude=claude-code/.local/bin/spar-claude" \
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
	  if [[ "$$(readlink -f "$$target")" == "$$(readlink -f "$$src")" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done; \
	if bash -n claude-code/.claude/statusline.sh; then echo "ok:   bash -n statusline.sh"; else echo "FAIL: bash -n statusline.sh"; fail=1; fi; \
	for b in spar-claude spar-codex; do \
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
	if command -v python3 > /dev/null; then \
	  if python3 -c 'import tomllib; tomllib.load(open("codex/.codex/config.toml","rb"))' 2>/dev/null; then \
	    echo "ok:   valid TOML codex/.codex/config.toml"; \
	  else echo "FAIL: invalid TOML codex/.codex/config.toml"; fail=1; fi; \
	  if python3 -c 'import tomllib; d=tomllib.load(open("codex/.codex/config.toml","rb")); p=d["permissions"]["reviewed-writes"]; fs=p["filesystem"]; wr=fs[":workspace_roots"]; assert d["approval_policy"]=="on-request" and d["approvals_reviewer"]=="user" and d["default_permissions"]=="reviewed-writes" and "sandbox_mode" not in d; assert p["extends"]==":read-only" and p["network"]["enabled"] is False; assert ":minimal" not in fs and fs[":tmpdir"]=="write" and fs[":slash_tmp"]=="write" and fs["glob_scan_max_depth"]==64; assert wr["."]=="read"; assert all(fs[k]=="deny" for k in ("~/.aws","~/.config/gh/hosts.yml","~/.docker/config.json","~/.gnupg","~/.kube","~/.local/share/opencode/auth.json","~/.netrc","~/.npmrc","~/.pypirc","~/.ssh")); assert all(wr[k]=="deny" for k in (".env",".env.*","secrets","**/*.key","**/*.pem","**/*credentials*")); assert wr[".env.example"]=="read"' 2>/dev/null; then \
	    echo "ok:   codex reviewed-writes profile (human review, offline, OS temp writes)"; \
	  else echo "FAIL: codex reviewed-writes profile drifted"; fail=1; fi; \
	else echo "note: python3 not found, skipping TOML validity check"; fi; \
	if command -v jq > /dev/null; then \
	  for f in claude-code/.claude/settings.json opencode/.config/opencode/opencode.json opencode/.config/opencode/tui.json .claude/settings.json opencode.json; do \
	    if jq empty "$$f" > /dev/null 2>&1; then echo "ok:   valid JSON $$f"; else echo "FAIL: invalid JSON $$f"; fail=1; fi; \
	  done; \
	  if jq -e '.permission.bash | to_entries | (map(.key) | index("* > *")) as $$i | if $$i == null then false else .[$$i:] | all(.value != "allow") end' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode bash permission order (no allow after guards)"; \
	  else echo "FAIL: opencode bash permission order (guards and denies must be the final entries)"; fail=1; fi; \
	  if jq -e '.permission.bash["spar-claude *"] == "allow" and (.permission.bash | has("claude -p *") | not)' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode claude bridge allow (spar-claude only, no raw claude -p)"; \
	  else echo "FAIL: opencode claude bridge allow (need spar-claude allow, no claude -p entry)"; fail=1; fi; \
	  if jq -e '.permission.edit | to_entries == [{"key":"*","value":"ask"},{"key":"**/*.key","value":"deny"},{"key":"**/*.pem","value":"deny"},{"key":".env","value":"deny"},{"key":"secrets/**","value":"deny"},{"key":"~/.aws/**","value":"deny"},{"key":"~/.gnupg/**","value":"deny"}]' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode top-level edit map (persistent edits ask, sensitive edits deny)"; \
	  else echo "FAIL: opencode top-level edit map drifted"; fail=1; fi; \
	  if jq -e '(.agent.build | not) and (.permission.edit | to_entries[0] == {"key":"*","value":"ask"})' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode build inherits persistent edit review"; \
	  else echo "FAIL: opencode build edit review drifted"; fail=1; fi; \
	  if jq -e '.agent.plan.permission.edit | to_entries == [{"key":"*","value":"deny"}]' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode plan edit deny"; \
	  else echo "FAIL: opencode plan edit deny missing"; fail=1; fi; \
	  if jq -e '.permission.read["*"] == "allow" and .permission.read[".env.example"] == "allow" and .permission.read[".env"] == "deny" and .permission.read[".env.*"] == "deny" and .permission.read["~/.ssh/**"] == "deny" and .permission.external_directory["*"] == "ask" and .permission.external_directory["~/.ssh/**"] == "deny"' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode sensitive read and external-directory denies"; \
	  else echo "FAIL: opencode sensitive read or external-directory rules drifted"; fail=1; fi; \
	  if jq -e '(.permissions.ask | index("Edit") != null and index("Write") != null)' \
	    claude-code/.claude/settings.json > /dev/null; then \
	    echo "ok:   claude persistent Edit and Write review"; \
	  else echo "FAIL: claude edit asks drifted"; fail=1; fi; \
	  if jq -e '.permission.bash["*"] == "ask" and (.permission.bash | has("gh api") | not) and (.permission.bash | has("gh api *") | not) and (.permission.bash | has("codex *") | not) and (.permission.bash | has("claude -p *") | not)' \
	    opencode/.config/opencode/opencode.json > /dev/null; then \
	    echo "ok:   opencode has no broad shell, gh api, or raw reviewer allow"; \
	  else echo "FAIL: opencode broad shell or unsafe CLI allow found"; fail=1; fi; \
	else echo "note: jq not found, skipping JSON validity checks"; fi; \
	if grep -Fqx -- '- Persistent file-content changes use native edit tools, so each file gets its own approval prompt and diff. An `apply_patch` call modifies exactly one file; never bundle multiple files into one patch.' claude-code/.claude/rules/shared-guidance.md && \
	  grep -Fqx -- '- An `apply_patch` call must modify exactly one file; never bundle multiple files into one patch.' opencode/.config/opencode/AGENTS.md; then \
	  echo "ok:   one-file apply_patch guidance"; \
	else echo "FAIL: one-file apply_patch guidance missing"; fail=1; fi; \
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
	-rm -f ~/.claude/agents ~/.claude/rules ~/.claude/skills
	-rm -f ~/.codex/AGENTS.md
	-rm -f ~/.agents/skills/commit ~/.agents/skills/spar
	-rm -f ~/.config/opencode ~/.config/opencode/agents ~/.config/opencode/commands \
	  ~/.config/opencode/modes ~/.config/opencode/plugins ~/.config/opencode/skills \
	  ~/.config/opencode/themes ~/.config/opencode/tools
	-rm -f ~/.claude/settings.json

lint:
	shellcheck -s bash claude-code/.claude/statusline.sh claude-code/.local/bin/spar-claude codex/.local/bin/spar-codex
	@echo "ok:   shellcheck clean"
