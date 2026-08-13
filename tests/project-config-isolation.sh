#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/home/.config/opencode/plugins" "$TMP/project/.git" "$TMP/project/.opencode/plugins"

cp "$ROOT/opencode/.config/opencode/opencode.json" "$TMP/home/.config/opencode/opencode.json"
cp "$ROOT/opencode/.config/opencode/plugins/reviewed-writes.ts" \
  "$TMP/home/.config/opencode/plugins/reviewed-writes.ts"
cat >"$TMP/project/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": {
      "project-probe": "allow"
    }
  }
}
JSON
cat >"$TMP/project/.opencode/plugins/project-probe.ts" <<'PLUGIN'
export const ProjectProbe = async () => {
  throw new Error("PROJECT_PLUGIN_LOADED")
}
PLUGIN

enabled=$(cd "$TMP/project" && HOME="$TMP/home" OPENCODE_CONFIG_DIR="$TMP/home/.config/opencode" \
  opencode debug config 2>&1 || true)
[[ $enabled == *'PROJECT_PLUGIN_LOADED'* || $enabled == *'"project-probe": "allow"'* ]] || {
  printf 'FAIL: project config/plugin did not load in the control case\n' >&2
  exit 1
}

disabled=$(cd "$TMP/project" && HOME="$TMP/home" OPENCODE_CONFIG_DIR="$TMP/home/.config/opencode" \
  OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode debug config 2>&1)
[[ $disabled != *'PROJECT_PLUGIN_LOADED'* && $disabled != *'"project-probe": "allow"'* ]] || {
  printf 'FAIL: disabled project config or plugin still loaded\n' >&2
  exit 1
}
[[ $disabled == *'reviewed-writes.ts'* ]] || {
  printf 'FAIL: global reviewed-writes plugin disappeared under project isolation\n' >&2
  exit 1
}

printf 'ok: OpenCode project config isolation preserves global controls\n'

claude_help=$(claude -p --help)
[[ $claude_help == *'--safe-mode'* && $claude_help == *'hooks'* && $claude_help == *'disabled'* ]] || {
  printf 'FAIL: Claude safe-mode isolation contract is unavailable\n' >&2
  exit 1
}
[[ $claude_help == *'--setting-sources <sources>'* && $claude_help == *'user, project, local'* ]] || {
  printf 'FAIL: Claude setting-source isolation contract is unavailable\n' >&2
  exit 1
}

printf 'ok: Claude project config isolation flags are available\n'
