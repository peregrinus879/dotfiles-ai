#!/usr/bin/env bash
# Behavioral checks for the spar reviewer bridges and payload scanner. Reviewer
# CLIs are shimmed; fixtures that must look like credentials are assembled at
# runtime so the repository itself stays scannable.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLAUDE_BRIDGE="$ROOT/claude-code/.local/bin/spar-claude"
CODEX_BRIDGE="$ROOT/codex/.local/bin/spar-codex"
SCANNER="$ROOT/claude-code/.local/bin/spar-payload-scan"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/art"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat >"$TMP/bin/claude" <<'SHIM'
#!/usr/bin/env bash
[[ -z ${CLAUDE_CODE_EFFORT_LEVEL:-} ]] || exit 89
if [[ " $* " == *' auth status '* ]]; then
  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}'
  exit
fi
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
printf '%s\n' "$PWD" >>"$SPAR_TEST_CALLS.pwd"
cat >"$SPAR_TEST_CALLS.stdin"
session="33333333-3333-4333-8333-333333333333"
case ${SPAR_TEST_MODE:-ok} in
  ok) jq -cn --arg s "$session" '{type:"result",is_error:false,result:"review ok",session_id:$s}' ;;
  reply) jq -cn --arg s "$session" --arg t "$SPAR_TEST_REPLY" '{type:"result",is_error:false,result:$t,session_id:$s}' ;;
  failure) printf 'reviewer failed while reading .env policy\n' >&2; exit 1 ;;
  error-result) jq -cn '{type:"result",is_error:true,result:"review failed"}' ;;
  limit) jq -cn '{type:"result",is_error:true,result:"usage limit reached"}' ;;
  hang)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do sleep 1; done ;;
esac
SHIM

cat >"$TMP/bin/codex" <<'SHIM'
#!/usr/bin/env bash
if [[ ${1:-} == login && ${2:-} == status ]]; then
  printf 'Logged in using ChatGPT\n'
  exit
fi
[[ ${1:-} == exec ]] || exit 90
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
printf '%s\n' "$PWD" >>"$SPAR_TEST_CALLS.pwd"
cat >"$SPAR_TEST_CALLS.stdin"
thread="11111111-1111-4111-8111-111111111111"
case ${SPAR_TEST_MODE:-ok} in
  ok)
    jq -cn --arg t "$thread" '{type:"thread.started",thread_id:$t}'
    jq -cn '{type:"item.completed",item:{type:"agent_message",text:"review ok"}}'
    jq -cn '{type:"turn.completed"}' ;;
  reply)
    jq -cn --arg t "$thread" '{type:"thread.started",thread_id:$t}'
    jq -cn --arg t "$SPAR_TEST_REPLY" '{type:"item.completed",item:{type:"agent_message",text:$t}}'
    jq -cn '{type:"turn.completed"}' ;;
  failure) printf 'reviewer failed while reading .env policy\n' >&2; exit 1 ;;
  error-result)
    jq -cn --arg t "$thread" '{type:"thread.started",thread_id:$t}'
    jq -cn '{type:"turn.failed",error:"review failed"}' ;;
  limit) printf 'rate limit reached; resets later\n' >&2; exit 1 ;;
  hang)
    trap '' TERM
    (trap '' TERM; while :; do sleep 1; done) &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    while :; do sleep 1; done ;;
esac
SHIM
chmod 755 "$TMP/bin/claude" "$TMP/bin/codex"

# Credential-shaped fixtures are assembled here so no literal exists on disk.
token=$(printf '%s%s' 'sk-' 'UNKNOWNFIXTURE0123456789ABCDEF')
key_name=$(printf '%s_%s' 'OPENAI_API' 'KEY')
envelope=$(printf '%s %s' '-----BEGIN TEST PRIVATE' 'KEY-----')
github_token=$(printf '%s%s' 'ghp_' 'PUBLICFIXTURE0123456789AB')

# --- Scanner ---
printf 'Review ordinary material.' | "$SCANNER" outbound >"$TMP/out" || fail "scanner rejected a safe request"
[[ $(<"$TMP/out") == 'Review ordinary material.' ]] || fail "scanner did not preserve a safe request"

printf 'plan body\n' >"$TMP/art/spar-plan.md"
printf 'Review.' | "$SCANNER" outbound "$TMP/art/spar-plan.md" >"$TMP/out" || fail "scanner rejected a safe artifact"
[[ $(<"$TMP/out") == *'===== artifact: spar-plan.md ====='*'plan body'*'===== end artifact: spar-plan.md ====='* ]] ||
  fail "scanner did not inline the artifact with delimiters"

if printf '' | "$SCANNER" outbound >/dev/null 2>&1; then fail "empty request passed scanner"; fi
printf 'binary\0content' >"$TMP/art/payload.bin"
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/payload.bin" >/dev/null 2>&1; then fail "binary artifact passed scanner"; fi
printf '\377' >"$TMP/art/latin.md"
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/latin.md" >/dev/null 2>&1; then fail "non-UTF-8 artifact passed scanner"; fi
ln -s -- "$TMP/art/spar-plan.md" "$TMP/art/linked.md"
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/linked.md" >/dev/null 2>&1; then fail "symlinked artifact passed scanner"; fi
printf 'harmless\n' >"$TMP/art/.env"
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/.env" >/dev/null 2>&1; then fail "sensitive artifact name passed scanner"; fi
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/missing.md" >/dev/null 2>&1; then fail "missing artifact passed scanner"; fi
python3 -c 'import sys; sys.stdout.write("x" * (512 * 1024 + 1))' >"$TMP/art/oversized.md"
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/oversized.md" >/dev/null 2>&1; then fail "oversized artifact passed scanner"; fi
for index in 1 2 3; do python3 -c 'import sys; sys.stdout.write("x" * 400000)' >"$TMP/art/big$index.md"; done
if printf 'Review.' | "$SCANNER" outbound "$TMP/art/big1.md" "$TMP/art/big2.md" "$TMP/art/big3.md" >/dev/null 2>&1; then
  fail "oversized aggregate payload passed scanner"
fi
if python3 -c 'import sys; sys.stdout.write("x" * (256 * 1024 + 1))' | "$SCANNER" outbound >/dev/null 2>&1; then
  fail "oversized request passed scanner"
fi

printf '%s=%s\n' "$key_name" "$token" >"$TMP/art/leak.md"
rc=0
diagnostic=$(printf 'Review.' | "$SCANNER" outbound "$TMP/art/leak.md" 2>&1 >/dev/null) || rc=$?
[[ $rc == 2 && $diagnostic != *"$token"* ]] || fail "credential assignment passed scanner or leaked into diagnostics"
for content in "$envelope" "$github_token" "$(printf 'AKIA%s' 'PUBLICFIXTURE123')" \
  "$(printf '//registry.example.invalid/:_%s=%s' 'authToken' 'PUBLICPACKAGEAUTH123')" \
  "$(printf 'machine example.invalid\n%s %s' 'password' 'PUBLICNETRC123')"; do
  printf '%s\n' "$content" >"$TMP/art/vector.md"
  if printf 'Review.' | "$SCANNER" outbound "$TMP/art/vector.md" >/dev/null 2>&1; then
    fail "credential-shaped fixture passed scanner"
  fi
done
printf '%s=placeholder-token\n//registry.example.invalid/:_%s=example-token\n%s=%s\n' \
  "$key_name" 'authToken' 'PASSWORD' "\${PASSWORD}" >"$TMP/art/placeholders.md"
printf 'Review.' | "$SCANNER" outbound "$TMP/art/placeholders.md" >/dev/null 2>&1 ||
  fail "scanner rejected documented placeholder values"
for _ in $(seq 1 10); do printf '%s=%s\n' "$key_name" "$token"; done >"$TMP/art/many.md"
rc=0
diagnostic=$(printf 'Review.' | "$SCANNER" outbound "$TMP/art/many.md" 2>&1 >/dev/null) || rc=$?
[[ $rc == 2 && $(grep -c '^SPAR-PAYLOAD FINDING:' <<<"$diagnostic") == 9 && $diagnostic == *'2 additional findings omitted'* ]] ||
  fail "scanner finding report was not bounded"

sensitive_headers=(
  'diff --git a/.env.production b/.env.production'
  'diff --git a/a/.env-old/config b/a/.env-old/config'
  'diff --git a/private.pem/key.txt b/private.pem/key.txt'
  'diff --git "a/\056env" "b/\056env"'
  'diff --git a/public secrets/x b/public secrets/x'
  'diff --cc secrets/config'
  'diff --combined private.pem'
  '--- a/.netrc'
  '+++ b/auth.json'
  'rename from credentials.old'
  'rename to id_rsa/public.txt'
  'copy to .env_bak'
  'diff --git "a/.env"x" "b/public"'
  'diff --git a/pub\lic b/public'
)
for header in "${sensitive_headers[@]}"; do
  printf '%s\n' "$header" >"$TMP/art/header.md"
  if printf 'Review.' | "$SCANNER" outbound "$TMP/art/header.md" >/dev/null 2>&1; then
    fail "sensitive or malformed diff header passed scanner: $header"
  fi
done
printf '%s\n' 'diff --git "a/public\040file" "b/public\040file"' 'diff --git a/public file b/public file' \
  'diff --git "a/caf\303\251.txt" b/public file.txt' '--- a/public' $'+++ b/public\tcomment' \
  'diff --git a/docs/credentials-policy.md b/docs/credentials-policy.md' 'rename to secretary.md' \
  '+  diff --git a/.env b/.env' >"$TMP/art/safe-headers.md"
printf 'Review.' | "$SCANNER" outbound "$TMP/art/safe-headers.md" >/dev/null 2>&1 ||
  fail "safe diff headers were rejected"

printf 'The .env path is denied.\n' | "$SCANNER" reply >/dev/null || fail "reply scanner rejected sensitive-path prose"
if printf '%s=%s\n' "$key_name" "$token" | "$SCANNER" reply >/dev/null 2>&1; then fail "reply scanner accepted a credential value"; fi

# The repository must stay reviewable by its own scanner.
git -C "$ROOT" diff --binary "$(git -C "$ROOT" hash-object -t tree /dev/null)" -- . |
  "$SCANNER" outbound >/dev/null || fail "the repository's own tracked content fails the outbound scan"

# --- Bridges ---
repo="$TMP/repo"
git init -q "$repo"
printf 'harmless\n' >"$repo/README.md"
run_bridge() { # bridge mode calls-file [bridge args...]
  local bridge=$1 mode=$2 calls=$3
  shift 3
  BRIDGE_RC=0
  rm -f -- "$calls" "$calls.pwd" "$calls.stdin"
  SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
    /usr/bin/env -C "$repo" "$bridge" review "$@" >"$calls.out" 2>"$calls.err" || BRIDGE_RC=$?
}

for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  name=${bridge##*/}
  calls="$TMP/calls-$name"

  git -C "$repo" config spar.consent false
  run_bridge "$bridge" ok "$calls" "Review after opt-out."
  [[ $BRIDGE_RC == 2 && ! -e $calls && $(<"$calls.err") == *'spar.consent'* ]] ||
    fail "$name ran in a repository that opted out"
  git -C "$repo" config --unset spar.consent

  GIT_EDITOR=true run_bridge "$bridge" ok "$calls" "Review ordinary material." "$TMP/art/spar-plan.md"
  [[ $BRIDGE_RC == 0 && $(<"$calls.out") == 'review ok' ]] || fail "$name failed an ordinary review: $(<"$calls.err")"
  [[ $(<"$calls.err") == *'SPAR-BRIDGE ID: '* ]] || fail "$name did not report the reviewer id"
  [[ $(<"$calls.pwd") == "$repo" ]] || fail "$name did not launch from the repository root"
  [[ $(<"$calls.stdin") == *'Review ordinary material.'*'===== artifact: spar-plan.md ====='*'plan body'* ]] ||
    fail "$name did not send the scanned prompt with the inlined artifact on stdin"
  args=$(<"$calls")
  if [[ $name == spar-claude ]]; then
    for flag in '--tools Read,Glob,Grep' '--permission-mode dontAsk' '--safe-mode' '--setting-sources=' \
      '--strict-mcp-config' '--model opus' '--effort xhigh' '--output-format json' \
      "Read(/$repo/**)" "Read(/$repo/.git/**)" 'Read(./**/.env)' 'Read(./**/*.pem)' "Read(/$HOME/.ssh/**)"; do
      [[ $args == *"$flag"* ]] || fail "$name isolation missing: $flag"
    done
  else
    for flag in 'default_permissions="spar-reviewer"' 'approval_policy="never"' 'features.plugins=false' \
      'features.multi_agent=false' 'web_search="disabled"' 'network={enabled=false}' '":root"="deny"' \
      "\"$repo\"=\"read\"" "\"$repo/.git\"=\"deny\"" '"**/.env"="deny"' '"**/*.pem"="deny"' \
      "trust_level=\"untrusted\"" 'project_doc_max_bytes=0' '--ignore-user-config' '--ignore-rules'; do
      [[ $args == *"$flag"* ]] || fail "$name isolation missing: $flag"
    done
  fi
  [[ $args != *'/var/tmp/spar-'* ]] || fail "$name still references a handoff directory"

  resume_id="22222222-2222-4222-8222-222222222222"
  run_bridge "$bridge" ok "$calls" --resume "$resume_id" "Follow up."
  [[ $BRIDGE_RC == 0 && $(<"$calls") == *"$resume_id"* ]] || fail "$name did not resume the requested session"
  run_bridge "$bridge" ok "$calls" --resume not-a-uuid "Follow up."
  [[ $BRIDGE_RC == 64 && ! -e $calls ]] || fail "$name accepted a malformed resume id"

  run_bridge "$bridge" ok "$calls" "$(printf '%s=%s' "$key_name" "$token")"
  [[ $BRIDGE_RC == 2 && ! -e $calls ]] || fail "$name sent a credential-shaped request"
  run_bridge "$bridge" ok "$calls" "Review leak." "$TMP/art/leak.md"
  [[ $BRIDGE_RC == 2 && ! -e $calls && $(<"$calls.err") != *"$token"* ]] || fail "$name sent a credential-shaped artifact"

  SPAR_TEST_REPLY="$(printf '%s=%s' "$key_name" "$token")" run_bridge "$bridge" reply "$calls" "Review reply."
  [[ $BRIDGE_RC == 2 && $(<"$calls.out") != *"$token"* && $(<"$calls.err") != *"$token"* ]] ||
    fail "$name relayed a credential-shaped reply"
  SPAR_TEST_REPLY='The .env path is denied.' run_bridge "$bridge" reply "$calls" "Review prose."
  [[ $BRIDGE_RC == 0 && $(<"$calls.out") == 'The .env path is denied.' ]] || fail "$name rejected sensitive-path prose"

  run_bridge "$bridge" limit "$calls" "Review limit."
  [[ $BRIDGE_RC == 3 && $(<"$calls.err") == *'SPAR-BRIDGE LIMIT'* ]] || fail "$name did not classify a usage limit"
  run_bridge "$bridge" error-result "$calls" "Review error."
  [[ $BRIDGE_RC == 5 && $(<"$calls.err") == *'SPAR-BRIDGE ERROR'* ]] || fail "$name did not classify an error result"
  run_bridge "$bridge" failure "$calls" "Review failure."
  [[ $BRIDGE_RC == 5 && $(<"$calls.err") == *'reviewer failed while reading .env policy'* ]] ||
    fail "$name did not relay safe reviewer diagnostics"

  child_pid_file="$TMP/child-$name"
  start=$(date +%s)
  SPAR_TEST_CHILD_PID=$child_pid_file SPAR_BRIDGE_TIMEOUT=1 run_bridge "$bridge" hang "$calls" "Review timeout."
  [[ $BRIDGE_RC == 124 && $(<"$calls.err") == *'SPAR-BRIDGE TIMEOUT'* ]] || fail "$name did not classify a timeout"
  (( $(date +%s) - start <= 8 )) || fail "$name timeout was not bounded"
  if [[ -s $child_pid_file ]] && kill -0 "$(<"$child_pid_file")" 2>/dev/null; then
    fail "$name left a descendant after timeout"
  fi

  rm -f -- "$child_pid_file" "$calls"
  SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=hang SPAR_TEST_CHILD_PID=$child_pid_file PATH="$TMP/bin:$PATH" \
    /usr/bin/env -C "$repo" "$bridge" review "Review signal." >/dev/null 2>"$calls.err" &
  bridge_pid=$!
  for _ in $(seq 1 50); do [[ -s $child_pid_file ]] && break; sleep 0.1; done
  kill -TERM "$bridge_pid"
  rc=0
  wait "$bridge_pid" || rc=$?
  [[ $rc == 130 ]] || fail "$name did not return 130 after TERM"
  if [[ -s $child_pid_file ]] && kill -0 "$(<"$child_pid_file")" 2>/dev/null; then
    fail "$name left a descendant after TERM"
  fi
done

printf 'ok: spar bridges relay scanned one-pass reviews and honor repository opt-out\n'
