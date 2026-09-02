# Maintenance automation for EyrAgents. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.

SHELL := /bin/bash
PACKAGES := claude-code codex opencode
SHELLCHECK_FILES := claude-code/.claude/statusline.sh \
  claude-code/.claude/hooks/spar-handoff-approve.sh \
  claude-code/.local/bin/spar-claude \
  codex/.local/bin/spar-codex \
  $(wildcard scripts/*.sh tests/*.sh)

.PHONY: help stow unstow dry-run restow migrate-codex-config lint test verify-deploy canary verify clean

help:
	@echo "Targets:"
	@echo "  stow           Stow all packages into ~"
	@echo "  unstow         Remove all package symlinks"
	@echo "  dry-run        Preview raw Stow actions without running preparation"
	@echo "  restow         Re-stow after repo content changes"
	@echo "  migrate-codex-config  Safely convert Codex config to host-local state"
	@echo "  lint           ShellCheck and syntax checks over managed scripts"
	@echo "  test           Fast tests: configuration boundaries, bridges, plugin, preparation"
	@echo "  verify-deploy  Check every package file resolves to its deployed target"
	@echo "  canary         Live client probes for project isolation flags"
	@echo "  verify         lint, test, verify-deploy, and canary"
	@echo "  clean          Safely prepare managed paths for stow"

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

lint:
	shellcheck -s bash $(SHELLCHECK_FILES)
	python3 -I -c 'import sys; [compile(open(p, "rb").read(), p, "exec") for p in sys.argv[1:]]' \
	  claude-code/.local/bin/spar-payload-scan tests/config-contracts.py
	@echo "ok:   lint"

test:
	python3 tests/config-contracts.py
	node --experimental-strip-types tests/reviewed-writes.mjs
	bash tests/statusline-state.sh
	bash tests/prepare-stow.sh
	bash tests/spar-bridges.sh
	@echo "ok:   test"

# Stow may tree-fold package subdirectories, so compare resolved managed-child
# paths rather than requiring leaf links. Preparation keeps runtime-state roots
# such as ~/.config/opencode real. GNU Stow ignores .gitignore by default; the
# package-internal copies control fresh-clone state and are not deployed.
verify-deploy:
	@fail=0; \
	for command in git readlink stow; do \
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
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	exit $$fail

canary:
	bash tests/project-config-isolation.sh

verify: lint test verify-deploy canary
	@echo "ok:   verify"

clean:
	bash scripts/prepare-stow.sh
