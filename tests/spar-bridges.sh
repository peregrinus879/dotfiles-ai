#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/claude" <<'SHIM'
#!/usr/bin/env bash
[[ ${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-} == 1 ]] || exit 91
[[ ${DISABLE_AUTOUPDATER:-} == 1 ]] || exit 92
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
  if [[ ${SPAR_TEST_MODE:-ok} == plugin-leak || " $* " != *' features.plugins=false '* ]]; then
    printf '%s\n' '{"installed":[{"pluginId":"ambient@test"}]}'
  else
    printf '%s\n' '{"installed":[]}'
  fi
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
  stderr-failure)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' 'transport handshake failed' >&2
    exit 1 ;;
  stderr-empty)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    exit 1 ;;
  stderr-held-open)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    (trap '' TERM; sleep 30) >/dev/null &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    printf '%s\n' 'transport failed with a lingering stderr holder' >&2
    exit 1 ;;
  stderr-limit)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' 'rate limit reached; resets at 12:34 UTC' >&2
    exit 1 ;;
  stderr-sensitive)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf 'OPENAI_API_KEY=%s\n' "$SPAR_TEST_SECRET" >&2
    exit 1 ;;
  stderr-oversized)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%09000d' 0 >&2
    exit 1 ;;
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
  root="/var/tmp/spar-$(cat /proc/sys/kernel/random/uuid)"
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

  credential_name=$(printf '%s%s' 'OPENAI_' 'API_KEY')
  credential_value=$(printf '%s%s' 'sk' '-0123456789abcdef0123456789abcdef')
  run_bridge "$bridge" "${credential_name}=\"${credential_value}\""
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "API-key prompt reached ${bridge##*/}"

  private_key_canary=$(printf '%s%s\n%s\n' '-----BEGIN PRIVATE ' 'KEY-----' 'not-a-real-key')
  run_bridge "$bridge" "Review the handoff." "$private_key_canary"
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "private-key handoff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'diff --git a/.env.production b/.env.production\n--- a/.env.production\n+++ b/.env.production\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "sensitive diff path reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'Read(~/.codex/auth.json) = deny\n.env.* = deny\n**/*.key = deny\n'
  [[ $BRIDGE_RC == 0 && $BRIDGE_CALLED == 1 ]] || fail "policy text was falsely rejected by ${bridge##*/}"
done

handoff=$(make_handoff)
calls="$TMP/codex-plugin-leak"
if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=plugin-leak PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review plugin isolation." \
  >/dev/null 2>/dev/null; then
  fail "spar-codex accepted plugins after applying its disable override"
fi
[[ ! -s $calls ]] || fail "Codex reviewer was invoked after plugin isolation failed"
rm -rf -- "$handoff"

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

handoff=$(make_handoff)
calls="$TMP/codex-stderr-failure"
rc=0
diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-failure PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review diagnostics." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'transport handshake failed'* ]] ||
  fail "spar-codex did not relay safe reviewer stderr"
[[ $diagnostic == *'SPAR-BRIDGE THREAD: reviewer thread started before failure: 11111111-1111-4111-8111-111111111111'* ]] ||
  fail "spar-codex did not preserve a failed-new thread id"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-stderr-empty"
rc=0
diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-empty PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review diagnostics." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'reviewer exited 1 without stderr'* ]] ||
  fail "spar-codex did not classify an empty reviewer stderr failure"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-stderr-held-open"
child_pid_file="$TMP/codex-stderr-held-open-child"
rc=0
diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-held-open \
  SPAR_TEST_CHILD_PID=$child_pid_file PATH="$TMP/bin:$PATH" \
  timeout --kill-after=1 5 "$ROOT/codex/.local/bin/spar-codex" \
  new "$handoff" "Review diagnostics." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'transport failed with a lingering stderr holder'* ]] ||
  fail "spar-codex did not bound cleanup of a reviewer descendant holding stderr"
if [[ -s $child_pid_file ]]; then
  child_pid=$(<"$child_pid_file")
  if kill -0 "$child_pid" 2>/dev/null; then
    kill -KILL "$child_pid" 2>/dev/null || true
    fail "spar-codex left a reviewer descendant holding stderr"
  fi
fi
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-stderr-limit"
rc=0
diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-limit PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review diagnostics." 2>&1) || rc=$?
[[ $rc == 3 && $diagnostic == *'rate limit reached; resets at 12:34 UTC'* ]] ||
  fail "spar-codex did not classify a stderr-only usage limit"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-stderr-sensitive"
diagnostic_secret=$(printf '%s%s' 'sk' '-0123456789abcdef0123456789abcdef')
rc=0
diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-sensitive \
  SPAR_TEST_SECRET=$diagnostic_secret PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review diagnostics." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'stderr withheld by content gate'* ]] ||
  fail "spar-codex did not withhold sensitive reviewer stderr"
[[ $diagnostic != *"$diagnostic_secret"* ]] || fail "spar-codex relayed sensitive reviewer stderr"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-stderr-oversized"
rc=0
diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-oversized PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review diagnostics." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'stderr exceeds 8192-byte relay bound'* ]] ||
  fail "spar-codex did not bound oversized reviewer stderr"
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
  'forced_login_method="chatgpt"' 'model_provider="openai"' 'model="gpt-5.6-sol"' \
  'model_reasoning_effort="xhigh"' 'web_search="disabled"' 'network={enabled=false}' \
  'features.plugins=false' 'features.remote_plugin=false' 'service_tier="fast"' \
  'features.fast_mode=true'; do
  [[ $new_flags == *"$flag"* && $resume_flags == *"$flag"* ]] || fail "Codex new/resume isolation parity missing: $flag"
done
[[ $new_flags != *' -s read-only '* && $resume_flags != *'sandbox_mode'* ]] ||
  fail "legacy Codex sandbox override remains"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/claude-flags"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review flags." >/dev/null 2>/dev/null
new_flags=$(<"$calls")
rm -f "$calls"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  resume 11111111-1111-4111-8111-111111111111 "$handoff" "Review flags." >/dev/null 2>/dev/null
resume_flags=$(<"$calls")
[[ $new_flags == *'--effort xhigh'* && $resume_flags == *'--effort xhigh'* ]] ||
  fail "Claude new/resume xhigh effort pin missing"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/claude-env"
claude_auth_name=$(printf '%s%s' 'ANTHROPIC_AUTH_' 'TOKEN')
if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" "$claude_auth_name=sentinel" \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review auth." >/dev/null 2>/dev/null; then
  fail "Claude bridge accepted alternate auth environment"
fi
[[ ! -s $calls ]] || fail "Claude reviewer was invoked after alternate auth rejection"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-env"
codex_key_name=$(printf '%s%s' 'CODEX_' 'API_KEY')
if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" "$codex_key_name=sentinel" \
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

for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  handoff=$(make_handoff)
  printf 'content\n' >"$handoff/spar-plan.md"
  "$bridge" flush "$handoff" >/dev/null 2>&1 || fail "${bridge##*/} flush rejected a valid handoff"
  rm -rf -- "$handoff"
  if "$bridge" flush "/tmp/spar-$(cat /proc/sys/kernel/random/uuid)" >/dev/null 2>&1; then
    fail "${bridge##*/} flush accepted a legacy /tmp handoff path"
  fi
  if "$bridge" flush "/var/tmp/spar-not-a-uuid" >/dev/null 2>&1; then
    fail "${bridge##*/} flush accepted a malformed handoff name"
  fi
  if "$bridge" flush "/var/tmp/spar-$(cat /proc/sys/kernel/random/uuid)" >/dev/null 2>&1; then
    fail "${bridge##*/} flush accepted a missing handoff directory"
  fi
done

# Reviewer manifest lifecycle: role and state lines at earliest availability.
handoff=$(make_handoff)
calls="$TMP/manifest-claude"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review manifest." >/dev/null 2>/dev/null || fail "spar-claude manifest run failed"
grep -q $'\tprimary\tallocated\t' "$handoff/reviewer-id" || fail "spar-claude manifest missing allocated"
grep -q $'\tprimary\tcompleted\t' "$handoff/reviewer-id" || fail "spar-claude manifest missing completed"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review manifest." cold >/dev/null 2>/dev/null || fail "spar-claude cold-role run failed"
[[ $(grep -c . "$handoff/reviewer-id") == 4 ]] || fail "spar-claude manifest is not append-only"
grep -q $'\tcold\tcompleted\t' "$handoff/reviewer-id" || fail "spar-claude cold role missing"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review manifest." wrongrole >/dev/null 2>/dev/null; then
  fail "spar-claude accepted an invalid reviewer role"
fi
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/manifest-codex"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  new "$handoff" "Review manifest." >/dev/null 2>/dev/null || fail "spar-codex manifest run failed"
grep -q $'\tprimary\tstarted\t' "$handoff/reviewer-id" || fail "spar-codex manifest missing started"
grep -q $'\tprimary\tcompleted\t' "$handoff/reviewer-id" || fail "spar-codex manifest missing completed"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  new "$handoff" "Review manifest." wrongrole >/dev/null 2>/dev/null; then
  fail "spar-codex accepted an invalid reviewer role"
fi
rm -rf -- "$handoff"

# Post-start failure still records the thread id before the failure surfaces.
handoff=$(make_handoff)
calls="$TMP/manifest-codex-failure"
SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=stderr-failure PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review manifest." >/dev/null 2>/dev/null || true
grep -q $'\tprimary\tstarted\t11111111-1111-4111-8111-111111111111' "$handoff/reviewer-id" ||
  fail "spar-codex failure path did not persist the started thread id"
if grep -q $'\tcompleted\t' "$handoff/reviewer-id"; then
  fail "spar-codex failure path recorded a completed state"
fi
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/manifest-claude-failure"
SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=eof PATH="$TMP/bin:$PATH" \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review manifest." >/dev/null 2>/dev/null || true
grep -q $'\tprimary\tallocated\t' "$handoff/reviewer-id" ||
  fail "spar-claude failure path did not persist the allocated session id"
if grep -q $'\tcompleted\t' "$handoff/reviewer-id"; then
  fail "spar-claude failure path recorded a completed state"
fi
rm -rf -- "$handoff"

# Status discovery lists valid handoffs with title and manifest, and reports
# invalid entries individually without using them.
h1=$(make_handoff)
printf '# Task Alpha probe\n' >"$h1/spar-plan.md"
printf '2026-08-17T00:00:00+00:00\tprimary\tcompleted\t11111111-1111-4111-8111-111111111111\n' >"$h1/reviewer-id"
h2=$(make_handoff)
chmod 755 "$h2"
for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  out=$("$bridge" status 2>/dev/null) || fail "${bridge##*/} status failed"
  [[ $out == *"handoff	$h1"* ]] || fail "${bridge##*/} status missed a valid handoff"
  [[ $out == *'# Task Alpha probe'* ]] || fail "${bridge##*/} status missed the task title"
  [[ $out == *'11111111-1111-4111-8111-111111111111'* ]] || fail "${bridge##*/} status missed the manifest"
  [[ $out == *"invalid	$h2"* ]] || fail "${bridge##*/} status did not report the invalid handoff"
done
rm -rf -- "$h1" "$h2"

printf 'ok: spar bridges block sensitive outbound payloads before reviewer invocation\n'
