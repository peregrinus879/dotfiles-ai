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
case ${SPAR_TEST_MODE:-ok} in
  ok) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok"}' ;;
  eof) : ;;
  duplicate)
    printf '%s\n' '{"type":"result","is_error":false,"result":"review ok"}'
    printf '%s\n' '{"type":"result","is_error":false,"result":"review twice"}' ;;
  empty) printf '%s\n' '{"type":"result","is_error":false,"result":""}' ;;
  failure) printf '%s\n' '{"type":"result","is_error":true,"result":"review failed"}' ;;
  stall)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do sleep 1; done ;;
  ceiling)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do printf '%s\n' '{"type":"stream_event"}'; sleep 0.2; done ;;
esac
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
case ${SPAR_TEST_MODE:-ok} in
  ok)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  eof) printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}' ;;
  duplicate)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  empty)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":""}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  failure) printf '%s\n' '{"type":"turn.failed","error":"review failed"}' ;;
  malformed)
    printf '%s\n' '{"type":"thread.started","thread_id":"not-a-uuid"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  stall)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do sleep 1; done ;;
  ceiling)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do printf '%s\n' '{"type":"turn.started"}'; sleep 0.2; done ;;
esac
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

  private_key_canary=$(printf '%s%s\n%s\n' '-----BEGIN PRIVATE ' 'KEY-----' 'not-a-real-key')
  run_bridge "$bridge" "Review the handoff." "$private_key_canary"
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "private-key handoff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'diff --git a/.env.production b/.env.production\n--- a/.env.production\n+++ b/.env.production\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "sensitive diff path reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'Read(~/.codex/auth.json) = deny\n.env.* = deny\n**/*.key = deny\n'
  [[ $BRIDGE_RC == 0 && $BRIDGE_CALLED == 1 ]] || fail "policy text was falsely rejected by ${bridge##*/}"
done

for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  for mode in eof duplicate empty failure; do
    handoff=$(make_handoff)
    calls="$TMP/terminal-${bridge##*/}-$mode"
    if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
      "$bridge" new "$handoff" "Review terminal events." >/dev/null 2>/dev/null; then
      fail "${bridge##*/} accepted terminal mode $mode"
    fi
    rm -rf -- "$handoff"
  done
done

handoff=$(make_handoff)
calls="$TMP/codex-malformed"
if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=malformed PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review terminal events." >/dev/null 2>/dev/null; then
  fail "spar-codex accepted malformed thread id"
fi
rm -rf -- "$handoff"

for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  for mode in stall ceiling; do
    handoff=$(make_handoff)
    calls="$TMP/timeout-${bridge##*/}-$mode"
    child_pid_file="$TMP/child-${bridge##*/}-$mode"
    start=$(date +%s)
    if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=$mode SPAR_TEST_CHILD_PID=$child_pid_file \
      SPAR_BRIDGE_STALL=1 SPAR_BRIDGE_CEILING=2 PATH="$TMP/bin:$PATH" \
      "$bridge" new "$handoff" "Review timeout." >/dev/null 2>/dev/null; then
      fail "${bridge##*/} accepted timeout mode $mode"
    fi
    elapsed=$(($(date +%s) - start))
    [[ $elapsed -le 6 ]] || fail "${bridge##*/} $mode exceeded bounded shutdown"
    if [[ -s $child_pid_file ]]; then
      child_pid=$(<"$child_pid_file")
      if kill -0 "$child_pid" 2>/dev/null; then fail "${bridge##*/} left descendant after $mode"; fi
    fi
    rm -rf -- "$handoff"
  done
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
  'forced_login_method="chatgpt"' 'model_provider="openai"' 'web_search="disabled"' \
  'service_tier="fast"' 'features.fast_mode=true'; do
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
