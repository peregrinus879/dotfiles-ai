# Maintenance automation for EyrAgents. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.
# Stow runs without directory folding so every managed parent under $HOME stays
# a real directory and only leaf files are links.

SHELL := /bin/bash
PACKAGES := claude-code codex opencode
STOW := stow --no-folding -t ~
SHELLCHECK_FILES := claude-code/.claude/statusline.sh \
  claude-code/.local/bin/spar-claude \
  codex/.local/bin/spar-codex \
  $(wildcard scripts/*.sh tests/*.sh)

.PHONY: help stow unstow dry-run restow migrate-codex-config lint test verify-deploy verify clean

help:
	@echo "Targets:"
	@echo "  stow           Clean dangling managed links, then stow all packages into ~"
	@echo "  unstow         Remove all package links"
	@echo "  dry-run        Preview Stow actions"
	@echo "  restow         Clean, then refresh links after repo content changes"
	@echo "  migrate-codex-config  Make ~/.codex/config.toml a host-local regular file"
	@echo "  lint           ShellCheck and syntax checks over managed scripts"
	@echo "  test           Fast tests: configuration boundaries, bridges, statusline, preparation"
	@echo "  verify-deploy  Check every package file resolves to its deployed target"
	@echo "  verify         lint, test, and verify-deploy"
	@echo "  clean          Remove dangling links that point into this repository's packages"

stow: clean
	$(STOW) -v $(PACKAGES)

unstow:
	$(STOW) -D -v $(PACKAGES)

dry-run:
	$(STOW) -n -v $(PACKAGES)

restow: clean
	$(STOW) -R -v $(PACKAGES)

migrate-codex-config:
	bash scripts/prepare-stow.sh --migrate-codex-config

lint:
	shellcheck -s bash $(SHELLCHECK_FILES)
	python3 -I -c 'import sys; [compile(open(p, "rb").read(), p, "exec") for p in sys.argv[1:]]' \
	  claude-code/.local/bin/spar-payload-scan tests/config-contracts.py
	@echo "ok:   lint"

test:
	python3 tests/config-contracts.py
	bash tests/statusline.sh
	bash tests/prepare-stow.sh
	bash tests/spar-bridges.sh
	@echo "ok:   test"

# Every non-ignored package file must resolve to the same inode as its
# deployed target, every package directory must be a real directory in $HOME,
# and a retired source must leave no link behind. GNU Stow ignores .gitignore
# files, so they are skipped.
verify-deploy:
	@fail=0; \
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
	  if [[ $$(readlink -f -- "$$target") == "$$(readlink -f -- "$$src")" ]]; then \
	    echo "ok:   $$target resolves into the repo"; \
	  else \
	    echo "FAIL: $$target does not resolve into the repo"; fail=1; \
	  fi; \
	done < <(git ls-files -z --cached --others --exclude-standard -- $(PACKAGES)); \
	while IFS= read -r -d '' dir; do \
	  target="$$HOME/$${dir#*/}"; \
	  if [[ -d $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: managed directory is folded or missing: $$target"; fail=1; fi; \
	done < <(find $(PACKAGES) -mindepth 1 -type d -not -path '*/.git/*' -print0); \
	for path in package.json package-lock.json bun.lock bun.lockb node_modules; do \
	  target="opencode/.config/opencode/$$path"; \
	  if [[ ! -e $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: generated OpenCode state reached the package source: $$target"; fail=1; fi; \
	done; \
	for b in spar-claude spar-codex spar-payload-scan; do \
	  if [[ -x "$$HOME/.local/bin/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	exit $$fail

verify: lint test verify-deploy
	@echo "ok:   verify"

clean:
	bash scripts/prepare-stow.sh
