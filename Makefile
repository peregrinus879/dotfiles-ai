# Maintenance automation for EyrAgents. Run from the repo root on any machine.
# The package list here is the single source of truth for the stow command sets.
# Stow runs without directory folding so every managed parent under $HOME stays
# a real directory and only leaf files are links.

SHELL := /bin/bash
PACKAGES := agents claude-code codex opencode
STOW := stow --no-folding --ignore='__pycache__' -t ~
SHELLCHECK_FILES := claude-code/.claude/statusline.sh \
  templates/hooks/commit-gate $(wildcard agents/.local/bin/*) \
  claude-code/.local/bin/spar-claude \
  codex/.local/bin/spar-codex \
  $(wildcard scripts/*.sh tests/*.sh)

.PHONY: help stow unstow dry-run restow require-clone install-gate migrate-codex-config lint test check verify-deploy verify clean

help:
	@echo "Targets:"
	@echo "  stow           Clean dangling links, stow all packages into ~, install the commit gate, reconcile the Codex config"
	@echo "  unstow         Remove all package links"
	@echo "  dry-run        Preview Stow actions"
	@echo "  restow         Clean, refresh links, install the commit gate, and reconcile the Codex config (refuses from a non-deployed clone)"
	@echo "  install-gate   Install templates/hooks/commit-gate as a real file under ~/.agents/hooks"
	@echo "  migrate-codex-config  Reconcile ~/.codex/config.toml with the template, keeping host tables"
	@echo "  lint           ShellCheck, Python, and plugin syntax checks over managed scripts"
	@echo "  test           Fast tests: configuration boundaries, bridges, statusline, preparation, commit gate"
	@echo "  check          Repository checks: package symlinks resolve, owned JSON and TOML parse, then test (runs in CI)"
	@echo "  verify-deploy  Check every package file resolves to its deployed target"
	@echo "  verify         lint, check, and verify-deploy"
	@echo "  clean          Remove dangling links that point into this repository's packages"

stow: clean
	$(STOW) -v $(PACKAGES)
	$(MAKE) --no-print-directory install-gate
	bash scripts/prepare-stow.sh --migrate-codex-config

unstow:
	$(STOW) -D -v $(PACKAGES)

dry-run:
	$(STOW) -n -v $(PACKAGES)

restow: require-clone clean
	$(STOW) -R -v $(PACKAGES)
	$(MAKE) --no-print-directory install-gate
	bash scripts/prepare-stow.sh --migrate-codex-config

# The hook runs outside the Codex sandbox, so its executable lives outside
# every workspace as a real file the sandboxed agent cannot write.
GATE := $(HOME)/.agents/hooks/commit-gate
install-gate:
	install -D -m 755 templates/hooks/commit-gate $(GATE)
	@echo "ok:   commit gate installed at $(GATE)"

# A managed endpoint that is a link must resolve into this clone; a reference
# clone of the same repository must never redeploy the packages from itself.
require-clone:
	@fail=0; \
	while IFS= read -r -d '' src; do \
	  target="$$HOME/$${src#*/}"; \
	  [[ -L $$target ]] || continue; \
	  case $$(readlink -f -- "$$target") in \
	    "$(CURDIR)"/*) ;; \
	    *) echo "FAIL: $$target is linked from another clone; run make stow from the deployed clone"; fail=1 ;; \
	  esac; \
	done < <(git ls-files -z --cached --others --exclude-standard -- $(PACKAGES)); \
	exit $$fail

migrate-codex-config:
	bash scripts/prepare-stow.sh --migrate-codex-config

lint:
	shellcheck -s bash $(SHELLCHECK_FILES)
	python3 -I -c 'import sys; [compile(open(p, "rb").read(), p, "exec") for p in sys.argv[1:]]' \
	  claude-code/.local/bin/spar-payload-scan scripts/reconcile-codex-config.py tests/config-contracts.py
	node --check opencode/.config/opencode/plugins/commit-gate.js
	@echo "ok:   lint"

test:
	python3 tests/config-contracts.py
	bash tests/statusline.sh
	bash tests/prepare-stow.sh
	bash tests/spar-bridges.sh
	bash tests/commit-gate.sh
	@echo "ok:   test"

check:
	@fail=0; \
	while IFS= read -r -d '' link; do \
	  echo "FAIL: package symlink does not resolve: $$link"; fail=1; \
	done < <(find $(PACKAGES) -type l -xtype l -print0); \
	[[ $$fail -eq 0 ]] && echo "ok:   package symlinks resolve"; \
	while IFS= read -r -d '' f; do \
	  case $$f in \
	    *.toml) python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$$f" ;; \
	    *) python3 -c 'import sys, json; json.load(open(sys.argv[1], encoding="utf-8"))' "$$f" ;; \
	  esac && echo "ok:   $$f parses" || { echo "FAIL: $$f does not parse"; fail=1; }; \
	done < <(git ls-files -z -- '*.json' '*.toml'); \
	exit $$fail
	@$(MAKE) --no-print-directory test
	@echo "ok:   check"

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
	while IFS= read -r dir; do \
	  target="$$HOME/$${dir#*/}"; \
	  if [[ -d $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: managed directory is folded or missing: $$target"; fail=1; fi; \
	done < <(git ls-files --cached --others --exclude-standard -- $(PACKAGES) | \
	  while IFS= read -r src; do [[ -e $$src || -L $$src ]] || continue; dir=$${src%/*}; \
	  while [[ $$dir == */* ]]; do echo "$$dir"; dir=$${dir%/*}; done; done | sort -u); \
	for path in package.json package-lock.json bun.lock bun.lockb node_modules; do \
	  target="opencode/.config/opencode/$$path"; \
	  if [[ ! -e $$target && ! -L $$target ]]; then :; \
	  else echo "FAIL: generated OpenCode state reached the package source: $$target"; fail=1; fi; \
	done; \
	for b in spar-claude spar-codex spar-payload-scan; do \
	  if [[ -x "$$HOME/.local/bin/$$b" ]]; then echo "ok:   $$b executable"; else echo "FAIL: $$b missing or not executable"; fail=1; fi; \
	done; \
	if [[ -f "$(GATE)" && ! -L "$(GATE)" && -x "$(GATE)" ]] && cmp -s templates/hooks/commit-gate "$(GATE)"; then \
	  echo "ok:   installed commit gate matches templates/hooks/commit-gate"; \
	else echo "FAIL: installed commit gate missing, linked, or drifted (run make restow)"; fail=1; fi; \
	config="$$HOME/.codex/config.toml"; \
	if [[ -f $$config && ! -L $$config && -O $$config && $$(stat -c '%a' -- "$$config") =~ ^[46]00$$ ]] && \
	  python3 scripts/reconcile-codex-config.py check templates/codex/config.toml "$$config" && \
	  HOST_CODEX_CONFIG="$$config" python3 tests/config-contracts.py >/dev/null; then \
	  echo "ok:   host Codex config carries the template boundaries"; \
	else echo "FAIL: host Codex config is missing, exposed, or drifted from the template (run make restow)"; fail=1; fi; \
	if [[ -e "$$HOME/.config/opencode/opencode.jsonc" ]]; then \
	  echo "FAIL: stray ~/.config/opencode/opencode.jsonc shadows the stowed config"; fail=1; \
	else echo "ok:   no stray opencode.jsonc"; fi; \
	exit $$fail

verify: lint check verify-deploy
	@echo "ok:   verify"

clean:
	bash scripts/prepare-stow.sh
