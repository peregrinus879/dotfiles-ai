#!/usr/bin/env bash
# Prepare $HOME for `stow --no-folding`, and reconcile the Codex config on request.
#
# Without arguments: remove dangling symlinks under the managed target
# directories whose link text names a path inside one of this repository's
# packages, recognized by the package name followed by a top-level entry that
# package really has, so retired files and moved or renamed clones are cleaned
# and unrelated links with a similar spelling are not. The match is not bound
# to this clone's path, so a dangling link into another clone with the same
# package layout is removed too; only dangling links are ever removed. Links
# that resolve, links that point elsewhere, and regular files are never
# touched; Stow itself reports any remaining conflict without changing the
# filesystem.
#
# --migrate-codex-config: make ~/.codex/config.toml a host-local, owner-only
# regular file that carries the portable template's root keys and tables and
# preserves every host-only table Codex or the desktop app wrote (projects,
# marketplaces, plugins, mcp_servers, shell_environment_policy, desktop). A
# missing file or a managed symlink is replaced by the template; a regular file
# that already matches the template is left untouched.
set -euo pipefail

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

script_dir=$(dirname -- "${BASH_SOURCE[0]}")
repository_root=$(realpath -e -- "$script_dir/..") || abort 'cannot resolve repository root'
PACKAGES=(claude-code codex opencode)
TARGET_ROOTS=("$HOME/.claude" "$HOME/.codex" "$HOME/.agents" "$HOME/.local/bin" "$HOME/.config/opencode")

managed_link_text() { # link text
  local text=$1 package tail
  for package in "${PACKAGES[@]}"; do
    [[ $text == *"/$package/"* ]] || continue
    tail=${text#*"/$package/"}
    [[ -n $tail && -e "$repository_root/$package/${tail%%/*}" ]] && return 0
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
  local codex_root="$HOME/.codex" config template reconcile temp
  local -a host=()
  template="$repository_root/templates/codex/config.toml"
  reconcile="$repository_root/scripts/reconcile-codex-config.py"
  config="$codex_root/config.toml"
  [[ -f $template && ! -L $template ]] || abort "Codex portable template is missing: $template"
  [[ -f $reconcile ]] || abort "Codex reconciliation script is missing: $reconcile"
  command -v python3 >/dev/null || abort 'python3 is required for Codex config reconciliation'
  [[ -d $codex_root && ! -L $codex_root && -O $codex_root ]] ||
    abort "Codex runtime root must be a real directory owned by you: $codex_root"

  if [[ -L $config ]]; then
    managed_link_text "$(readlink -- "$config")" ||
      abort "refusing to replace an unmanaged Codex config symlink: $config"
  elif [[ -e $config ]]; then
    [[ -f $config && -O $config ]] || abort "host-local Codex config must be a regular file owned by you: $config"
    if python3 "$reconcile" check "$template" "$config" && [[ $(stat -c '%a' -- "$config") =~ ^[46]00$ ]]; then
      printf 'prepare-stow: host-local Codex config already matches the template\n'
      return
    fi
    host=("$config")
  fi

  umask 077
  temp=$(mktemp -- "$codex_root/.config.toml.XXXXXX") || abort 'cannot create reconciliation temporary file'
  trap 'rm -f -- "$temp"' EXIT
  python3 "$reconcile" merge "$template" "${host[@]}" >"$temp" || abort 'cannot reconcile the Codex config'
  sync -f -- "$temp" || abort 'cannot flush the reconciled Codex config'
  mv -T -- "$temp" "$config" || abort "cannot install the reconciled Codex config: $config"
  trap - EXIT
  if ((${#host[@]})); then
    printf 'prepare-stow: reconciled host-local Codex config with the template, host tables preserved\n'
  else
    printf 'prepare-stow: installed host-local Codex config from the template\n'
  fi
}

case ${1:-} in
  '') clean_links ;;
  --migrate-codex-config)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    migrate_codex_config ;;
  *) abort "unsupported arguments: $*" ;;
esac
