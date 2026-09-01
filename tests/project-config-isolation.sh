#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
OPENCODE_TEST_ENV=(
  env
  -u OPENCODE_DISABLE_CLAUDE_CODE
  -u OPENCODE_DISABLE_CLAUDE_CODE_SKILLS
  -u OPENCODE_DISABLE_EXTERNAL_SKILLS
  -u OPENCODE_DISABLE_PROJECT_CONFIG
  -u OPENCODE_PURE
)
mkdir -p "$TMP/home/.config/opencode" "$TMP/package/opencode/plugins" \
  "$TMP/home/.config/opencode/skills/commit" "$TMP/home/.config/opencode/skills/spar" \
  "$TMP/home/.claude/skills/omarchy" "$TMP/home/.claude/skills/external-claude-probe" \
  "$TMP/home/.agents/skills/external-agent-probe" "$TMP/project/.git" "$TMP/project/.opencode/plugins"

cp "$ROOT/opencode/.config/opencode/opencode.json" "$TMP/home/.config/opencode/opencode.json"
cp "$ROOT/opencode/.config/opencode/plugins/reviewed-writes.ts" \
  "$TMP/package/opencode/plugins/reviewed-writes.ts"
cp "$ROOT/opencode/.config/opencode/plugins/package.json" \
  "$TMP/package/opencode/plugins/package.json"
ln -s "$TMP/package/opencode/plugins" "$TMP/home/.config/opencode/plugins"
cp "$ROOT/opencode/.config/opencode/skills/commit/SKILL.md" \
  "$TMP/home/.config/opencode/skills/commit/SKILL.md"
cp "$ROOT/opencode/.config/opencode/skills/spar/SKILL.md" \
  "$TMP/home/.config/opencode/skills/spar/SKILL.md"
cat >"$TMP/home/.claude/skills/omarchy/SKILL.md" <<'SKILL'
---
name: omarchy
description: Explicitly retained host skill.
---

Explicit host skill fixture.
SKILL
cat >"$TMP/home/.claude/skills/external-claude-probe/SKILL.md" <<'SKILL'
---
name: external-claude-probe
description: External Claude skill discovery fixture.
---

External Claude discovery fixture.
SKILL
cat >"$TMP/home/.agents/skills/external-agent-probe/SKILL.md" <<'SKILL'
---
name: external-agent-probe
description: External agent skill discovery fixture.
---

External agent discovery fixture.
SKILL
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

# run_opencode [extra VAR=value words] <opencode arguments...>: the shared
# project-cwd invocation with the isolated home; extra env words precede the
# command per env(1).
run_opencode() {
  (cd "$TMP/project" && "${OPENCODE_TEST_ENV[@]}" \
    HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" \
    OPENCODE_CONFIG_DIR="$TMP/home/.config/opencode" "$@")
}

enabled=$(run_opencode opencode debug config 2>&1 || true)
[[ $enabled == *'PROJECT_PLUGIN_LOADED'* || $enabled == *'"project-probe": "allow"'* ]] || {
  printf 'FAIL: project config/plugin did not load in the control case\n' >&2
  exit 1
}

skills_enabled=$(run_opencode opencode debug skill 2>&1)
[[ $skills_enabled == *"$TMP/home/.claude/skills/external-claude-probe/SKILL.md"* && \
  $skills_enabled == *"$TMP/home/.agents/skills/external-agent-probe/SKILL.md"* ]] || {
  printf 'FAIL: external skill discovery did not load in the control case\n' >&2
  exit 1
}

disabled=$(run_opencode OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode debug config 2>&1)
[[ $disabled != *'PROJECT_PLUGIN_LOADED'* && $disabled != *'"project-probe": "allow"'* ]] || {
  printf 'FAIL: disabled project config or plugin still loaded\n' >&2
  exit 1
}
if ! jq -e --arg spec "file://$TMP/home/.config/opencode/plugins/reviewed-writes.ts" \
  '.plugin_origins | any(.spec == $spec and .scope == "global")' <<<"$disabled" >/dev/null; then
  printf 'FAIL: global reviewed-writes plugin was not registered through its managed symlink\n' >&2
  exit 1
fi
node --experimental-strip-types --input-type=module -e '
  import { pathToFileURL } from "node:url"
  const module = await import(pathToFileURL(process.argv[1]).href)
  const plugin = await module.ReviewedWritesPlugin({ directory: process.argv[2] })
  if (typeof plugin["tool.execute.before"] !== "function") process.exit(1)
' "$TMP/home/.config/opencode/plugins/reviewed-writes.ts" "$TMP/project"

skills_disabled=$(run_opencode OPENCODE_DISABLE_EXTERNAL_SKILLS=1 opencode debug skill 2>&1)
for managed in \
  "$TMP/home/.config/opencode/skills/commit/SKILL.md" \
  "$TMP/home/.config/opencode/skills/spar/SKILL.md" \
  "$TMP/home/.claude/skills/omarchy/SKILL.md"; do
  [[ $skills_disabled == *"$managed"* ]] || {
    printf 'FAIL: managed or explicit skill missing under external isolation: %s\n' "$managed" >&2
    exit 1
  }
done
[[ $skills_disabled != *"$TMP/home/.claude/skills/external-claude-probe/SKILL.md"* && \
  $skills_disabled != *"$TMP/home/.agents/skills/external-agent-probe/SKILL.md"* ]] || {
  printf 'FAIL: automatic external skill survived isolation\n' >&2
  exit 1
}

if ! run_opencode OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
  OPENCODE_CONFIG_CONTENT='{"skills":{"paths":["~/missing-opencode-skill"]}}' \
  opencode debug skill >/dev/null; then
  printf 'FAIL: missing explicit skill path broke startup\n' >&2
  exit 1
fi

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
