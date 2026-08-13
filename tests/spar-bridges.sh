#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/claude" <<'SHIM'
#!/usr/bin/env bash
if [[ ${1:-} == auth && ${2:-} == status ]]; then
  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}'
  exit
fi
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
printf '%s\n' '{"type":"result","is_error":false,"result":"review ok"}'
SHIM

cat >"$TMP/bin/codex" <<'SHIM'
#!/usr/bin/env bash
if [[ ${1:-} == login && ${2:-} == status ]]; then
  printf '%s\n' 'Logged in using ChatGPT'
  exit
fi
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  printf '%s\n' '{"installed":[]}'
  exit
fi
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
printf '%s\n' '{"type":"turn.completed"}'
SHIM

chmod 755 "$TMP/bin/claude" "$TMP/bin/codex"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

make_handoff() {
  local root
  root="/tmp/spar-$(cat /proc/sys/kernel/random/uuid)"
  mkdir -m 700 -- "$root"
  printf '%s\n' "$root"
}

run_bridge() { # bridge, prompt, optional handoff content
  local bridge=$1 prompt=$2 content=${3:-} handoff calls rc=0
  handoff=$(make_handoff)
  calls="$TMP/calls-$RANDOM"
  [[ -z $content ]] || printf '%s' "$content" >"$handoff/payload.md"
  SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$bridge" new "$handoff" "$prompt" \
    >/dev/null 2>/dev/null || rc=$?
  BRIDGE_RC=$rc
  BRIDGE_CALLED=0
  [[ ! -s $calls ]] || BRIDGE_CALLED=1
  rm -rf -- "$handoff"
}

for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  run_bridge "$bridge" "Review this ordinary plan."
  [[ $BRIDGE_RC == 0 && $BRIDGE_CALLED == 1 ]] || fail "ordinary payload did not reach ${bridge##*/}"

  run_bridge "$bridge" 'OPENAI_API_KEY="sk-0123456789abcdef0123456789abcdef"'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "API-key prompt reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "private-key handoff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'diff --git a/.env.production b/.env.production\n--- a/.env.production\n+++ b/.env.production\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "sensitive diff path reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'Read(~/.codex/auth.json) = deny\n.env.* = deny\n**/*.key = deny\n'
  [[ $BRIDGE_RC == 0 && $BRIDGE_CALLED == 1 ]] || fail "policy text was falsely rejected by ${bridge##*/}"
done

handoff=$(make_handoff)
calls="$TMP/codex-flags"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  new "$handoff" "Review flags." >/dev/null 2>/dev/null
new_flags=$(<"$calls")
rm -f "$calls"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  resume 11111111-1111-4111-8111-111111111111 "$handoff" "Review flags." >/dev/null 2>/dev/null
resume_flags=$(<"$calls")
for flag in --ignore-user-config --ignore-rules --strict-config 'default_permissions="spar-reviewer"' \
  'forced_login_method="chatgpt"' 'model_provider="openai"' 'web_search="disabled"'; do
  [[ $new_flags == *"$flag"* && $resume_flags == *"$flag"* ]] || fail "Codex new/resume isolation parity missing: $flag"
done
[[ $new_flags != *' -s read-only '* && $resume_flags != *'sandbox_mode'* ]] ||
  fail "legacy Codex sandbox override remains"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/claude-env"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" ANTHROPIC_AUTH_TOKEN=sentinel \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review auth." >/dev/null 2>/dev/null; then
  fail "Claude bridge accepted alternate auth environment"
fi
[[ ! -s $calls ]] || fail "Claude reviewer was invoked after alternate auth rejection"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-env"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" CODEX_API_KEY=sentinel \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review auth." >/dev/null 2>/dev/null; then
  fail "Codex bridge accepted API-key environment"
fi
[[ ! -s $calls ]] || fail "Codex reviewer was invoked after API-key rejection"
rm -rf -- "$handoff"

handoff=$(make_handoff)
printf 'binary\0content' >"$handoff/payload.bin"
if printf 'Review.' | "$ROOT/claude-code/.local/bin/spar-payload-scan" "$handoff" >/dev/null 2>&1; then
  fail "binary handoff passed scanner"
fi
rm -rf -- "$handoff"

printf 'ok: spar bridges block sensitive outbound payloads before reviewer invocation\n'
