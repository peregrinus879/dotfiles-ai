#!/usr/bin/env bash
# Prepare user state directories for Stow without deleting regular files.
set -euo pipefail

declare -a remove_links=()
declare -a create_dirs=()

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

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
  queue_link "$root/tools" "opencode/.config/opencode/tools"
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
