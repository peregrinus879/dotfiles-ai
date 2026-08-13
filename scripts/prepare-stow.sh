#!/usr/bin/env bash
# Prepare user state directories for Stow without deleting regular files.
set -euo pipefail

declare -a remove_links=()
declare -a create_dirs=()

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

queue_link() { # path, expected package suffix
  local path=$1 suffix=$2 target
  if [[ -L $path ]]; then
    target=$(realpath -m -- "$(dirname -- "$path")/$(readlink -- "$path")")
    [[ $target == */"$suffix" ]] ||
      abort "refusing unmanaged symlink: $path -> $(readlink -- "$path")"
    remove_links+=("$path")
  elif [[ -e $path ]]; then
    abort "regular file or directory conflicts with managed endpoint: $path"
  fi
}

prepare_real_dir() { # path, expected folded-package suffix or empty
  local path=$1 suffix=${2:-} target
  if [[ -L $path ]]; then
    [[ -n $suffix ]] || abort "refusing symlinked state directory: $path"
    target=$(realpath -m -- "$(dirname -- "$path")/$(readlink -- "$path")")
    [[ $target == */"$suffix" ]] ||
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
    queue_link "$HOME/.codex/AGENTS.md" "codex/.codex/AGENTS.md"
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
  if prepare_real_dir "$HOME/.local" "claude-code/.local"; then
    if prepare_real_dir "$HOME/.local/bin" "claude-code/.local/bin"; then
      queue_link "$HOME/.local/bin/spar-claude" "claude-code/.local/bin/spar-claude"
      queue_link "$HOME/.local/bin/spar-codex" "codex/.local/bin/spar-codex"
    fi
  else
    create_dirs+=("$HOME/.local/bin")
  fi
}

prepare_opencode() {
  local root="$HOME/.config/opencode"
  if ! prepare_real_dir "$HOME/.config" "opencode/.config"; then
    return
  fi

  if [[ -L $root ]]; then
    queue_link "$root" "opencode/.config/opencode"
    return
  fi
  [[ ! -e $root || -d $root ]] || abort "OpenCode config path is not a directory: $root"
  [[ -d $root ]] || return 0

  queue_link "$root/.gitignore" "opencode/.config/opencode/.gitignore"
  queue_link "$root/AGENTS.md" "opencode/.config/opencode/AGENTS.md"
  queue_link "$root/agents" "opencode/.config/opencode/agents"
  queue_link "$root/bun.lock" "opencode/.config/opencode/bun.lock"
  queue_link "$root/commands" "opencode/.config/opencode/commands"
  queue_link "$root/node_modules" "opencode/.config/opencode/node_modules"
  queue_link "$root/opencode.json" "opencode/.config/opencode/opencode.json"
  queue_link "$root/package-lock.json" "opencode/.config/opencode/package-lock.json"
  queue_link "$root/package.json" "opencode/.config/opencode/package.json"
  queue_link "$root/plugins" "opencode/.config/opencode/plugins"
  queue_link "$root/skills" "opencode/.config/opencode/skills"
  queue_link "$root/themes" "opencode/.config/opencode/themes"
  queue_link "$root/tools" "opencode/.config/opencode/tools"
  queue_link "$root/tui.json" "opencode/.config/opencode/tui.json"
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
