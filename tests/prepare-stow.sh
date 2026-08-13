#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

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
    "$repo/opencode/.config/opencode/plugins"
  printf 'tracked\n' >"$repo/claude-code/.claude/settings.json"
  printf 'tracked\n' >"$repo/claude-code/.claude/CLAUDE.md"
  printf 'tracked\n' >"$repo/claude-code/.claude/statusline.sh"
  printf 'tracked\n' >"$repo/codex/.codex/config.toml"
  ln -s ../../../claude-code/.claude/rules/shared-guidance.md "$repo/codex/.codex/AGENTS.md"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/spar-claude"
  printf 'tracked\n' >"$repo/codex/.local/bin/spar-codex"
  printf '{}\n' >"$repo/opencode/.config/opencode/opencode.json"
}

run_prepare() {
  HOME=$1 bash "$ROOT/scripts/prepare-stow.sh"
}

case_fresh_home() {
  local base="$TMP/fresh" home="$TMP/fresh/home" repo="$TMP/fresh/dotfiles-ai"
  mkdir -p "$base" "$home"
  make_payload "$repo"
  run_prepare "$home"
  for path in .claude .claude/skills .codex .agents/skills .local/bin; do
    [[ -d $home/$path && ! -L $home/$path ]] || fail "fresh $path is not a real directory"
  done
}

case_managed_links() {
  local home="$TMP/linked/home" repo="$TMP/linked/dotfiles-ai"
  mkdir -p "$home/.claude/skills" "$home/.codex" "$home/.agents/skills" \
    "$home/.local/bin" "$home/.config/opencode"
  make_payload "$repo"
  ln -s "$repo/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  ln -s "$repo/claude-code/.claude/agents" "$home/.claude/agents"
  ln -s "$repo/claude-code/.claude/skills/commit" "$home/.claude/skills/commit"
  mkdir "$home/.claude/skills/user-owned"
  ln -s "$repo/codex/.codex/config.toml" "$home/.codex/config.toml"
  ln -s "$repo/codex/.agents/skills/spar" "$home/.agents/skills/spar"
  ln -s "$repo/claude-code/.local/bin/spar-claude" "$home/.local/bin/spar-claude"
  ln -s "$repo/opencode/.config/opencode/opencode.json" "$home/.config/opencode/opencode.json"
  run_prepare "$home"
  [[ ! -e $home/.claude/settings.json && ! -L $home/.claude/settings.json ]] || fail "managed Claude link remains"
  [[ -d $home/.claude/skills/user-owned ]] || fail "user-owned skill was removed"
  [[ ! -e $home/.config/opencode/opencode.json ]] || fail "managed OpenCode link remains"
}

case_folded_claude() {
  local home="$TMP/folded/home" repo="$TMP/folded/dotfiles-ai" before after
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

case_dangling_old_clone() {
  local home="$TMP/dangling/home"
  mkdir -p "$home/.claude"
  ln -s "$TMP/missing/dotfiles-ai/claude-code/.claude/settings.json" "$home/.claude/settings.json"
  run_prepare "$home"
  [[ ! -L $home/.claude/settings.json ]] || fail "dangling managed link remains"
}

case_regular_conflict() {
  local home="$TMP/conflict/home" repo="$TMP/conflict/dotfiles-ai"
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

case_fresh_home
case_managed_links
case_folded_claude
case_dangling_old_clone
case_regular_conflict
case_unmanaged_link
printf 'ok: prepare-stow preserves data and normalizes state parents\n'
