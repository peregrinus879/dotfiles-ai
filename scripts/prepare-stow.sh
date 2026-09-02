#!/usr/bin/env bash
# Prepare $HOME for `stow --no-folding`, and migrate the Codex config on request.
#
# Without arguments: remove dangling symlinks under the managed target
# directories whose link text points into one of this repository's packages
# (retired files, moved clones). Links that resolve, links that point
# elsewhere, and regular files are never touched; Stow itself reports any
# remaining conflict without changing the filesystem.
#
# --migrate-codex-config: make ~/.codex/config.toml a host-local, owner-only
# regular file. A managed symlink is converted in place with its current bytes;
# a dangling managed symlink or a missing file is seeded from the portable
# template; an existing regular file is preserved.
set -euo pipefail

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

script_dir=$(dirname -- "${BASH_SOURCE[0]}")
repository_root=$(realpath -e -- "$script_dir/..") || abort 'cannot resolve repository root'
repository_name=${repository_root##*/}
PACKAGES=(claude-code codex opencode)
TARGET_ROOTS=("$HOME/.claude" "$HOME/.codex" "$HOME/.agents" "$HOME/.local/bin" "$HOME/.config/opencode")

managed_link_text() { # link text
  local package
  for package in "${PACKAGES[@]}"; do
    [[ $1 != *"/$repository_name/$package/"* ]] || return 0
  done
  return 1
}

clean_links() {
  local root path text
  [[ -n ${HOME:-} && $HOME != / ]] || abort 'HOME must name a non-root directory'
  for root in "${TARGET_ROOTS[@]}"; do
    [[ -d $root && ! -L $root ]] || continue
    while IFS= read -r -d '' path; do
      text=$(readlink -- "$path") || continue
      managed_link_text "$text" || continue
      rm -- "$path"
      printf 'removed dangling managed link: %s\n' "$path"
    done < <(find "$root" -xtype l -print0 2>/dev/null)
  done
}

migrate_codex_config() {
  local codex_root="$HOME/.codex" config template source temp
  template="$repository_root/templates/codex/config.toml"
  config="$codex_root/config.toml"
  [[ -f $template && ! -L $template ]] || abort "Codex portable template is missing: $template"
  [[ -d $codex_root && ! -L $codex_root && -O $codex_root ]] ||
    abort "Codex runtime root must be a real directory owned by you: $codex_root"

  if [[ -L $config ]]; then
    if source=$(realpath -e -- "$config" 2>/dev/null); then
      [[ $source == "$repository_root/codex/.codex/config.toml" ]] ||
        abort "Codex config symlink does not target this clone's managed leaf: $config -> $source"
    else
      managed_link_text "$(readlink -- "$config")" ||
        abort "refusing to replace an unmanaged dangling Codex config symlink: $config"
      source=$template
    fi
  elif [[ -e $config ]]; then
    [[ -f $config && -O $config && $(stat -c '%a' -- "$config") =~ ^[46]00$ ]] ||
      abort "host-local Codex config must be a regular owner-only file: $config"
    printf 'prepare-stow: preserved existing host-local Codex config\n'
    return
  else
    source=$template
  fi

  umask 077
  temp=$(mktemp -- "$codex_root/.config.toml.XXXXXX") || abort 'cannot create migration temporary file'
  trap 'rm -f -- "$temp"' EXIT
  cat -- "$source" >"$temp" || abort 'cannot copy migration source'
  sync -f -- "$temp" || abort 'cannot flush migration temporary file'
  mv -T -- "$temp" "$config" || abort "cannot install migrated Codex config: $config"
  trap - EXIT
  printf 'prepare-stow: installed host-local Codex config from %s\n' "$source"
}

case ${1:-} in
  '') clean_links ;;
  --migrate-codex-config)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    migrate_codex_config ;;
  *) abort "unsupported arguments: $*" ;;
esac
