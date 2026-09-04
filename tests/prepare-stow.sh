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
  mkdir -p "$repo/agents/.agents/skills/commit/scripts" "$repo/claude-code/.claude/skills/commit/scripts" \
    "$repo/claude-code/.claude/skills/spar/scripts" \
    "$repo/agents/.agents/skills/spar/scripts" "$repo/codex/.codex" \
    "$repo/opencode/.config/opencode" \
    "$repo/scripts" "$repo/templates/codex"
  printf 'tracked\n' >"$repo/claude-code/.claude/settings.json"
  printf 'guidance\n' >"$repo/agents/.agents/shared-guidance.md"
  printf 'skill\n' >"$repo/agents/.agents/skills/commit/SKILL.md"
  printf 'script\n' >"$repo/agents/.agents/skills/commit/scripts/commit-apply"
  ln -s ../../agents/.agents/shared-guidance.md "$repo/claude-code/.claude/CLAUDE.md"
  ln -s ../../../../agents/.agents/skills/commit/SKILL.md "$repo/claude-code/.claude/skills/commit/SKILL.md"
  ln -s ../../../../../agents/.agents/skills/commit/scripts/commit-apply "$repo/claude-code/.claude/skills/commit/scripts/commit-apply"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/spar-claude"
  printf 'tracked\n' >"$repo/codex/.codex/config.toml"
  ln -s ../../agents/.agents/shared-guidance.md "$repo/codex/.codex/AGENTS.md"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/spar-codex"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/spar-payload-scan"
  printf 'tracked\n' >"$repo/agents/.agents/skills/spar/scripts/review-brief"
  for tool in review-brief spar-claude spar-codex spar-payload-scan; do
    ln -s "../../../../../agents/.agents/skills/spar/scripts/$tool" "$repo/claude-code/.claude/skills/spar/scripts/$tool"
  done
  printf '{}\n' >"$repo/opencode/.config/opencode/opencode.json"
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
deploy() {
  HOME=$1 stow --no-folding -R -d "$2" -t "$1" claude-code codex opencode &&
    HOME=$1 stow --no-folding --ignore='\.agents/skills' -R -d "$2" -t "$1" agents &&
    HOME=$1 bash "$2/scripts/prepare-stow.sh" --link-skills
}
undeploy() {
  HOME=$1 stow --no-folding -D -d "$2" -t "$1" claude-code codex opencode &&
    HOME=$1 stow --no-folding --ignore='\.agents/skills' -D -d "$2" -t "$1" agents &&
    HOME=$1 bash "$2/scripts/prepare-stow.sh" --unlink-skills
}

case_clean_links() {
  local home="$TMP/clean/home" repo="$TMP/clean/eyragents" old="$TMP/clean/old/eyragents"
  mkdir -p "$home/.claude/skills" "$home/.codex" "$home/.agents/skills" "$home/.local/bin" "$home/.config/opencode"
  make_clone "$repo"
  ln -s "$old/claude-code/.claude/hooks" "$home/.claude/hooks"
  ln -s "$old/codex/.codex/config.toml" "$home/.codex/config.toml"
  ln -s "../../Projects/renamed-clone/agents/.agents/skills/retired" "$home/.agents/skills/retired"
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
  for path in .claude .claude/skills/commit .claude/skills/commit/scripts .codex .agents .agents/skills .claude/skills/spar/scripts .config/opencode; do
    [[ -d $home/$path && ! -L $home/$path ]] || fail "$path is not a real directory after no-folding stow"
  done
  for name in commit spar; do
    [[ -L $home/.agents/skills/$name && $(readlink -f -- "$home/.agents/skills/$name") == "$repo/agents/.agents/skills/$name" ]] ||
      fail "skill directory $name is not one link into the clone"
  done
  [[ $(readlink -f -- "$home/.agents/shared-guidance.md") == "$repo/agents/.agents/shared-guidance.md" ]] ||
    fail "leaf link does not resolve into the clone"
  [[ $(readlink -f -- "$home/.claude/CLAUDE.md") == "$repo/agents/.agents/shared-guidance.md" ]] ||
    fail "Claude user instructions symlink did not deploy"
  [[ $(readlink -f -- "$home/.codex/AGENTS.md") == "$repo/agents/.agents/shared-guidance.md" ]] ||
    fail "package symlink did not deploy"
  [[ $(readlink -f -- "$home/.claude/skills/commit/SKILL.md") == "$repo/agents/.agents/skills/commit/SKILL.md" ]] ||
    fail "Claude skill symlink did not deploy"
  [[ $(readlink -f -- "$home/.claude/skills/commit/scripts/commit-apply") == "$repo/agents/.agents/skills/commit/scripts/commit-apply" ]] ||
    fail "Claude skill scripts symlink did not deploy"
  for tool in review-brief spar-claude spar-codex spar-payload-scan; do
    [[ $(readlink -f -- "$home/.claude/skills/spar/scripts/$tool") == "$repo/agents/.agents/skills/spar/scripts/$tool" ]] ||
      fail "Claude spar link for $tool does not reach its own source"
  done
  [[ $(readlink -f -- "$home/.agents/skills/commit/SKILL.md") == "$repo/agents/.agents/skills/commit/SKILL.md" ]] ||
    fail "skill leaf link does not resolve into the clone"
  printf 'host-local\n' >"$root/package.json"
  mkdir "$root/node_modules"
  prepare "$home" "$repo"
  deploy "$home" "$repo" >/dev/null 2>&1 || fail "restow failed with host-local generated state present"
  [[ ! -L $root/package.json && $(<"$root/package.json") == "host-local" && -d $root/node_modules ]] ||
    fail "restow changed host-local generated state"
  [[ ! -e $repo/opencode/.config/opencode/package.json ]] || fail "generated state reached the package source"
  undeploy "$home" "$repo" >/dev/null 2>&1 || fail "unstow failed"
  [[ ! -e $home/.claude/CLAUDE.md && ! -e $home/.agents/skills/commit && -d $home/.agents/skills && -f $root/package.json ]] ||
    fail "unstow removed the wrong things"
}

case_skill_links() {
  local home="$TMP/links/home" repo="$TMP/links/eyragents"
  mkdir -p "$home/.agents/skills/commit/scripts"
  make_clone "$repo"
  # The leaf-link layout an earlier no-folding deploy left behind becomes one link.
  ln -s "$repo/agents/.agents/skills/commit/SKILL.md" "$home/.agents/skills/commit/SKILL.md"
  ln -s "$repo/agents/.agents/skills/commit/scripts/commit-apply" "$home/.agents/skills/commit/scripts/commit-apply"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null || fail "link-skills failed on the leaf-link layout"
  [[ -L $home/.agents/skills/commit && $(readlink -f -- "$home/.agents/skills/commit") == "$repo/agents/.agents/skills/commit" ]] ||
    fail "the leaf-link skill directory was not replaced by one link"
  [[ -L $home/.agents/skills/spar ]] || fail "a missing skill directory was not linked"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null || fail "link-skills is not idempotent"
  # A foreign entry stops the conversion and stays.
  rm "$home/.agents/skills/spar"
  mkdir -p "$home/.agents/skills/spar"
  printf 'mine\n' >"$home/.agents/skills/spar/notes.md"
  if HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null 2>&1; then fail "link-skills replaced a directory holding a foreign entry"; fi
  [[ -f $home/.agents/skills/spar/notes.md ]] || fail "link-skills removed a foreign entry"
  rm -r "$home/.agents/skills/spar"
  # A link that resolves elsewhere is refused, not repointed.
  mkdir -p "$TMP/links/elsewhere"
  ln -s "$TMP/links/elsewhere" "$home/.agents/skills/spar"
  if HOME=$home bash "$repo/scripts/prepare-stow.sh" --link-skills >/dev/null 2>&1; then fail "link-skills repointed a foreign link"; fi
  [[ $(readlink -- "$home/.agents/skills/spar") == "$TMP/links/elsewhere" ]] || fail "link-skills changed a foreign link"
  rm "$home/.agents/skills/spar"
  HOME=$home bash "$repo/scripts/prepare-stow.sh" --unlink-skills >/dev/null || fail "unlink-skills failed"
  [[ ! -e $home/.agents/skills/commit && -d $home/.agents/skills ]] || fail "unlink-skills left the link or removed the root"
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
    printf '\n[projects."/srv/example"]\ntrust_level = "trusted"\n\n[plugins."sites@openai-bundled"]\nenabled = true\n\n[hooks.state]\n\n[hooks.state."/srv/example/config.toml:pre_tool_use:0:0"]\ntrusted_hash = "sha256:fixture"\n\n[desktop]\nfollowUpQueueMode = "queue"\n'
  } >"$config"
  chmod 600 "$config"
  migrate "$home" "$repo"
  [[ $(toml_value "$config" model_reasoning_effort) == xhigh ]] || fail "template-owned value was not restored"
  # Codex records each hook's trusted hash under hooks.state; the record survives
  # under the template's hooks table and does not count as drift.
  [[ $(python3 -c 'import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
print(data["hooks"]["state"]["/srv/example/config.toml:pre_tool_use:0:0"]["trusted_hash"])' "$config") == sha256:fixture ]] ||
    fail "hook trust state was lost"
  [[ $(python3 -c 'import sys, tomllib
print(len(tomllib.load(open(sys.argv[1], "rb"))["hooks"]["PreToolUse"]))' "$config") == 1 ]] || fail "template hooks were not restored beside the trust state"
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
case_skill_links
case_migration
printf 'ok: prepare-stow removes only dangling managed links, links skill directories, and migrates Codex config safely\n'
