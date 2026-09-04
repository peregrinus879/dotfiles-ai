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
#
# --link-skills: make each ~/.agents/skills/<name> one link to the skill's
# directory in the agents package, the shape Codex's skill loader follows
# (it skips symlinks that are not directories, so the leaf links a no-folding
# deploy would leave hide the skill). A directory left by an earlier deploy is
# emptied of the links that resolve into that skill's source and removed; any
# other entry, or a link that resolves elsewhere, stops the script and stays.
# --unlink-skills removes the links that resolve into this clone's package.
set -euo pipefail

abort() {
  printf 'prepare-stow: %s\n' "$1" >&2
  exit 1
}

script_dir=$(dirname -- "${BASH_SOURCE[0]}")
repository_root=$(realpath -e -- "$script_dir/..") || abort 'cannot resolve repository root'
PACKAGES=(agents claude-code codex opencode)
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

package_skills() {
  local dir
  for dir in "$repository_root"/agents/.agents/skills/*/; do
    [[ -d $dir ]] || continue
    basename -- "$dir"
  done
}

link_skills() {
  local root="$HOME/.agents/skills" name source target text entry
  [[ -n ${HOME:-} && $HOME != / ]] || abort 'HOME must name a non-root directory'
  [[ ! -L $root ]] || abort "the skills root must be a real directory, not a link: $root"
  mkdir -p -- "$root"
  while IFS= read -r name; do
    source="$repository_root/agents/.agents/skills/$name"
    target="$root/$name"
    text=$(realpath --relative-to="$root" -- "$source")
    if [[ -L $target ]]; then
      [[ $(realpath -m -- "$target") == "$source" ]] && continue
      abort "refusing to repoint a skill link that resolves elsewhere: $target"
    elif [[ -d $target ]]; then
      while IFS= read -r -d '' entry; do
        case $(realpath -m -- "$entry") in
          "$source"/*) rm -- "$entry" ;;
          *) abort "foreign entry inside a managed skill directory: $entry" ;;
        esac
      done < <(find "$target" -type l -print0)
      find "$target" -depth -type d -exec rmdir -- {} + 2>/dev/null || true
      [[ ! -e $target ]] || abort "skill directory still holds entries that are not its own links: $target"
    elif [[ -e $target ]]; then
      abort "skill endpoint is neither a link nor a directory: $target"
    fi
    ln -s -- "$text" "$target"
    printf 'linked skill directory: %s -> %s\n' "$target" "$text"
  done < <(package_skills)
}

unlink_skills() {
  local root="$HOME/.agents/skills" name target
  while IFS= read -r name; do
    target="$root/$name"
    [[ -L $target ]] || continue
    [[ $(realpath -m -- "$target") == "$repository_root/agents/.agents/skills/$name" ]] || continue
    rm -- "$target"
    printf 'removed skill directory link: %s\n' "$target"
  done < <(package_skills)
}

case ${1:-} in
  '') clean_links ;;
  --migrate-codex-config)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    migrate_codex_config ;;
  --link-skills)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    link_skills ;;
  --unlink-skills)
    [[ $# == 1 ]] || abort "unsupported arguments: $*"
    unlink_skills ;;
  *) abort "unsupported arguments: $*" ;;
esac
