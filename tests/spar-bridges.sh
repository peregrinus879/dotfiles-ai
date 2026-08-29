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
[[ -z ${SPAR_TEST_PWDS:-} ]] || printf '%s\n' "$PWD" >>"$SPAR_TEST_PWDS"
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
case ${SPAR_TEST_MODE:-ok} in
  ok) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}}}' ;;
  eof) : ;;
  duplicate)
    printf '%s\n' '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}}}'
    printf '%s\n' '{"type":"result","is_error":false,"result":"review twice","modelUsage":{"claude-opus-5":{}}}' ;;
  empty) printf '%s\n' '{"type":"result","is_error":false,"result":"","modelUsage":{"claude-opus-5":{}}}' ;;
  failure) printf '%s\n' '{"type":"result","is_error":true,"result":"review failed"}' ;;
  limit) printf '%s\n' '{"type":"result","is_error":true,"result":"usage limit reached"}' ;;
  missing-model) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok"}' ;;
  wrong-model) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-sonnet-5":{}}}' ;;
  mixed-model) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{},"claude-sonnet-5":{}}}' ;;
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
if [[ ${1:-} == exec ]]; then
  seen_resume=0
  skip_repo_check=0
  for arg in "$@"; do
    [[ $arg == --skip-git-repo-check ]] && skip_repo_check=1
    if [[ $seen_resume == 1 && ($arg == -C || $arg == --cd) ]]; then
      printf 'top-level option appears after resume: %s\n' "$arg" >&2
      exit 90
    fi
    [[ $arg == resume ]] && seen_resume=1
  done
  [[ $skip_repo_check == 1 ]] || { printf 'missing --skip-git-repo-check\n' >&2; exit 90; }
fi
[[ -z ${SPAR_TEST_PWDS:-} ]] || printf '%s\n' "$PWD" >>"$SPAR_TEST_PWDS"
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

hook_decision() { # target
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}\n' "$1" |
    "$ROOT/claude-code/.claude/hooks/spar-handoff-approve.sh" |
    jq -r '.hookSpecificOutput.permissionDecision'
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

[[ $(hook_decision "$ROOT/README.md") == defer ]] || fail "Claude hook did not defer an ordinary edit"
handoff=$(make_handoff)
[[ $(hook_decision "$handoff/spar-plan.md") == allow ]] || fail "Claude hook rejected a valid handoff write"
[[ $(hook_decision "$handoff/.env") == deny ]] || fail "Claude hook did not deny a sensitive handoff write"
[[ $(hook_decision "$handoff/reviewer-id") == deny ]] || fail "Claude hook did not reserve the reviewer manifest"
[[ $(hook_decision "$handoff/AGENTS.md") == deny ]] || fail "Claude hook allowed reviewer-instruction injection"
[[ $(hook_decision "$handoff/CLAUDE.md") == deny ]] || fail "Claude hook allowed Claude-instruction injection"
[[ $(hook_decision "$handoff/.netrc.bak") == deny ]] || fail "Claude hook allowed a sensitive backup filename"
ln -s -- "$handoff" "$TMP/handoff-alias"
[[ $(hook_decision "$TMP/handoff-alias/spar-plan.md") == allow ]] || fail "Claude hook rejected a safe handoff alias"
[[ $(hook_decision "$TMP/handoff-alias/reviewer-id") == deny ]] || fail "Claude hook allowed an alias to the reviewer manifest"
sibling_handoff=$(make_handoff)
[[ $(hook_decision "$TMP/handoff-alias/../${sibling_handoff##*/}/reviewer-id") == deny ]] ||
  fail "Claude hook allowed alias-plus-parent traversal to a reviewer manifest"
rm -rf -- "$sibling_handoff"
rm -- "$TMP/handoff-alias"
ln -s -- "$handoff/reviewer-id" "$TMP/manifest-alias"
[[ $(hook_decision "$TMP/manifest-alias") == deny ]] || fail "Claude hook allowed a direct alias to the reviewer manifest"
rm -- "$TMP/manifest-alias"
ln -s -- "$handoff" "$TMP/handoff-chain"
ln -s -- /var/tmp "$handoff/out"
[[ $(hook_decision "$TMP/handoff-chain/out/escape.md") == deny ]] || fail "Claude hook allowed an alias entering and escaping the handoff"
rm -- "$handoff/out" "$TMP/handoff-chain"
ln -s -- /var/tmp "$handoff/sub"
[[ $(hook_decision "$handoff/sub/escape.md") == deny ]] || fail "Claude hook allowed an alias escaping the handoff"
rm -- "$handoff/sub"
chmod 755 "$handoff"
[[ $(hook_decision "$handoff/spar-plan.md") == deny ]] || fail "Claude hook did not deny unsafe handoff metadata"
rm -rf -- "$handoff"

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

  run_bridge "$bridge" "Review the handoff." $'diff --git i/.env.production w/.env.production\n--- i/.env.production\n+++ w/.env.production\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "mnemonic-prefix sensitive diff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'diff --git .env.production .env.production\n--- .env.production\n+++ .env.production\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "no-prefix sensitive diff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'--- \'a/.env.production\'\n+++ \'b/.env.production\'\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "quoted sensitive diff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'diff --git a/config.txt b/config.txt\n--- a/config.txt\n+++ b/config.txt\n@@ -1 +1 @@\n+PASSWORD=actual-secret-value\n'
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 ]] || fail "credential assignment in a diff reached ${bridge##*/}"

  run_bridge "$bridge" "Review the handoff." $'Read(~/.codex/auth.json) = deny\n.env.* = deny\n**/*.key = deny\n'
  [[ $BRIDGE_RC == 0 && $BRIDGE_CALLED == 1 ]] || fail "policy text was falsely rejected by ${bridge##*/}"
done

handoff=$(make_handoff)
printf '2026-08-17T00:00:00+00:00\tcodex\tprimary\tcompleted\t11111111-1111-4111-8111-111111111111\n' >"$handoff/reviewer-id"
calls="$TMP/cross-bridge-resume"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  resume 11111111-1111-4111-8111-111111111111 "$handoff" "Review wrong bridge." \
  >/dev/null 2>/dev/null; then
  fail "spar-claude resumed a Codex reviewer session"
fi
[[ ! -s $calls ]] || fail "spar-claude invoked a cross-bridge reviewer session"
rm -rf -- "$handoff"

legacy_sid=33333333-3333-4333-8333-333333333333
handoff=$(make_handoff)
printf '2026-08-17T00:00:00+00:00\tprimary\tallocated\t%s\n' "$legacy_sid" >"$handoff/reviewer-id"
calls="$TMP/legacy-claude-resume"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  resume "$legacy_sid" "$handoff" "Resume legacy Claude session." >/dev/null 2>/dev/null ||
  fail "spar-claude rejected its bridge-specific legacy manifest"
wrong_calls="$TMP/legacy-claude-via-codex"
if SPAR_TEST_CALLS=$wrong_calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  resume "$legacy_sid" "$handoff" "Resume wrong legacy bridge." >/dev/null 2>/dev/null; then
  fail "spar-codex accepted a legacy Claude manifest"
fi
[[ ! -s $wrong_calls ]] || fail "spar-codex invoked a legacy Claude session"
rm -rf -- "$handoff"

handoff=$(make_handoff)
printf '2026-08-17T00:00:00+00:00\tprimary\tstarted\t%s\n' "$legacy_sid" >"$handoff/reviewer-id"
calls="$TMP/legacy-codex-resume"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  resume "$legacy_sid" "$handoff" "Resume legacy Codex session." >/dev/null 2>/dev/null ||
  fail "spar-codex rejected its bridge-specific legacy manifest"
wrong_calls="$TMP/legacy-codex-via-claude"
if SPAR_TEST_CALLS=$wrong_calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  resume "$legacy_sid" "$handoff" "Resume wrong legacy bridge." >/dev/null 2>/dev/null; then
  fail "spar-claude accepted a legacy Codex manifest"
fi
[[ ! -s $wrong_calls ]] || fail "spar-claude invoked a legacy Codex session"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/codex-plugin-leak"
if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=plugin-leak PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review plugin isolation." \
  >/dev/null 2>/dev/null; then
  fail "spar-codex accepted plugins after applying its disable override"
fi
[[ ! -s $calls ]] || fail "Codex reviewer was invoked after plugin isolation failed"
rm -rf -- "$handoff"

for mode in eof duplicate empty failure; do
  handoff=$(make_handoff)
  calls="$TMP/terminal-spar-codex-$mode"
  if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
    "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review terminal events." \
    >/dev/null 2>/dev/null; then
    fail "spar-codex accepted terminal mode $mode"
  fi
  rm -rf -- "$handoff"
done

run_claude_diag() { # mode, expected rc, expected diagnostic, failure message
  local mode=$1 expected_rc=$2 expected=$3 message=$4 handoff rc=0 diagnostic
  handoff=$(make_handoff)
  diagnostic=$(SPAR_TEST_CALLS="$TMP/claude-$mode" SPAR_TEST_MODE="$mode" \
    PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
    new "$handoff" "Review terminal events." 2>&1 >/dev/null) || rc=$?
  [[ $rc == "$expected_rc" && $diagnostic == *"$expected"* ]] || fail "$message"
  rm -rf -- "$handoff"
}

run_claude_diag eof 5 'reviewer ended without one successful result' \
  "spar-claude did not reject a missing terminal result"
run_claude_diag duplicate 5 'duplicate result event' \
  "spar-claude did not reject duplicate terminal results"
run_claude_diag empty 5 'successful result has no reply' \
  "spar-claude did not reject an empty reply"
run_claude_diag failure 5 'review failed' \
  "spar-claude did not relay a reviewer error"
run_claude_diag limit 3 'usage limit reached' \
  "spar-claude did not classify a reviewer usage limit"
run_claude_diag missing-model 5 'reviewer served model keys [<missing>]' \
  "spar-claude did not reject missing model usage"
run_claude_diag wrong-model 5 'reviewer served model keys [claude-sonnet-5]' \
  "spar-claude did not reject a non-Opus reviewer"
run_claude_diag mixed-model 5 'reviewer served model keys [claude-opus-5,claude-sonnet-5]' \
  "spar-claude did not reject mixed reviewer models"

handoff=$(make_handoff)
calls="$TMP/codex-malformed"
if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=malformed PATH="$TMP/bin:$PATH" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review terminal events." >/dev/null 2>/dev/null; then
  fail "spar-codex accepted malformed thread id"
fi
rm -rf -- "$handoff"

# run_codex_diag <mode> <expected-rc> <expected-substring> <fail-message>
# [extra VAR=value env words]. Runs the shared stderr-diagnostic scenario and
# exports $diagnostic for follow-up assertions.
run_codex_diag() {
  local mode=$1 expected_rc=$2 expected_substring=$3 message=$4 handoff rc=0
  shift 4
  handoff=$(make_handoff)
  diagnostic=$(env SPAR_TEST_CALLS="$TMP/codex-$mode" SPAR_TEST_MODE="$mode" \
    PATH="$TMP/bin:$PATH" "$@" \
    "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review diagnostics." 2>&1) || rc=$?
  [[ $rc == "$expected_rc" && $diagnostic == *"$expected_substring"* ]] || fail "$message"
  rm -rf -- "$handoff"
}

run_codex_diag stderr-failure 5 'transport handshake failed' \
  "spar-codex did not relay safe reviewer stderr"
[[ $diagnostic == *'SPAR-BRIDGE THREAD: reviewer thread started before failure: 11111111-1111-4111-8111-111111111111'* ]] ||
  fail "spar-codex did not preserve a failed-new thread id"

run_codex_diag stderr-empty 5 'reviewer exited 1 without stderr' \
  "spar-codex did not classify an empty reviewer stderr failure"

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

run_codex_diag stderr-limit 3 'rate limit reached; resets at 12:34 UTC' \
  "spar-codex did not classify a stderr-only usage limit"

diagnostic_secret=$(printf '%s%s' 'sk' '-0123456789abcdef0123456789abcdef')
run_codex_diag stderr-sensitive 5 'stderr withheld by content gate' \
  "spar-codex did not withhold sensitive reviewer stderr" \
  SPAR_TEST_SECRET="$diagnostic_secret"
[[ $diagnostic != *"$diagnostic_secret"* ]] || fail "spar-codex relayed sensitive reviewer stderr"

run_codex_diag stderr-oversized 5 'stderr exceeds 8192-byte relay bound' \
  "spar-codex did not bound oversized reviewer stderr"

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
pwds="$TMP/codex-pwds"
SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  new "$handoff" "Review flags." >/dev/null 2>/dev/null
new_flags=$(<"$calls")
rm -f "$calls"
SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  resume 11111111-1111-4111-8111-111111111111 "$handoff" "Review flags." >/dev/null 2>/dev/null
resume_flags=$(<"$calls")
codex_runtime=$(realpath -e -- "$TMP/bin/codex")
for flag in --ignore-user-config --ignore-rules --strict-config --skip-git-repo-check --json 'default_permissions="spar-reviewer"' \
  'forced_login_method="chatgpt"' 'model_provider="openai"' 'model="gpt-5.6-sol"' \
  'model_reasoning_effort="max"' 'model_reasoning_summary="none"' \
  'web_search="disabled"' 'network={enabled=false}' \
  'features.plugins=false' 'features.remote_plugin=false' 'features.skill_search=false' \
  'skills.include_instructions=false' 'project_root_markers=[]' 'notify=[]' \
  'check_for_update_on_startup=false' 'analytics.enabled=false' 'feedback.enabled=false' \
  'service_tier="fast"' 'features.fast_mode=true'; do
  [[ $new_flags == *"$flag"* && $resume_flags == *"$flag"* ]] || fail "Codex new/resume isolation parity missing: $flag"
done
for flags in "$new_flags" "$resume_flags"; do
  [[ $flags == *'-C '"$handoff"* && $flags == *'filesystem={":root"="deny",":minimal"="read",":tmpdir"="deny",":slash_tmp"="deny"'* && \
    $flags == *'"'"$codex_runtime"'"="read"'* && $flags == *'"'"$handoff"'"="read"'* ]] ||
    fail "Codex reviewer lacks its runtime or handoff read grant: $flags"
  [[ $flags == *'projects={"'"$handoff"'"={trust_level="untrusted"}}'* ]] ||
    fail "Codex reviewer handoff trust isolation missing"
  [[ $flags != *'extends=":read-only"'* && $flags != *'":workspace_roots"'* ]] ||
    fail "Codex reviewer retained inherited repository reads"
done
[[ $(wc -l <"$pwds") == 2 && $(sort -u "$pwds") == "$handoff" ]] ||
  fail "Codex new/resume did not launch from the handoff"
[[ $new_flags != *' -s read-only '* && $resume_flags != *'sandbox_mode'* ]] ||
  fail "legacy Codex sandbox override remains"
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/claude-flags"
pwds="$TMP/claude-pwds"
SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review flags." >/dev/null 2>/dev/null
new_flags=$(<"$calls")
claude_sid=$(awk -F '\t' '$4 == "allocated" { print $5; exit }' "$handoff/reviewer-id")
rm -f "$calls"
SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  resume "$claude_sid" "$handoff" "Review flags." >/dev/null 2>/dev/null
resume_flags=$(<"$calls")
[[ $new_flags == *'--effort max'* && $resume_flags == *'--effort max'* ]] ||
  fail "Claude new/resume maximum effort pin missing"
[[ $new_flags == *'--tools Read,Glob,Grep'* && $resume_flags == *'--tools Read,Glob,Grep'* ]] ||
  fail "Claude new/resume read-only tool whitelist missing"
[[ $new_flags == *'--model opus'* && $resume_flags == *'--model opus'* ]] ||
  fail "Claude new/resume latest-Opus alias missing"
[[ $new_flags == *'--permission-mode dontAsk'* && $resume_flags == *'--permission-mode dontAsk'* ]] ||
  fail "Claude new/resume fail-closed permission mode missing"
[[ $new_flags == *'--setting-sources='* && $resume_flags == *'--setting-sources='* ]] ||
  fail "Claude new/resume setting-source isolation missing"
read_rule="Read(/$handoff/**)"
[[ $new_flags == *'--allowedTools '"$read_rule"* && $resume_flags == *'--allowedTools '"$read_rule"* ]] ||
  fail "Claude new/resume handoff-only Read allow missing"
[[ $new_flags != *'--permission-mode plan'* && $resume_flags != *'--setting-sources user'* ]] ||
  fail "Claude reviewer retained ambient read permissions"
reviewer_settings='--settings {"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":""}}'
[[ $new_flags == *"$reviewer_settings"* && $resume_flags == *"$reviewer_settings"* ]] ||
  fail "Claude new/resume alias-clear settings missing"
[[ $(wc -l <"$pwds") == 2 && $(sort -u "$pwds") == "$handoff" ]] ||
  fail "Claude new/resume did not launch from the handoff"
rm -rf -- "$handoff"

for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  handoff=$(make_handoff)
  calls="$TMP/unbound-${bridge##*/}"
  if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$bridge" \
    resume 22222222-2222-4222-8222-222222222222 "$handoff" "Review unbound resume." \
    >/dev/null 2>/dev/null; then
    fail "${bridge##*/} resumed a session not recorded in its handoff"
  fi
  [[ ! -s $calls ]] || fail "${bridge##*/} invoked a reviewer for an unbound session"
  rm -rf -- "$handoff"
done

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
calls="$TMP/claude-model-env"
if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" \
  ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-8 \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review model." \
  >/dev/null 2>/dev/null; then
  fail "Claude bridge accepted an Opus alias override"
fi
[[ ! -s $calls ]] || fail "Claude reviewer was invoked after alias-override rejection"
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
calls="$TMP/codex-sqlite-env"
if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" CODEX_SQLITE_HOME="$ROOT" \
  "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review state isolation." \
  >/dev/null 2>/dev/null; then
  fail "Codex bridge accepted a caller-directed SQLite state path"
fi
[[ ! -s $calls ]] || fail "Codex reviewer was invoked after SQLite state-path rejection"
rm -rf -- "$handoff"

for variable in CODEX_HOME CODEX_ACCESS_TOKEN OPENAI_BASE_URL HTTPS_PROXY; do
  handoff=$(make_handoff)
  calls="$TMP/codex-override-$variable"
  if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" "$variable=sentinel" \
    "$ROOT/codex/.local/bin/spar-codex" new "$handoff" "Review environment isolation." \
    >/dev/null 2>/dev/null; then
    fail "Codex bridge accepted $variable"
  fi
  [[ ! -s $calls ]] || fail "Codex reviewer was invoked after $variable rejection"
  rm -rf -- "$handoff"
done

for variable in HTTPS_PROXY ANTHROPIC_BETAS ANTHROPIC_CUSTOM_HEADERS \
  NODE_TLS_REJECT_UNAUTHORIZED CLAUDE_CODE_CERT_STORE \
  CLAUDE_CODE_CLIENT_CERT CLAUDE_CODE_CLIENT_KEY CLAUDE_CODE_CLIENT_KEY_PASSPHRASE \
  CLAUDE_CODE_DISABLE_MTLS_RELOAD_ON_STALE_CONNECTION; do
  handoff=$(make_handoff)
  calls="$TMP/claude-routing-$variable"
  if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" "$variable=sentinel" \
    "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review routing isolation." \
    >/dev/null 2>/dev/null; then
    fail "Claude bridge accepted $variable"
  fi
  [[ ! -s $calls ]] || fail "Claude reviewer was invoked after $variable rejection"
  rm -rf -- "$handoff"
done

printf 'printf sourced >"$%s"\n' 'SPAR_TEST_BASH_ENV_HIT' >"$TMP/hostile-bash-env"
for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  handoff=$(make_handoff)
  calls="$TMP/bash-env-calls-${bridge##*/}"
  hit="$TMP/bash-env-hit-${bridge##*/}"
  BASH_ENV="$TMP/hostile-bash-env" SPAR_TEST_BASH_ENV_HIT=$hit SPAR_TEST_CALLS=$calls \
    PATH="$TMP/bin:$PATH" "$bridge" new "$handoff" "Review startup isolation." \
    >/dev/null 2>/dev/null || fail "${bridge##*/} failed under a hostile BASH_ENV"
  [[ ! -e $hit ]] || fail "${bridge##*/} executed caller-supplied Bash startup code"
  rm -rf -- "$handoff"
done

for bridge_name in claude codex; do
  handoff=$(make_handoff)
  calls="$TMP/cwd-substitution-$bridge_name"
  printf '#!/bin/sh\nexit 99\n' >"$handoff/$bridge_name"
  chmod 755 "$handoff/$bridge_name"
  SPAR_TEST_CALLS=$calls PATH=".:$TMP/bin:$PATH" \
    "$ROOT/${bridge_name/claude/claude-code}/.local/bin/spar-$bridge_name" \
    new "$handoff" "Review executable pinning." >/dev/null 2>/dev/null ||
    fail "spar-$bridge_name selected a reviewer executable after changing cwd"
  rm -rf -- "$handoff"
done

handoff=$(make_handoff)
printf 'binary\0content' >"$handoff/payload.bin"
if printf 'Review.' | "$ROOT/claude-code/.local/bin/spar-payload-scan" "$handoff" >/dev/null 2>&1; then
  fail "binary handoff passed scanner"
fi
rm -rf -- "$handoff"

for name in .env .netrc private.pem.bak AGENTS.md CLAUDE.md; do
  handoff=$(make_handoff)
  printf 'harmless\n' >"$handoff/$name"
  if printf 'Review.' | "$ROOT/claude-code/.local/bin/spar-payload-scan" "$handoff" >/dev/null 2>&1; then
    fail "sensitive or reviewer-instruction handoff filename passed scanner: $name"
  fi
  rm -rf -- "$handoff"
done

for content in \
  'PASSWORD=actual-example-secret-value' \
  'PASSWORD="my actual secret passphrase"' \
  "PASSWORD=\"\"'my actual secret passphrase'" \
  'PASSWORD=example#actual-secret' \
  'PASSWORD=#actual-secret' \
  'GITHUB_TOKEN=github_pat_0123456789abcdef0123456789abcdef' \
  '//registry.npmjs.org/:_authToken=0123456789abcdef' \
  $'diff --git a/config.txt b/config.txt\n+//registry.npmjs.org/:_authToken=0123456789abcdef' \
  $'diff --git a/config.txt b/config.txt\n+machine example.com\n+password actual-secret' \
  $'machine example.com\nlogin user\npassword actual-secret'; do
  handoff=$(make_handoff)
  printf '%s\n' "$content" >"$handoff/payload.md"
  if printf 'Review.' | "$ROOT/claude-code/.local/bin/spar-payload-scan" "$handoff" >/dev/null 2>&1; then
    fail "credential-shaped handoff content passed scanner"
  fi
  rm -rf -- "$handoff"
done

handoff=$(make_handoff)
printf 'PASSWORD="example value"\nPASSWORD=""\n' >"$handoff/payload.md"
printf 'Review.' | "$ROOT/claude-code/.local/bin/spar-payload-scan" "$handoff" >/dev/null 2>&1 ||
  fail "placeholder credential was falsely rejected"
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
grep -q $'\tclaude\tprimary\tallocated\t' "$handoff/reviewer-id" || fail "spar-claude manifest missing allocated"
grep -q $'\tclaude\tprimary\tcompleted\t' "$handoff/reviewer-id" || fail "spar-claude manifest missing completed"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review manifest." cold >/dev/null 2>/dev/null || fail "spar-claude cold-role run failed"
[[ $(grep -c . "$handoff/reviewer-id") == 4 ]] || fail "spar-claude manifest is not append-only"
grep -q $'\tclaude\tcold\tcompleted\t' "$handoff/reviewer-id" || fail "spar-claude cold role missing"
cold_sid=$(awk -F '\t' '$3 == "cold" && $4 == "allocated" { print $5; exit }' "$handoff/reviewer-id")
rm -f "$calls"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  resume "$cold_sid" "$handoff" "Improper cold resume." >/dev/null 2>/dev/null; then
  fail "spar-claude resumed a cold reviewer"
fi
[[ ! -s $calls ]] || fail "spar-claude invoked a cold reviewer resume"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/claude-code/.local/bin/spar-claude" \
  new "$handoff" "Review manifest." wrongrole >/dev/null 2>/dev/null; then
  fail "spar-claude accepted an invalid reviewer role"
fi
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/manifest-codex"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$ROOT/codex/.local/bin/spar-codex" \
  new "$handoff" "Review manifest." >/dev/null 2>/dev/null || fail "spar-codex manifest run failed"
grep -q $'\tcodex\tprimary\tstarted\t' "$handoff/reviewer-id" || fail "spar-codex manifest missing started"
grep -q $'\tcodex\tprimary\tcompleted\t' "$handoff/reviewer-id" || fail "spar-codex manifest missing completed"
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
grep -q $'\tcodex\tprimary\tstarted\t11111111-1111-4111-8111-111111111111' "$handoff/reviewer-id" ||
  fail "spar-codex failure path did not persist the started thread id"
if grep -q $'\tcompleted\t' "$handoff/reviewer-id"; then
  fail "spar-codex failure path recorded a completed state"
fi
rm -rf -- "$handoff"

handoff=$(make_handoff)
calls="$TMP/manifest-claude-failure"
SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=eof PATH="$TMP/bin:$PATH" \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review manifest." >/dev/null 2>/dev/null || true
grep -q $'\tclaude\tprimary\tallocated\t' "$handoff/reviewer-id" ||
  fail "spar-claude failure path did not persist the allocated session id"
if grep -q $'\tcompleted\t' "$handoff/reviewer-id"; then
  fail "spar-claude failure path recorded a completed state"
fi
rm -rf -- "$handoff"

# Status discovery lists valid handoffs with title and manifest, and reports
# invalid entries individually without using them.
h1=$(make_handoff)
printf '# Task Alpha probe\n' >"$h1/spar-plan.md"
printf '2026-08-17T00:00:00+00:00\tclaude\tprimary\tcompleted\t11111111-1111-4111-8111-111111111111\n' >"$h1/reviewer-id"
h2=$(make_handoff)
chmod 755 "$h2"
h3=$(make_handoff)
printf '# Brainstorm Gamma probe\n' >"$h3/spar-brainstorm.md"
for bridge in "$ROOT/claude-code/.local/bin/spar-claude" "$ROOT/codex/.local/bin/spar-codex"; do
  out=$("$bridge" status 2>/dev/null) || fail "${bridge##*/} status failed"
  [[ $out == *"handoff	$h1"* ]] || fail "${bridge##*/} status missed a valid handoff"
  [[ $out == *'# Task Alpha probe'* ]] || fail "${bridge##*/} status missed the task title"
  [[ $out == *'11111111-1111-4111-8111-111111111111'* ]] || fail "${bridge##*/} status missed the manifest"
  [[ $out == *"handoff	$h3"* ]] || fail "${bridge##*/} status missed a brainstorm handoff"
  [[ $out == *'# Brainstorm Gamma probe'* ]] || fail "${bridge##*/} status missed the brainstorm title"
  [[ $out == *"invalid	$h2"* ]] || fail "${bridge##*/} status did not report the invalid handoff"
done
rm -rf -- "$h1" "$h2" "$h3"

# Failure contracts: a failing mkfifo aborts exit 2 with the private workdir
# cleaned (the trap is installed before mkfifo), and a failing uuid read in
# new surfaces the bridge's abort message, not cat's raw status.
mkdir -p "$TMP/failbin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/failbin/mkfifo"
chmod 755 "$TMP/failbin/mkfifo"
handoff=$(make_handoff)
workdirs="$TMP/leak-observe"
mkdir -p "$workdirs"
rc=0
TMPDIR=$workdirs SPAR_TEST_CALLS="$TMP/failcalls" PATH="$TMP/failbin:$TMP/bin:$PATH" \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review failure." >/dev/null 2>&1 || rc=$?
[[ $rc == 2 ]] || fail "spar-claude mkfifo failure did not abort with exit 2"
[[ -z $(ls -A "$workdirs") ]] || fail "spar-claude leaked its private workdir on mkfifo failure"
rm -f "$TMP/failbin/mkfifo"
rm -rf -- "$handoff"

printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/failbin/cat"
chmod 755 "$TMP/failbin/cat"
handoff=$(make_handoff)
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/failcalls" PATH="$TMP/failbin:$TMP/bin:$PATH" \
  "$ROOT/claude-code/.local/bin/spar-claude" new "$handoff" "Review failure." 2>&1) || rc=$?
[[ $rc == 2 && $diagnostic == *'cannot generate a reviewer session id'* ]] ||
  fail "spar-claude uuid failure did not surface the bridge abort"
rm -f "$TMP/failbin/cat"
rm -rf -- "$handoff"

printf 'ok: spar bridges block sensitive outbound payloads before reviewer invocation\n'
