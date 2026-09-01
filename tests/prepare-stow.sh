#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# The fixture mirrors the full package shape even though prepare-stow.sh reads
# only a few endpoints today: the realism guards a future preparation step that
# inspects targets, at zero cost.
make_payload() {
  local repo=$1
  mkdir -p "$repo/claude-code/.claude/agents" \
    "$repo/claude-code/.claude/rules" \
    "$repo/claude-code/.claude/skills/commit" \
    "$repo/claude-code/.claude/skills/spar" \
    "$repo/claude-code/.local/bin" \
    "$repo/codex/.codex" \
    "$repo/codex/.agents/skills/commit" \
    "$repo/codex/.agents/skills/spar" \
    "$repo/codex/.local/bin" \
    "$repo/opencode/.config/opencode/plugins" \
    "$repo/opencode/.config/opencode/tools"
  printf 'tracked\n' >"$repo/claude-code/.claude/settings.json"
  printf 'tracked\n' >"$repo/claude-code/.claude/CLAUDE.md"
  printf 'tracked\n' >"$repo/claude-code/.claude/statusline.sh"
  printf 'tracked\n' >"$repo/codex/.codex/config.toml"
  printf '{}\n' >"$repo/codex/.codex/hooks.json"
  ln -s ../../claude-code/.claude/rules/shared-guidance.md "$repo/codex/.codex/AGENTS.md"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/spar-claude"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/spar-payload-scan"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/context-read-gate.sh"
  printf 'tracked\n' >"$repo/codex/.local/bin/spar-codex"
  printf '{}\n' >"$repo/opencode/.config/opencode/opencode.json"
  printf 'export const plugin = true\n' >"$repo/opencode/.config/opencode/plugins/reviewed-writes.ts"
  printf '{"name":"eyragents-opencode-plugins","private":true,"type":"module"}\n' \
    >"$repo/opencode/.config/opencode/plugins/package.json"
  printf 'export default {}\n' >"$repo/opencode/.config/opencode/tools/external-context.ts"
  printf '{"name":"eyragents-opencode-tools","private":true,"type":"module"}\n' \
    >"$repo/opencode/.config/opencode/tools/package.json"
}

run_prepare() {
  HOME=$1 bash "$ROOT/scripts/prepare-stow.sh"
}

case_fresh_home() {
  local base="$TMP/fresh" home="$TMP/fresh/home" repo="$TMP/fresh/eyragents"
  mkdir -p "$base" "$home"
  make_payload "$repo"
  run_prepare "$home"
  for path in .claude .claude/skills .codex .agents/skills .local/bin .config .config/opencode; do
    [[ -d $home/$path && ! -L $home/$path ]] || fail "fresh $path is not a real directory"
  done
}

case_managed_links() {
  local home="$TMP/linked/home" repo="$TMP/linked/eyragents"
  mkdir -p "$home/.claude/skills" "$home/.codex" "$home/.agents/skills" \
    "$home/.local/bin" "$home/.config/opencode"
  make_payload "$repo"
  ln -s "$repo/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  ln -s "$repo/claude-code/.claude/agents" "$home/.claude/agents"
  ln -s "$repo/claude-code/.claude/skills/commit" "$home/.claude/skills/commit"
  mkdir "$home/.claude/skills/user-owned"
  ln -s "$repo/codex/.codex/AGENTS.md" "$home/.codex/AGENTS.md"
  ln -s "$repo/codex/.codex/config.toml" "$home/.codex/config.toml"
  ln -s "$repo/codex/.codex/hooks.json" "$home/.codex/hooks.json"
  ln -s "$repo/codex/.agents/skills/spar" "$home/.agents/skills/spar"
  ln -s "$repo/claude-code/.local/bin/spar-claude" "$home/.local/bin/spar-claude"
  ln -s "$repo/claude-code/.local/bin/spar-payload-scan" "$home/.local/bin/spar-payload-scan"
  ln -s "$repo/claude-code/.local/bin/context-read-gate.sh" "$home/.local/bin/context-read-gate.sh"
  ln -s "$repo/opencode/.config/opencode/opencode.json" "$home/.config/opencode/opencode.json"
  ln -s "$repo/opencode/.config/opencode/tools" "$home/.config/opencode/tools"
  printf '{}\n' >"$repo/opencode/.config/opencode/package.json"
  printf '{}\n' >"$repo/opencode/.config/opencode/package-lock.json"
  mkdir "$repo/opencode/.config/opencode/node_modules"
  ln -s "$repo/opencode/.config/opencode/package.json" "$home/.config/opencode/package.json"
  ln -s "$repo/opencode/.config/opencode/package-lock.json" "$home/.config/opencode/package-lock.json"
  ln -s "$repo/opencode/.config/opencode/node_modules" "$home/.config/opencode/node_modules"
  run_prepare "$home"
  [[ ! -e $home/.claude/settings.json && ! -L $home/.claude/settings.json ]] || fail "managed Claude link remains"
  [[ -d $home/.claude/skills/user-owned ]] || fail "user-owned skill was removed"
  [[ ! -e $home/.codex/AGENTS.md && ! -L $home/.codex/AGENTS.md ]] || fail "managed Codex instruction link remains"
  [[ ! -e $home/.codex/hooks.json && ! -L $home/.codex/hooks.json ]] || fail "managed Codex hooks link remains"
  [[ ! -e $home/.config/opencode/opencode.json ]] || fail "managed OpenCode link remains"
  [[ ! -e $home/.config/opencode/tools && ! -L $home/.config/opencode/tools ]] ||
    fail "managed OpenCode tools link remains"
  for path in package.json package-lock.json node_modules; do
    [[ ! -e $home/.config/opencode/$path && ! -L $home/.config/opencode/$path ]] ||
      fail "legacy OpenCode link remains: $path"
  done
}

case_folded_claude() {
  local home="$TMP/folded/home" repo="$TMP/folded/eyragents" before after
  mkdir -p "$home"
  make_payload "$repo"
  before=$(sha256sum "$repo/claude-code/.claude/settings.json")
  ln -s "$repo/claude-code/.claude" "$home/.claude"
  run_prepare "$home"
  after=$(sha256sum "$repo/claude-code/.claude/settings.json")
  [[ $before == "$after" ]] || fail "folded cleanup changed tracked payload"
  [[ -d $home/.claude && ! -L $home/.claude ]] || fail "folded Claude parent was not replaced with a real directory"
  [[ -d $home/.claude/skills && ! -L $home/.claude/skills ]] || fail "Claude skills parent was not created"
}

case_folded_codex_local() {
  local home="$TMP/folded-codex-local/home" repo="$TMP/folded-codex-local/eyragents"
  local bin_home="$TMP/folded-codex-bin/home"
  mkdir -p "$home" "$bin_home/.local"
  make_payload "$repo"
  ln -s "$repo/codex/.local" "$home/.local"
  run_prepare "$home"
  [[ -d $home/.local && ! -L $home/.local ]] || fail "folded Codex .local was not replaced"
  [[ -d $home/.local/bin && ! -L $home/.local/bin ]] || fail "folded Codex bin parent was not created"
  ln -s "$repo/codex/.local/bin" "$bin_home/.local/bin"
  run_prepare "$bin_home"
  [[ -d $bin_home/.local/bin && ! -L $bin_home/.local/bin ]] || fail "folded Codex bin was not replaced"
}

case_folded_opencode_parent() {
  local home="$TMP/folded-opencode-parent/home" repo="$TMP/folded-opencode-parent/eyragents"
  mkdir -p "$home"
  make_payload "$repo"
  ln -s "$repo/opencode/.config" "$home/.config"
  run_prepare "$home"
  [[ -d $home/.config && ! -L $home/.config ]] || fail "folded .config parent was not replaced"
  [[ -d $home/.config/opencode && ! -L $home/.config/opencode ]] ||
    fail "OpenCode root was not created below a folded .config parent"
}

case_folded_opencode_root() {
  local home="$TMP/folded-opencode-root/home" repo="$TMP/folded-opencode-root/eyragents"
  mkdir -p "$home/.config"
  make_payload "$repo"
  printf 'generated through fold\n' >"$repo/opencode/.config/opencode/package.json"
  ln -s "$repo/opencode/.config/opencode" "$home/.config/opencode"
  run_prepare "$home"
  [[ -d $home/.config/opencode && ! -L $home/.config/opencode ]] ||
    fail "folded OpenCode root was not replaced with a real directory"
  [[ ! -e $home/.config/opencode/package.json ]] || fail "generated state remains exposed through the old fold"
  [[ -f $repo/opencode/.config/opencode/package.json ]] || fail "preparation deleted package-source state"
}

case_dangling_old_clone() {
  local home="$TMP/dangling/home"
  mkdir -p "$home/.claude"
  ln -s "$TMP/missing/eyragents/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  run_prepare "$home"
  [[ ! -L $home/.claude/settings.json ]] || fail "dangling managed link remains"
}

case_dangling_opencode_legacy() {
  local home="$TMP/dangling-opencode/home" root="$TMP/dangling-opencode/home/.config/opencode"
  mkdir -p "$root"
  for path in package.json package-lock.json node_modules; do
    ln -s "$TMP/missing/eyragents/opencode/.config/opencode/$path" "$root/$path"
  done
  run_prepare "$home"
  for path in package.json package-lock.json node_modules; do
    [[ ! -e $root/$path && ! -L $root/$path ]] || fail "dangling legacy link remains: $path"
  done
}

case_regular_opencode_state() {
  local home="$TMP/regular-opencode/home" root="$TMP/regular-opencode/home/.config/opencode" before after
  mkdir -p "$root/node_modules"
  for path in package.json package-lock.json bun.lock bun.lockb; do
    printf 'host-local %s\n' "$path" >"$root/$path"
  done
  before=$(sha256sum "$root/package.json" "$root/package-lock.json" "$root/bun.lock" "$root/bun.lockb")
  run_prepare "$home"
  run_prepare "$home"
  after=$(sha256sum "$root/package.json" "$root/package-lock.json" "$root/bun.lock" "$root/bun.lockb")
  [[ $before == "$after" ]] || fail "regular OpenCode generated files changed"
  [[ -d $root/node_modules && ! -L $root/node_modules ]] || fail "regular node_modules was not preserved"
}

case_regular_conflict() {
  local home="$TMP/conflict/home" repo="$TMP/conflict/eyragents"
  mkdir -p "$home/.claude"
  make_payload "$repo"
  printf 'user data\n' >"$home/.claude/settings.json"
  ln -s "$repo/claude-code/.claude/agents" "$home/.claude/agents"
  if run_prepare "$home" >/dev/null 2>&1; then
    fail "regular conflict did not abort"
  fi
  [[ $(<"$home/.claude/settings.json") == "user data" ]] || fail "regular conflict was changed"
  [[ -L $home/.claude/agents ]] || fail "preflight failure partially removed links"
}

case_unmanaged_link() {
  local home="$TMP/unmanaged/home"
  mkdir -p "$home/.claude"
  ln -s /tmp/not-managed/settings.json "$home/.claude/settings.json"
  if run_prepare "$home" >/dev/null 2>&1; then
    fail "unmanaged symlink did not abort"
  fi
  [[ -L $home/.claude/settings.json ]] || fail "unmanaged symlink was removed"
}

case_unmanaged_opencode_link() {
  local home="$TMP/unmanaged-opencode/home" repo="$TMP/unmanaged-opencode/eyragents"
  local root="$TMP/unmanaged-opencode/home/.config/opencode"
  mkdir -p "$root"
  make_payload "$repo"
  ln -s "$repo/opencode/.config/opencode/opencode.json" "$root/opencode.json"
  ln -s /tmp/not-managed/package.json "$root/package.json"
  if run_prepare "$home" >/dev/null 2>&1; then
    fail "unmanaged OpenCode generated-state symlink did not abort"
  fi
  [[ -L $root/opencode.json ]] || fail "preflight failure partially removed a managed OpenCode link"
  [[ -L $root/package.json ]] || fail "unmanaged OpenCode symlink was removed"
}

case_unmanaged_bun_link() {
  local path home root
  for path in bun.lock bun.lockb; do
    home="$TMP/unmanaged-$path/home"
    root="$home/.config/opencode"
    mkdir -p "$root"
    ln -s "/tmp/not-managed/$path" "$root/$path"
    if run_prepare "$home" >/dev/null 2>&1; then
      fail "unmanaged $path symlink did not abort"
    fi
    [[ -L $root/$path ]] || fail "unmanaged $path symlink was removed"
  done
}

case_generated_state_wrong_types() {
  local file_home="$TMP/wrong-node-modules/home" file_root="$TMP/wrong-node-modules/home/.config/opencode"
  local dir_home="$TMP/wrong-package/home" dir_root="$TMP/wrong-package/home/.config/opencode"
  mkdir -p "$file_root" "$dir_root/package.json"
  printf 'not a directory\n' >"$file_root/node_modules"
  if run_prepare "$file_home" >/dev/null 2>&1; then
    fail "regular file at node_modules did not abort"
  fi
  [[ -f $file_root/node_modules ]] || fail "wrong-type node_modules was changed"
  if run_prepare "$dir_home" >/dev/null 2>&1; then
    fail "directory at package.json did not abort"
  fi
  [[ -d $dir_root/package.json ]] || fail "wrong-type package.json was changed"
}

case_unmanaged_opencode_root() {
  local home="$TMP/unmanaged-opencode-root/home"
  mkdir -p "$home/.config"
  ln -s /tmp/not-managed/opencode "$home/.config/opencode"
  if run_prepare "$home" >/dev/null 2>&1; then
    fail "unmanaged OpenCode root symlink did not abort"
  fi
  [[ -L $home/.config/opencode ]] || fail "unmanaged OpenCode root symlink was removed"
}

case_actual_stow() {
  local home="$TMP/actual-stow/home" repo="$TMP/actual-stow/eyragents"
  local root="$TMP/actual-stow/home/.config/opencode"
  mkdir -p "$home"
  make_payload "$repo"
  run_prepare "$home"
  stow -d "$repo" -t "$home" claude-code codex opencode >/dev/null
  [[ -d $root && ! -L $root ]] || fail "Stow folded the OpenCode config root"
  [[ $(readlink -f -- "$root/opencode.json") == "$repo/opencode/.config/opencode/opencode.json" ]] ||
    fail "OpenCode config child was not stowed"
  [[ $(readlink -f -- "$root/plugins/package.json") == "$repo/opencode/.config/opencode/plugins/package.json" ]] ||
    fail "nested OpenCode plugin marker was not stowed"
  [[ $(readlink -f -- "$root/tools/package.json") == "$repo/opencode/.config/opencode/tools/package.json" ]] ||
    fail "nested OpenCode tool marker was not stowed"
  [[ $(readlink -f -- "$home/.codex/hooks.json") == "$repo/codex/.codex/hooks.json" ]] ||
    fail "Codex hooks were not stowed"
  [[ $(readlink -f -- "$home/.local/bin/context-read-gate.sh") == "$repo/claude-code/.local/bin/context-read-gate.sh" ]] ||
    fail "external context gate was not stowed"

  printf 'host-local\n' >"$root/package.json"
  mkdir "$root/node_modules"
  run_prepare "$home"
  run_prepare "$home"
  [[ $(<"$root/package.json") == "host-local" ]] || fail "preparation changed host-local package state"
  [[ -d $root/node_modules && ! -L $root/node_modules ]] || fail "preparation changed host-local dependencies"
  stow -R -d "$repo" -t "$home" claude-code codex opencode >/dev/null
  [[ -d $root && ! -L $root ]] || fail "restow folded the OpenCode config root"
  [[ ! -L $root/package.json && $(<"$root/package.json") == "host-local" ]] ||
    fail "restow changed host-local package state"
}

case_fresh_home
case_managed_links
case_folded_claude
case_folded_codex_local
case_folded_opencode_parent
case_folded_opencode_root
case_dangling_old_clone
case_dangling_opencode_legacy
case_regular_opencode_state
case_regular_conflict
case_unmanaged_link
case_unmanaged_opencode_link
case_unmanaged_bun_link
case_generated_state_wrong_types
case_unmanaged_opencode_root
case_actual_stow
printf 'ok: prepare-stow preserves generated state and normalizes real roots\n'
