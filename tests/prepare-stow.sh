#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Mirror the full package shape so endpoint checks are not constrained by an
# artificially narrow fixture.
make_payload() {
  local repo=$1
  mkdir -p "$repo/claude-code/.claude/agents" \
    "$repo/claude-code/.claude/rules" \
    "$repo/claude-code/.claude/skills/commit" \
    "$repo/claude-code/.claude/skills/publish" \
    "$repo/claude-code/.claude/skills/spar" \
    "$repo/claude-code/.local/bin" \
    "$repo/codex/.codex" \
    "$repo/codex/.agents/skills/commit" \
    "$repo/codex/.agents/skills/publish" \
    "$repo/codex/.agents/skills/spar" \
    "$repo/codex/.local/bin" \
    "$repo/opencode/.config/opencode/plugins" \
    "$repo/opencode/.config/opencode/tools"
  printf 'tracked\n' >"$repo/claude-code/.claude/settings.json"
  printf 'tracked\n' >"$repo/claude-code/.claude/CLAUDE.md"
  printf 'tracked\n' >"$repo/claude-code/.claude/statusline.sh"
  printf 'tracked\n' >"$repo/codex/.codex/config.toml"
  ln -s ../../claude-code/.claude/rules/shared-guidance.md "$repo/codex/.codex/AGENTS.md"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/spar-claude"
  printf 'tracked\n' >"$repo/claude-code/.local/bin/spar-payload-scan"
  printf 'tracked\n' >"$repo/codex/.local/bin/spar-codex"
  printf '{}\n' >"$repo/opencode/.config/opencode/opencode.json"
  printf 'export const plugin = true\n' >"$repo/opencode/.config/opencode/plugins/reviewed-writes.ts"
  printf '{"name":"eyragents-opencode-plugins","private":true,"type":"module"}\n' \
    >"$repo/opencode/.config/opencode/plugins/package.json"
  : >"$repo/opencode/.config/opencode/tools/.gitkeep"
}

make_migration_clone() {
  local repo=$1
  make_payload "$repo"
  mkdir -p "$repo/scripts" "$repo/templates/codex"
  cp -- "$ROOT/scripts/prepare-stow.sh" "$repo/scripts/prepare-stow.sh"
  cp -- "$ROOT/templates/codex/config.toml" "$repo/templates/codex/config.toml"
}

run_prepare() {
  HOME=$1 bash "$ROOT/scripts/prepare-stow.sh"
}

run_migration() {
  local home=$1 script=${2:-"$ROOT/scripts/prepare-stow.sh"}
  HOME=$home bash "$script" --migrate-codex-config
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
  ln -s "$repo/claude-code/.claude/hooks" "$home/.claude/hooks"
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
  [[ ! -e $home/.claude/hooks && ! -L $home/.claude/hooks ]] || fail "retired Claude hooks link remains"
  [[ -d $home/.claude/skills/user-owned ]] || fail "user-owned skill was removed"
  [[ ! -e $home/.codex/AGENTS.md && ! -L $home/.codex/AGENTS.md ]] || fail "managed Codex instruction link remains"
  [[ ! -e $home/.codex/config.toml && ! -L $home/.codex/config.toml ]] || fail "managed Codex config link remains"
  [[ ! -e $home/.codex/hooks.json && ! -L $home/.codex/hooks.json ]] || fail "managed Codex hooks link remains"
  [[ ! -e $home/.config/opencode/opencode.json ]] || fail "managed OpenCode link remains"
  [[ ! -e $home/.config/opencode/tools && ! -L $home/.config/opencode/tools ]] ||
    fail "managed OpenCode tools placeholder remains"
  for path in package.json package-lock.json node_modules; do
    [[ ! -e $home/.config/opencode/$path && ! -L $home/.config/opencode/$path ]] ||
      fail "legacy OpenCode link remains: $path"
  done
}

case_retired_regular_paths() {
  local home="$TMP/retired-regular/home" repo="$TMP/retired-regular/eyragents"
  local root="$home/.config/opencode" before after
  mkdir -p "$home/.codex" "$home/.local/bin" "$root/tools"
  make_payload "$repo"
  printf 'user hooks\n' >"$home/.codex/hooks.json"
  printf 'user gate\n' >"$home/.local/bin/context-read-gate.sh"
  printf 'user tool\n' >"$root/tools/external-context.ts"
  printf 'user marker\n' >"$root/tools/package.json"
  before=$(sha256sum "$home/.codex/hooks.json" "$home/.local/bin/context-read-gate.sh" \
    "$root/tools/external-context.ts" "$root/tools/package.json")
  run_prepare "$home"
  run_prepare "$home"
  after=$(sha256sum "$home/.codex/hooks.json" "$home/.local/bin/context-read-gate.sh" \
    "$root/tools/external-context.ts" "$root/tools/package.json")
  [[ $before == "$after" ]] || fail "regular files at retired endpoints changed"
}

case_retired_tool_links() {
  local home="$TMP/retired-tools/home" repo="$TMP/retired-tools/eyragents"
  local root="$home/.config/opencode"
  mkdir -p "$root/tools"
  make_payload "$repo"
  ln -s "$repo/opencode/.config/opencode/tools/external-context.ts" \
    "$root/tools/external-context.ts"
  ln -s "$repo/opencode/.config/opencode/tools/package.json" "$root/tools/package.json"
  run_prepare "$home"
  [[ -d $root/tools && ! -L $root/tools ]] || fail "regular tools directory was not preserved"
  [[ ! -e $root/tools/external-context.ts && ! -L $root/tools/external-context.ts ]] ||
    fail "retired external-context tool link remains"
  [[ ! -e $root/tools/package.json && ! -L $root/tools/package.json ]] ||
    fail "retired tool marker link remains"
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

case_codex_migration_seed() {
  local home="$TMP/migration-seed/home" config inode_before inode_after
  mkdir -p "$home/.codex"
  run_migration "$home"
  config="$home/.codex/config.toml"
  [[ -f $config && ! -L $config ]] || fail "seeded Codex config is not a regular file"
  [[ $(stat -c '%a' -- "$config") == 600 ]] || fail "seeded Codex config mode is not 600"
  [[ $(stat -c '%h' -- "$config") == 1 ]] || fail "seeded Codex config has multiple hard links"
  cmp -s -- "$config" "$ROOT/templates/codex/config.toml" || fail "seeded Codex config differs from template"
  inode_before=$(stat -c '%i' -- "$config")
  run_migration "$home"
  inode_after=$(stat -c '%i' -- "$config")
  [[ $inode_before == "$inode_after" ]] || fail "repeat migration rewrote a safe regular Codex config"
  chmod 400 "$config"
  run_migration "$home"
  [[ $(stat -c '%i' -- "$config") == "$inode_after" ]] || fail "migration rewrote an owner-read-only Codex config"
  [[ $(stat -c '%a' -- "$config") == 400 ]] || fail "migration changed an owner-read-only Codex config mode"
}

case_codex_migration_managed_leaf() {
  local home="$TMP/migration-managed/home" repo="$TMP/migration-managed/eyragents"
  local config source_before source_after
  mkdir -p "$home/.codex"
  make_migration_clone "$repo"
  printf 'host-specific tracked config\n' >"$repo/codex/.codex/config.toml"
  config="$home/.codex/config.toml"
  ln -s "$repo/codex/.codex/config.toml" "$config"
  source_before=$(sha256sum "$repo/codex/.codex/config.toml")
  run_migration "$home" "$repo/scripts/prepare-stow.sh"
  source_after=$(sha256sum "$repo/codex/.codex/config.toml")
  [[ $source_before == "$source_after" ]] || fail "migration changed the managed Codex source"
  [[ -f $config && ! -L $config ]] || fail "managed Codex leaf was not converted to a regular file"
  [[ $(<"$config") == "host-specific tracked config" ]] || fail "managed Codex bytes were not preserved"
  [[ $(stat -c '%a' -- "$config") == 600 ]] || fail "converted Codex config mode is not 600"
  [[ $(stat -c '%h' -- "$config") == 1 ]] || fail "converted Codex config has multiple hard links"
}

case_codex_migration_refusals() {
  local home repo config fake_bin real_stat

  home="$TMP/migration-missing-root/home"
  mkdir -p "$home"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted a missing Codex runtime root"
  fi
  [[ ! -e $home/.codex && ! -L $home/.codex ]] || fail "failed migration created a Codex runtime root"

  home="$TMP/migration-folded-root/home"
  repo="$TMP/migration-folded-root/eyragents"
  mkdir -p "$home"
  make_payload "$repo"
  ln -s "$repo/codex/.codex" "$home/.codex"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted a folded Codex runtime root"
  fi
  [[ -L $home/.codex ]] || fail "failed migration changed a folded Codex runtime root"

  home="$TMP/migration-dangling/home"
  mkdir -p "$home/.codex"
  ln -s "$TMP/missing/codex/.codex/config.toml" "$home/.codex/config.toml"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted a dangling Codex config symlink"
  fi
  [[ -L $home/.codex/config.toml ]] || fail "failed migration changed a dangling Codex config symlink"

  home="$TMP/migration-unmanaged/home"
  mkdir -p "$home/.codex" "$TMP/migration-unmanaged/source"
  printf 'unmanaged\n' >"$TMP/migration-unmanaged/source/config.toml"
  ln -s "$TMP/migration-unmanaged/source/config.toml" "$home/.codex/config.toml"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted an unmanaged Codex config symlink"
  fi
  [[ -L $home/.codex/config.toml ]] || fail "failed migration changed an unmanaged Codex config symlink"

  home="$TMP/migration-other-clone/home"
  repo="$TMP/migration-other-clone/eyragents"
  mkdir -p "$home/.codex"
  make_payload "$repo"
  printf 'other clone\n' >"$repo/codex/.codex/config.toml"
  ln -s "$repo/codex/.codex/config.toml" "$home/.codex/config.toml"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted a managed Codex source from another clone"
  fi
  [[ -L $home/.codex/config.toml ]] || fail "failed migration changed another clone's Codex config"
  [[ $(<"$repo/codex/.codex/config.toml") == "other clone" ]] || fail "failed migration changed another clone's source"

  home="$TMP/migration-aliased/home"
  repo="$TMP/migration-aliased/eyragents"
  mkdir -p "$home/.codex" "$TMP/migration-aliased/source"
  make_migration_clone "$repo"
  printf 'aliased\n' >"$TMP/migration-aliased/source/config.toml"
  rm -- "$repo/codex/.codex/config.toml"
  ln -s "$TMP/migration-aliased/source/config.toml" "$repo/codex/.codex/config.toml"
  ln -s "$repo/codex/.codex/config.toml" "$home/.codex/config.toml"
  if run_migration "$home" "$repo/scripts/prepare-stow.sh" >/dev/null 2>&1; then
    fail "migration accepted an aliased managed Codex source"
  fi
  [[ -L $home/.codex/config.toml ]] || fail "failed migration changed an aliased Codex config"

  home="$TMP/migration-unsafe-mode/home"
  mkdir -p "$home/.codex"
  printf 'unsafe\n' >"$home/.codex/config.toml"
  chmod 640 "$home/.codex/config.toml"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted an unsafe Codex config mode"
  fi
  [[ $(stat -c '%a' -- "$home/.codex/config.toml") == 640 ]] || fail "failed migration changed unsafe config metadata"

  home="$TMP/migration-hard-link/home"
  mkdir -p "$home/.codex"
  printf 'linked\n' >"$home/.codex/config.toml"
  chmod 600 "$home/.codex/config.toml"
  ln "$home/.codex/config.toml" "$home/.codex/config.alias"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted a multiply linked Codex config"
  fi
  [[ $(stat -c '%h' -- "$home/.codex/config.toml") == 2 ]] || fail "failed migration changed Codex hard links"

  home="$TMP/migration-unsafe-root/home"
  mkdir -p "$home/.codex"
  chmod 777 "$home/.codex"
  if run_migration "$home" >/dev/null 2>&1; then
    fail "migration accepted an unsafe Codex runtime root mode"
  fi
  [[ ! -e $home/.codex/config.toml ]] || fail "failed migration wrote through an unsafe Codex runtime root"

  home="$TMP/migration-home-alias/real-home"
  mkdir -p "$home/.codex"
  ln -s "$home" "$TMP/migration-home-alias/home-alias"
  if run_migration "$TMP/migration-home-alias/home-alias" >/dev/null 2>&1; then
    fail "migration accepted an aliased HOME"
  fi
  [[ ! -e $home/.codex/config.toml ]] || fail "failed migration wrote through an aliased HOME"

  home="$TMP/migration-wrong-owner/home"
  config="$home/.codex/config.toml"
  fake_bin="$TMP/migration-wrong-owner/bin"
  mkdir -p "$home/.codex" "$fake_bin"
  printf 'owner fixture\n' >"$config"
  chmod 600 "$config"
  real_stat=$(command -v stat)
  cat >"$fake_bin/stat" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -c && $2 == %u && ${4:-} == "$WRONG_OWNER_PATH" ]]; then
  printf '999999\n'
  exit 0
fi
exec "$REAL_STAT" "$@"
EOF
  chmod 755 "$fake_bin/stat"
  if WRONG_OWNER_PATH="$config" REAL_STAT="$real_stat" PATH="$fake_bin:$PATH" \
    HOME="$home" bash "$ROOT/scripts/prepare-stow.sh" --migrate-codex-config >/dev/null 2>&1; then
    fail "migration accepted a Codex config owned by another user"
  fi
  [[ $(<"$config") == "owner fixture" ]] || fail "failed migration changed a wrong-owner Codex config"
}

case_codex_migration_atomic_failure() {
  local home="$TMP/migration-atomic/home" repo="$TMP/migration-atomic/eyragents"
  local fake_bin="$TMP/migration-atomic/bin" config path sync_called="$TMP/migration-atomic/sync-called"
  mkdir -p "$home/.codex" "$fake_bin"
  make_migration_clone "$repo"
  config="$home/.codex/config.toml"
  printf 'durable source\n' >"$repo/codex/.codex/config.toml"
  ln -s "$repo/codex/.codex/config.toml" "$config"
  printf 'keep\n' >"$home/.codex/.config.toml.migrate.keep"
  cat >"$fake_bin/sync" <<'EOF'
#!/usr/bin/env bash
: >"$SYNC_CALLED"
exit 1
EOF
  chmod 755 "$fake_bin/sync"
  if SYNC_CALLED="$sync_called" PATH="$fake_bin:$PATH" HOME="$home" \
    bash "$repo/scripts/prepare-stow.sh" --migrate-codex-config >/dev/null 2>&1; then
    fail "migration succeeded after its durability step failed"
  fi
  [[ -f $sync_called ]] || fail "migration failed before reaching its durability step"
  [[ -L $config ]] || fail "failed migration replaced the managed Codex symlink"
  [[ $(<"$config") == "durable source" ]] || fail "failed migration changed managed Codex bytes"
  shopt -s nullglob
  for path in "$home/.codex"/.config.toml.migrate.*; do
    [[ $path == "$home/.codex/.config.toml.migrate.keep" ]] || fail "failed migration left its temporary file"
  done
  shopt -u nullglob
  [[ -f $home/.codex/.config.toml.migrate.keep ]] || fail "migration removed a pre-existing similar file"
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
  [[ $(readlink -f -- "$root/tools/.gitkeep") == "$repo/opencode/.config/opencode/tools/.gitkeep" ]] ||
    fail "OpenCode tools placeholder was not stowed"
  [[ ! -e $root/tools/external-context.ts && ! -L $root/tools/external-context.ts ]] ||
    fail "retired OpenCode external-context tool was stowed"
  [[ ! -e $root/tools/package.json && ! -L $root/tools/package.json ]] ||
    fail "retired OpenCode tool marker was stowed"
  [[ ! -e $home/.codex/hooks.json && ! -L $home/.codex/hooks.json ]] ||
    fail "retired Codex hooks were stowed"
  [[ ! -e $home/.local/bin/context-read-gate.sh && ! -L $home/.local/bin/context-read-gate.sh ]] ||
    fail "retired external context gate was stowed"

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
case_retired_regular_paths
case_retired_tool_links
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
case_codex_migration_seed
case_codex_migration_managed_leaf
case_codex_migration_refusals
case_codex_migration_atomic_failure
case_actual_stow
printf 'ok: prepare-stow preserves state, normalizes roots, and migrates Codex config safely\n'
