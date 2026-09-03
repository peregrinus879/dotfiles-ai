#!/usr/bin/env bash
# Deployment preparation: dangling managed links are removed, everything else
# is preserved, no-folding Stow keeps every parent real, and Codex config
# migration produces a host-local owner-only file from the right source.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# A clone named like the real repository, with the package shape that matters.
make_clone() {
  local repo=$1
  mkdir -p "$repo/claude-code/.claude/rules" "$repo/claude-code/.claude/skills/commit" \
    "$repo/claude-code/.local/bin" "$repo/codex/.codex" "$repo/codex/.agents/skills/commit" \
    "$repo/codex/.local/bin" "$repo/opencode/.config/opencode/skills/commit" \
    "$repo/scripts" "$repo/templates/codex"
  printf 'tracked\n' >"$repo/claude-code/.claude/settings.json"
  printf 'guidance\n' >"$repo/claude-code/.claude/rules/shared-guidance.md"
  printf 'skill\n' >"$repo/claude-code/.claude/skills/commit/SKILL.md"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/spar-claude"
  printf 'tracked\n' >"$repo/codex/.codex/config.toml"
  ln -s ../../claude-code/.claude/rules/shared-guidance.md "$repo/codex/.codex/AGENTS.md"
  ln -s ../../../../claude-code/.claude/skills/commit/SKILL.md "$repo/codex/.agents/skills/commit/SKILL.md"
  printf 'tracked\n' >"$repo/codex/.local/bin/spar-codex"
  printf '{}\n' >"$repo/opencode/.config/opencode/opencode.json"
  ln -s ../../../../../claude-code/.claude/skills/commit/SKILL.md "$repo/opencode/.config/opencode/skills/commit/SKILL.md"
  cp -- "$ROOT/scripts/prepare-stow.sh" "$repo/scripts/prepare-stow.sh"
  cp -- "$ROOT/scripts/reconcile-codex-config.py" "$repo/scripts/reconcile-codex-config.py"
  cp -- "$ROOT/templates/codex/config.toml" "$repo/templates/codex/config.toml"
}

toml_value() { # file dotted.key
  python3 -c 'import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
for part in sys.argv[2].split("."):
    data = data[part]
print(data)' "$1" "$2"
}

prepare() { HOME=$1 bash "$2/scripts/prepare-stow.sh"; }
migrate() { HOME=$1 bash "$2/scripts/prepare-stow.sh" --migrate-codex-config; }
deploy() { HOME=$1 stow --no-folding -R -d "$2" -t "$1" claude-code codex opencode; }

case_clean_links() {
  local home="$TMP/clean/home" repo="$TMP/clean/eyragents" old="$TMP/clean/old/eyragents"
  mkdir -p "$home/.claude/skills" "$home/.codex" "$home/.agents/skills" "$home/.local/bin" "$home/.config/opencode"
  make_clone "$repo"
  ln -s "$old/claude-code/.claude/hooks" "$home/.claude/hooks"
  ln -s "$old/codex/.codex/config.toml" "$home/.codex/config.toml"
  ln -s "../../Projects/renamed-clone/codex/.agents/skills/retired" "$home/.agents/skills/retired"
  ln -s "$repo/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  ln -s /usr/share/nothing/here "$home/.claude/skills/vendor"
  ln -s "$old/unrelated/codex/thing" "$home/.local/bin/thing"
  ln -s "$TMP/clean/other/eyragents/codex/tool" "$home/.local/bin/tool"
  printf 'user data\n' >"$home/.config/opencode/opencode.json"
  prepare "$home" "$repo"
  [[ ! -e $home/.claude/hooks && ! -L $home/.claude/hooks ]] || fail "dangling managed directory link remains"
  [[ ! -L $home/.codex/config.toml ]] || fail "dangling managed leaf link remains"
  [[ ! -L $home/.agents/skills/retired ]] || fail "dangling link from a renamed clone remains"
  [[ -L $home/.claude/settings.json ]] || fail "resolving managed link was removed"
  [[ -L $home/.claude/skills/vendor ]] || fail "unmanaged dangling link was removed"
  [[ -L $home/.local/bin/thing ]] || fail "dangling link outside the package layout was removed"
  [[ -L $home/.local/bin/tool ]] || fail "dangling link with the repository name but no package entry was removed"
  [[ $(<"$home/.config/opencode/opencode.json") == "user data" ]] || fail "regular file was changed"
}

case_no_folding() {
  local home="$TMP/fold/home" repo="$TMP/fold/eyragents" root="$TMP/fold/home/.config/opencode"
  mkdir -p "$home/.config" "$home/.local"
  make_clone "$repo"
  # Folded links as an older Stow deployment created them: relative, so Stow
  # still recognizes them as its own and unfolds them.
  ln -s ../eyragents/claude-code/.claude "$home/.claude"
  ln -s ../../eyragents/opencode/.config/opencode "$home/.config/opencode"
  prepare "$home" "$repo"
  deploy "$home" "$repo" >/dev/null 2>&1 || fail "restow could not replace folded links"
  for path in .claude .claude/rules .claude/skills/commit .codex .agents/skills/commit .local/bin .config/opencode .config/opencode/skills/commit; do
    [[ -d $home/$path && ! -L $home/$path ]] || fail "$path is not a real directory after no-folding stow"
  done
  [[ $(readlink -f -- "$home/.claude/rules/shared-guidance.md") == "$repo/claude-code/.claude/rules/shared-guidance.md" ]] ||
    fail "leaf link does not resolve into the clone"
  [[ $(readlink -f -- "$home/.codex/AGENTS.md") == "$repo/claude-code/.claude/rules/shared-guidance.md" ]] ||
    fail "package symlink did not deploy"
  [[ $(readlink -f -- "$home/.agents/skills/commit/SKILL.md") == "$repo/claude-code/.claude/skills/commit/SKILL.md" ]] ||
    fail "skill symlink did not deploy"
  printf 'host-local\n' >"$root/package.json"
  mkdir "$root/node_modules"
  prepare "$home" "$repo"
  deploy "$home" "$repo" >/dev/null 2>&1 || fail "restow failed with host-local generated state present"
  [[ ! -L $root/package.json && $(<"$root/package.json") == "host-local" && -d $root/node_modules ]] ||
    fail "restow changed host-local generated state"
  [[ ! -e $repo/opencode/.config/opencode/package.json ]] || fail "generated state reached the package source"
  HOME=$home stow --no-folding -D -d "$repo" -t "$home" claude-code codex opencode >/dev/null 2>&1 ||
    fail "unstow failed"
  [[ ! -e $home/.claude/rules/shared-guidance.md && -f $root/package.json ]] || fail "unstow removed the wrong things"
}

case_migration() {
  local home="$TMP/migrate/home" repo="$TMP/migrate/eyragents" config
  mkdir -p "$home/.codex"
  make_clone "$repo"
  config="$home/.codex/config.toml"

  migrate "$home" "$repo"
  [[ -f $config && ! -L $config && $(stat -c '%a' -- "$config") == 600 ]] || fail "seeded config is not an owner-only regular file"
  cmp -s -- "$config" "$repo/templates/codex/config.toml" || fail "seeded config differs from the template"
  local inode; inode=$(stat -c '%i' -- "$config")
  migrate "$home" "$repo"
  [[ $(stat -c '%i' -- "$config") == "$inode" ]] || fail "repeat migration rewrote a matching config"
  chmod 640 "$config"
  migrate "$home" "$repo"
  [[ $(stat -c '%a' -- "$config") == 600 ]] || fail "migration did not restore owner-only mode"

  # App-written host tables survive; template-owned values are restored.
  {
    sed 's/^model_reasoning_effort = .*/model_reasoning_effort = "low"/' "$repo/templates/codex/config.toml"
    printf '\n[projects."/srv/example"]\ntrust_level = "trusted"\n\n[plugins."sites@openai-bundled"]\nenabled = true\n\n[desktop]\nfollowUpQueueMode = "queue"\n'
  } >"$config"
  chmod 600 "$config"
  migrate "$home" "$repo"
  [[ $(toml_value "$config" model_reasoning_effort) == xhigh ]] || fail "template-owned value was not restored"
  [[ $(toml_value "$config" 'projects./srv/example.trust_level') == trusted ]] || fail "host project table was lost"
  [[ $(toml_value "$config" 'plugins.sites@openai-bundled.enabled') == True ]] || fail "host plugin table was lost"
  [[ $(toml_value "$config" desktop.followUpQueueMode) == queue ]] || fail "host desktop table was lost"
  [[ $(stat -c '%a' -- "$config") == 600 ]] || fail "reconciled config is not owner-only"
  python3 "$repo/scripts/reconcile-codex-config.py" check "$repo/templates/codex/config.toml" "$config" ||
    fail "reconciled config does not pass the drift check"
  inode=$(stat -c '%i' -- "$config")
  migrate "$home" "$repo"
  [[ $(stat -c '%i' -- "$config") == "$inode" ]] || fail "repeat reconciliation rewrote a matching config"
  rm -- "$config"

  ln -s "$repo/codex/.codex/config.toml" "$config"
  rm -- "$repo/codex/.codex/config.toml"
  migrate "$home" "$repo"
  [[ -f $config && ! -L $config ]] || fail "dangling managed link was not replaced by a regular file"
  cmp -s -- "$config" "$repo/templates/codex/config.toml" || fail "dangling managed link was not seeded from the template"
  rm -- "$config"

  ln -s "$TMP/migrate/elsewhere/config.toml" "$config"
  if migrate "$home" "$repo" >/dev/null 2>&1; then fail "migration replaced an unmanaged dangling link"; fi
  [[ -L $config ]] || fail "failed migration changed an unmanaged link"
  rm -- "$config"

  printf 'not = [valid\n' >"$config"
  if migrate "$home" "$repo" >/dev/null 2>&1; then fail "migration accepted an unparseable host config"; fi
  [[ $(<"$config") == 'not = [valid' ]] || fail "failed migration changed an unparseable host config"
  rm -- "$config"

  rm -rf -- "$home/.codex"
  if migrate "$home" "$repo" >/dev/null 2>&1; then fail "migration accepted a missing Codex root"; fi
  [[ ! -e $home/.codex ]] || fail "failed migration created the Codex root"
}

case_clean_links
case_no_folding
case_migration
printf 'ok: prepare-stow removes only dangling managed links and migrates Codex config safely\n'
