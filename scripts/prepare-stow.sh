#!/usr/bin/env bash
# Prepare user state directories for Stow without deleting regular files.
set -euo pipefail

declare -a remove_links=()
declare -a create_dirs=()

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

MIGRATION_TMP=

cleanup_migration_temp() {
  if [[ -n "${MIGRATION_TMP:-}" ]]; then
    rm -f -- "$MIGRATION_TMP"
  fi
}

require_owner_controlled_directory() {
  local path=$1
  local label=$2
  local canonical mode owner

  [[ -d "$path" && ! -L "$path" ]] || abort "$label must be a real directory: $path"
  canonical=$(realpath -e -- "$path") || abort "cannot resolve $label: $path"
  [[ "$canonical" == "$path" ]] || abort "$label must not use a filesystem alias: $path"
  owner=$(stat -c '%u' -- "$path") || abort "cannot inspect $label owner: $path"
  [[ "$owner" == "$(id -u)" ]] || abort "$label is not owned by the current user: $path"
  mode=$(stat -c '%a' -- "$path") || abort "cannot inspect $label mode: $path"
  (( (8#$mode & 8#022) == 0 )) || abort "$label is writable by another user: $path"
}

require_safe_regular_file() {
  local path=$1
  local label=$2
  local links owner

  [[ -f "$path" && ! -L "$path" ]] || abort "$label must be a regular file: $path"
  owner=$(stat -c '%u' -- "$path") || abort "cannot inspect $label owner: $path"
  [[ "$owner" == "$(id -u)" ]] || abort "$label is not owned by the current user: $path"
  links=$(stat -c '%h' -- "$path") || abort "cannot inspect $label link count: $path"
  [[ "$links" == 1 ]] || abort "$label must have exactly one hard link: $path"
}

write_migration_temp() {
  local source=$1
  local codex_root=$2

  MIGRATION_TMP=$(mktemp -- "$codex_root/.config.toml.migrate.XXXXXX") || abort "cannot create migration temporary file"
  require_safe_regular_file "$MIGRATION_TMP" "migration temporary file"
  chmod 600 -- "$MIGRATION_TMP" || abort "cannot secure migration temporary file"
  cat -- "$source" >"$MIGRATION_TMP" || abort "cannot copy migration source"
  sync -f -- "$MIGRATION_TMP" || abort "cannot flush migration temporary file"
  cmp -s -- "$MIGRATION_TMP" "$source" || abort "migration copy differs from its source"
}

migrate_codex_config() {
  local dependency script_dir repository_root template
  local home_path codex_root config target mode

  for dependency in cat chmod cmp id mktemp mv realpath rm stat sync; do
    command -v "$dependency" >/dev/null 2>&1 || abort "required command not found: $dependency"
  done

  [[ -n "${HOME:-}" ]] || abort 'HOME is not set'
  home_path=${HOME%/}
  [[ -n "$home_path" && "$home_path" != / ]] || abort 'HOME must name a non-root directory'

  script_dir=$(dirname -- "${BASH_SOURCE[0]}")
  repository_root=$(realpath -e -- "$script_dir/..") || abort 'cannot resolve repository root'
  template="$repository_root/templates/codex/config.toml"
  require_safe_regular_file "$template" "Codex portable template"

  require_owner_controlled_directory "$home_path" 'HOME'
  codex_root="$home_path/.codex"
  require_owner_controlled_directory "$codex_root" 'Codex runtime root'
  config="$codex_root/config.toml"

  umask 077
  trap cleanup_migration_temp EXIT
  trap 'exit 130' HUP INT TERM

  if [[ ! -e "$config" && ! -L "$config" ]]; then
    write_migration_temp "$template" "$codex_root"
    [[ ! -e "$config" && ! -L "$config" ]] || abort "Codex config appeared during migration: $config"
    cmp -s -- "$MIGRATION_TMP" "$template" || abort "Codex portable template changed during migration"
    mv -T -- "$MIGRATION_TMP" "$config" || abort "cannot install migrated Codex config"
    MIGRATION_TMP=
    printf 'prepare-stow: seeded host-local Codex config from the portable template\n'
    return
  fi

  if [[ -L "$config" ]]; then
    target=$(realpath -e -- "$config") || abort "Codex config symlink is dangling: $config"
    case "$target" in
      */codex/.codex/config.toml) ;;
      *) abort "Codex config symlink is not a recognized managed leaf: $config" ;;
    esac
    require_safe_regular_file "$target" "managed Codex config source"
    write_migration_temp "$target" "$codex_root"
    [[ -L "$config" ]] || abort "Codex config changed during migration: $config"
    [[ "$(realpath -e -- "$config")" == "$target" ]] || abort "Codex config target changed during migration: $config"
    cmp -s -- "$MIGRATION_TMP" "$target" || abort "managed Codex config changed during migration"
    mv -T -- "$MIGRATION_TMP" "$config" || abort "cannot install migrated Codex config"
    MIGRATION_TMP=
    printf 'prepare-stow: converted managed Codex config to a host-local regular file\n'
    return
  fi

  require_safe_regular_file "$config" "host-local Codex config"
  mode=$(stat -c '%a' -- "$config") || abort "cannot inspect host-local Codex config mode: $config"
  [[ "$mode" == 400 || "$mode" == 600 ]] || abort "host-local Codex config must have owner-only non-executable mode: $config"
  printf 'prepare-stow: preserved existing host-local Codex config\n'
}

if (( $# > 0 )); then
  if [[ "$1" == --migrate-codex-config && $# == 1 ]]; then
    migrate_codex_config
    exit 0
  fi
  abort "unsupported arguments: $*"
fi

queue_link() { # path, expected package suffix, optional canonical target suffix
  local path=$1 suffix=$2 canonical_suffix=${3:-$2} target
  if [[ -L $path ]]; then
    target=$(realpath -m -- "$path")
    [[ $target == */"$suffix" || $target == */"$canonical_suffix" ]] ||
      abort "refusing unmanaged symlink: $path -> $(readlink -- "$path")"
    remove_links+=("$path")
  elif [[ -e $path ]]; then
    abort "regular file or directory conflicts with managed endpoint: $path"
  fi
}

queue_retired_link() { # path, expected package suffix
  local path=$1 suffix=$2 target
  [[ -L $path ]] || return 0
  target=$(realpath -m -- "$path")
  [[ $target == */"$suffix" ]] ||
    abort "refusing unmanaged symlink: $path -> $(readlink -- "$path")"
  remove_links+=("$path")
}

queue_generated_state() { # path, expected type, recognized legacy suffix or empty
  local path=$1 expected_type=$2 suffix=${3:-} target
  if [[ -L $path ]]; then
    [[ -n $suffix ]] || abort "refusing unmanaged generated-state symlink: $path -> $(readlink -- "$path")"
    target=$(realpath -m -- "$path")
    [[ $target == */"$suffix" ]] ||
      abort "refusing unmanaged generated-state symlink: $path -> $(readlink -- "$path")"
    remove_links+=("$path")
    return
  fi
  [[ -e $path ]] || return 0
  case $expected_type in
    file) [[ -f $path ]] || abort "generated state is not a regular file: $path" ;;
    dir) [[ -d $path ]] || abort "generated state is not a directory: $path" ;;
    *) abort "unknown generated-state type: $expected_type" ;;
  esac
}

prepare_real_dir() { # path, expected folded-package suffix or empty, optional canonical suffix
  local path=$1 suffix=${2:-} canonical_suffix=${3:-${2:-}} target
  if [[ -L $path ]]; then
    [[ -n $suffix ]] || abort "refusing symlinked state directory: $path"
    target=$(realpath -m -- "$path")
    [[ $target == */"$suffix" || $target == */"$canonical_suffix" ]] ||
      abort "refusing unmanaged directory symlink: $path -> $(readlink -- "$path")"
    remove_links+=("$path")
    create_dirs+=("$path")
    return 1
  fi
  [[ ! -e $path || -d $path ]] || abort "state path is not a directory: $path"
  create_dirs+=("$path")
  return 0
}

prepare_claude() {
  if prepare_real_dir "$HOME/.claude" "claude-code/.claude"; then
    queue_link "$HOME/.claude/CLAUDE.md" "claude-code/.claude/CLAUDE.md"
    queue_link "$HOME/.claude/settings.json" "claude-code/.claude/settings.json"
    queue_link "$HOME/.claude/statusline.sh" "claude-code/.claude/statusline.sh"
    queue_link "$HOME/.claude/agents" "claude-code/.claude/agents"
    queue_link "$HOME/.claude/rules" "claude-code/.claude/rules"
    if prepare_real_dir "$HOME/.claude/skills" "claude-code/.claude/skills"; then
      queue_link "$HOME/.claude/skills/commit" "claude-code/.claude/skills/commit"
      queue_link "$HOME/.claude/skills/spar" "claude-code/.claude/skills/spar"
    fi
  else
    create_dirs+=("$HOME/.claude/skills")
  fi
}

prepare_codex() {
  if prepare_real_dir "$HOME/.codex" "codex/.codex"; then
    queue_link "$HOME/.codex/AGENTS.md" "codex/.codex/AGENTS.md" \
      "claude-code/.claude/rules/shared-guidance.md"
    queue_link "$HOME/.codex/config.toml" "codex/.codex/config.toml"
    queue_retired_link "$HOME/.codex/hooks.json" "codex/.codex/hooks.json"
  fi

  if prepare_real_dir "$HOME/.agents" "codex/.agents"; then
    if prepare_real_dir "$HOME/.agents/skills" "codex/.agents/skills"; then
      queue_link "$HOME/.agents/skills/commit" "codex/.agents/skills/commit"
      queue_link "$HOME/.agents/skills/spar" "codex/.agents/skills/spar"
    fi
  else
    create_dirs+=("$HOME/.agents/skills")
  fi
}

prepare_bins() {
  if prepare_real_dir "$HOME/.local" "claude-code/.local" "codex/.local"; then
    if prepare_real_dir "$HOME/.local/bin" "claude-code/.local/bin" "codex/.local/bin"; then
      queue_link "$HOME/.local/bin/spar-claude" "claude-code/.local/bin/spar-claude"
      queue_link "$HOME/.local/bin/spar-codex" "codex/.local/bin/spar-codex"
      queue_link "$HOME/.local/bin/spar-payload-scan" "claude-code/.local/bin/spar-payload-scan"
      queue_retired_link "$HOME/.local/bin/context-read-gate.sh" \
        "claude-code/.local/bin/context-read-gate.sh"
    fi
  else
    create_dirs+=("$HOME/.local/bin")
  fi
}

prepare_opencode() {
  local root="$HOME/.config/opencode"
  if ! prepare_real_dir "$HOME/.config" "opencode/.config"; then
    create_dirs+=("$root")
    return
  fi

  if ! prepare_real_dir "$root" "opencode/.config/opencode"; then
    return
  fi
  [[ -d $root ]] || return 0

  queue_link "$root/AGENTS.md" "opencode/.config/opencode/AGENTS.md"
  queue_link "$root/agents" "opencode/.config/opencode/agents"
  queue_link "$root/commands" "opencode/.config/opencode/commands"
  queue_link "$root/opencode.json" "opencode/.config/opencode/opencode.json"
  queue_link "$root/plugins" "opencode/.config/opencode/plugins"
  queue_link "$root/skills" "opencode/.config/opencode/skills"
  queue_link "$root/themes" "opencode/.config/opencode/themes"
  if [[ -d $root/tools && ! -L $root/tools ]]; then
    queue_retired_link "$root/tools/external-context.ts" \
      "opencode/.config/opencode/tools/external-context.ts"
    queue_retired_link "$root/tools/package.json" \
      "opencode/.config/opencode/tools/package.json"
  else
    queue_link "$root/tools" "opencode/.config/opencode/tools"
  fi
  queue_link "$root/tui.json" "opencode/.config/opencode/tui.json"
  queue_generated_state "$root/package.json" file "opencode/.config/opencode/package.json"
  queue_generated_state "$root/package-lock.json" file "opencode/.config/opencode/package-lock.json"
  queue_generated_state "$root/bun.lock" file
  queue_generated_state "$root/bun.lockb" file
  queue_generated_state "$root/node_modules" dir "opencode/.config/opencode/node_modules"
}

prepare_claude
prepare_codex
prepare_bins
prepare_opencode

for path in "${remove_links[@]}"; do
  rm -- "$path"
  printf 'removed managed symlink: %s\n' "$path"
done
for path in "${create_dirs[@]}"; do
  mkdir -p -- "$path"
done
