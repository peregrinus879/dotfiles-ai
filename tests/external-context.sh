#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
GATE="$ROOT/claude-code/.local/bin/context-read-gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$TMP/workspace" "$TMP/external/list" "$TMP/external/large" "$TMP/home/.docker"
printf 'workspace\n' >"$TMP/workspace/local.txt"
printf 'external\n' >"$TMP/external/public.txt"
printf 'listed\n' >"$TMP/external/list/entry.txt"
printf 'sensitive canary\n' >"$TMP/external/.env"
printf '\0binary\n' >"$TMP/external/binary.bin"
printf 'synthetic registry config\n' >"$TMP/home/.docker/config.json"
ln -s "$TMP/external/public.txt" "$TMP/external/alias.txt"
ln "$TMP/external/public.txt" "$TMP/external/hardlink.txt"
for index in $(seq 1 129); do : >"$TMP/external/large/$index"; done

claude_input() {
  jq -nc --arg cwd "$TMP/workspace" --arg path "$1" '{
    hook_event_name: "PreToolUse",
    tool_name: "Read",
    cwd: $cwd,
    tool_input: {file_path: $path}
  }'
}

codex_input() {
  local path=$1 mode=${2:-read}
  jq -nc --arg cwd "$TMP/workspace" --arg path "$path" --arg mode "$mode" '{
    hook_event_name: "PreToolUse",
    tool_name: "request_permissions",
    cwd: $cwd,
    tool_input: {
      reason: "Read the exact external context named by H",
      permissions: {
        file_system: (if $mode == "read" then {read: [$path]} else {read: [], write: [$path]} end)
      }
    }
  }'
}

output=$(claude_input "$TMP/workspace/local.txt" | "$GATE")
[[ -z $output ]] || fail "workspace read did not defer"
output=$(claude_input "$TMP/external/list" | "$GATE")
[[ $output == *'"permissionDecision":"ask"'* ]] || fail "external directory did not ask"
for path in "$TMP/external/.env" "$TMP/external/alias.txt" "$TMP/external/public.txt" \
  "$TMP/external/large" "$TMP/external" "$TMP/external/missing*"; do
  output=$(claude_input "$path" | "$GATE")
  [[ $output == *'"permissionDecision":"deny"'* ]] || fail "unsafe external target did not deny: $path"
done
output=$(claude_input "$TMP/home/.docker/config.json" | HOME="$TMP/home" "$GATE")
[[ $output == *'"permissionDecision":"deny"'* ]] || fail "Docker credential root did not deny"
output=$(claude_input "/var/tmp/spar-external-context-fixture" | "$GATE")
[[ $output == *'"permissionDecision":"deny"'* ]] || fail "spar handoff path did not deny"

output=$(codex_input "$TMP/external/list/entry.txt" | "$GATE")
[[ -z $output ]] || fail "valid Codex exact read did not defer to approval"
output=$(codex_input "$TMP/external/list/entry.txt" write | "$GATE")
[[ $output == *'"permissionDecision":"deny"'* ]] || fail "Codex write request did not deny"
subagent=$(codex_input "$TMP/external/list/entry.txt" | jq '. + {agent_id: "child"}')
output=$(printf '%s\n' "$subagent" | "$GATE")
[[ $output == *'"permissionDecision":"deny"'* ]] || fail "Codex subagent request did not deny"
multi=$(codex_input "$TMP/external/list/entry.txt" | jq --arg second "$TMP/external/list" \
  '.tool_input.permissions.file_system.read += [$second]')
output=$(printf '%s\n' "$multi" | "$GATE")
[[ $output == *'"permissionDecision":"deny"'* ]] || fail "Codex multi-read request did not deny"
session=$(codex_input "$TMP/external/list/entry.txt" | jq '.tool_input.scope = "session"')
output=$(printf '%s\n' "$session" | "$GATE")
[[ $output == *'"permissionDecision":"deny"'* ]] || fail "Codex unsupported scope input did not deny"
if printf '{\n' | "$GATE" >/dev/null 2>&1; then fail "malformed hook input did not fail closed"; fi

ROOT=$ROOT FIXTURE_ROOT="$TMP" HOME="$TMP/home" node --experimental-strip-types --input-type=module <<'NODE'
import assert from "node:assert/strict"
import path from "node:path"
import { pathToFileURL } from "node:url"

const root = process.env.ROOT
const fixture = process.env.FIXTURE_ROOT
const toolPath = path.join(root, "opencode/.config/opencode/tools/external-context.ts")
const { default: externalContext } = await import(pathToFileURL(toolPath).href)
const asks = []
const context = {
  agent: "build",
  worktree: path.join(fixture, "workspace"),
  abort: new AbortController().signal,
  ask: async (request) => asks.push(request),
}

const publicPath = path.join(fixture, "external/list/entry.txt")
const readResult = await externalContext.execute({ operation: "read", path: publicPath }, context)
assert.equal(readResult.output, "listed\n")
assert.deepEqual(asks.at(-1).patterns, [publicPath])
assert.deepEqual(asks.at(-1).always, [])

const listPath = path.join(fixture, "external/list")
const listResult = await externalContext.execute({ operation: "list", path: listPath }, context)
assert.match(listResult.output, /file\tentry\.txt/)

const askCount = asks.length
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "external/.env") }, context),
)
assert.equal(asks.length, askCount)
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "home/.docker/config.json") }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: "/var/tmp/spar-external-context-fixture" }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: "/proc/version" }, context),
)
assert.equal(asks.length, askCount)
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "external/missing.txt") }, context),
)
assert.deepEqual(asks.at(-1).patterns, [path.join(fixture, "external/missing.txt")])
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "workspace/local.txt") }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "external/alias.txt") }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "external/public.txt") }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: path.join(fixture, "external/binary.bin") }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "list", path: path.join(fixture, "external") }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: `${fixture}/external/list/../list/entry.txt` }, context),
)
await assert.rejects(
  externalContext.execute({ operation: "read", path: publicPath }, { ...context, agent: "general" }),
)
NODE

printf 'ok: bounded external context gates\n'
