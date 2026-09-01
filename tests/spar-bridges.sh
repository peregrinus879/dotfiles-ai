#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REPO_ROOT=$(realpath -e -- "$ROOT")
CLAUDE_BRIDGE="$ROOT/claude-code/.local/bin/spar-claude"
CODEX_BRIDGE="$ROOT/codex/.local/bin/spar-codex"
SCANNER="$ROOT/claude-code/.local/bin/spar-payload-scan"
TMP=$(mktemp -d)
HANDOFF_RE='^/var/tmp/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
HANDOFF_REGISTRY="$TMP/handoffs"
: >"$HANDOFF_REGISTRY"

cleanup_handoffs() {
  local handoff
  while IFS= read -r handoff; do
    [[ ! -e $handoff && ! -L $handoff ]] || rm -rf -- "$handoff"
  done <"$HANDOFF_REGISTRY"
}

cleanup() {
  cleanup_handoffs
  rm -rf -- "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/claude" <<'SHIM'
#!/usr/bin/env bash
[[ ${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-} == 1 ]] || exit 91
[[ ${DISABLE_AUTOUPDATER:-} == 1 ]] || exit 92
[[ -z ${CLAUDE_CODE_EFFORT_LEVEL:-} ]] || exit 89
if [[ " $* " == *' auth status '* ]]; then
  [[ " $* " == *' --safe-mode '* ]] || exit 93
  [[ " $* " == *' --setting-sources= '* ]] || exit 94
  [[ -z ${SPAR_TEST_PREFLIGHT:-} ]] || printf 'claude-auth\n' >>"$SPAR_TEST_PREFLIGHT"
  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty"}'
  exit
fi
args=("$@")
session_id=""
for ((index = 0; index + 1 < ${#args[@]}; index++)); do
  if [[ ${args[index]} == --session-id || ${args[index]} == --resume ]]; then
    session_id=${args[index + 1]}
  fi
done
prompt=$(cat)
[[ -z ${SPAR_TEST_STDIN:-} ]] || printf '%s' "$prompt" >"$SPAR_TEST_STDIN"
[[ -z ${SPAR_TEST_PWDS:-} ]] || printf '%s\n' "$PWD" >>"$SPAR_TEST_PWDS"
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
case ${SPAR_TEST_MODE:-ok} in
  ok) printf '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$session_id" ;;
  path-reply) printf '{"type":"result","is_error":false,"result":"The .env path is denied.","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$session_id" ;;
  sensitive-reply) printf '{"type":"result","is_error":false,"result":"%s","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$SPAR_TEST_SECRET" "$session_id" ;;
  eof) : ;;
  duplicate)
    printf '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$session_id"
    printf '{"type":"result","is_error":false,"result":"review twice","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$session_id" ;;
  empty) printf '{"type":"result","is_error":false,"result":"","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$session_id" ;;
  failure) printf '%s\n' '{"type":"result","is_error":true,"result":"review failed"}' ;;
  limit) printf '%s\n' '{"type":"result","is_error":true,"result":"usage limit reached"}' ;;
  missing-model) printf '{"type":"result","is_error":false,"result":"review ok","session_id":"%s"}\n' "$session_id" ;;
  wrong-model) printf '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-sonnet-5":{}},"session_id":"%s"}\n' "$session_id" ;;
  mixed-model) printf '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{},"claude-sonnet-5":{}},"session_id":"%s"}\n' "$session_id" ;;
  missing-session) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}}}' ;;
  wrong-session) printf '%s\n' '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}},"session_id":"22222222-2222-4222-8222-222222222222"}' ;;
  normal-child)
    (trap '' TERM; while :; do sleep 1; done) </dev/null >/dev/null 2>&1 &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    printf '{"type":"result","is_error":false,"result":"review ok","modelUsage":{"claude-opus-5":{}},"session_id":"%s"}\n' "$session_id" ;;
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
  [[ -z ${SPAR_TEST_PREFLIGHT:-} ]] || printf 'codex-login\n' >>"$SPAR_TEST_PREFLIGHT"
  printf '%s\n' 'Logged in using ChatGPT'
  exit
fi
if [[ ${1:-} == plugin && ${2:-} == list ]]; then
  [[ -z ${SPAR_TEST_PREFLIGHT:-} ]] || printf 'codex-plugin\n' >>"$SPAR_TEST_PREFLIGHT"
  case ${SPAR_TEST_MODE:-ok} in
    plugin-leak) printf '%s\n' '{"installed":[{"pluginId":"ambient@test"}]}' ;;
    plugin-null) printf '%s\n' '{"installed":null}' ;;
    plugin-object) printf '%s\n' '{"installed":{}}' ;;
    plugin-string) printf '%s\n' '{"installed":""}' ;;
    plugin-missing) printf '%s\n' '{}' ;;
    *)
      if [[ " $* " != *' features.plugins=false '* ]]; then
        printf '%s\n' '{"installed":[{"pluginId":"ambient@test"}]}'
      else
        printf '%s\n' '{"installed":[]}'
      fi ;;
  esac
  exit
fi
[[ ${1:-} == exec ]] || exit 90
args=("$@")
reviewer_profile=""
for ((index = 0; index + 1 < ${#args[@]}; index++)); do
  if [[ ${args[index]} == -c && ${args[index + 1]} == permissions.spar-reviewer=* ]]; then
    reviewer_profile=${args[index + 1]}
  fi
done
[[ -n $reviewer_profile ]] || exit 95
python3 -c 'import sys, tomllib; tomllib.loads(sys.argv[1])' "$reviewer_profile" || exit 96
prompt=$(cat)
[[ -z ${SPAR_TEST_STDIN:-} ]] || printf '%s' "$prompt" >"$SPAR_TEST_STDIN"
[[ -z ${SPAR_TEST_PWDS:-} ]] || printf '%s\n' "$PWD" >>"$SPAR_TEST_PWDS"
printf '%s\n' "$*" >>"$SPAR_TEST_CALLS"
case ${SPAR_TEST_MODE:-ok} in
  ok)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  path-reply)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"The .env path is denied."}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  sensitive-reply)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"$SPAR_TEST_SECRET\"}}"
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
  malformed)
    printf '%s\n' '{"type":"thread.started","thread_id":"not-a-uuid"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  wrong-thread)
    printf '%s\n' '{"type":"thread.started","thread_id":"22222222-2222-4222-8222-222222222222"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  item-before-thread)
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  normal-child)
    (trap '' TERM; while :; do sleep 1; done) </dev/null >/dev/null &
    printf '%s\n' "$!" >"$SPAR_TEST_CHILD_PID"
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"review ok"}}'
    printf '%s\n' '{"type":"turn.completed"}' ;;
  failure) printf '%s\n' '{"type":"turn.failed","error":"review failed"}' ;;
  stderr-failure)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' 'transport handshake failed while reading .env policy' >&2
    exit 1 ;;
  stderr-limit)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' 'rate limit reached; resets later' >&2
    exit 1 ;;
  stderr-sensitive)
    printf '%s\n' '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
    printf '%s\n' "$SPAR_TEST_SECRET" >&2
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

track_handoff() {
  [[ $1 =~ $HANDOFF_RE && -d $1 && ! -L $1 && $(realpath -e -- "$1") == "$1" ]] ||
    fail "refusing to track an unsafe fixture handoff"
  printf '%s\n' "$1" >>"$HANDOFF_REGISTRY"
}

raw_handoff() {
  local root
  root="/var/tmp/spar-$(cat /proc/sys/kernel/random/uuid)"
  mkdir -m 700 -- "$root"
  track_handoff "$root"
  printf '%s\n' "$root"
}

init_handoff() { # bridge
  local root
  root=$($1 init) || fail "${1##*/} could not initialize a handoff"
  track_handoff "$root"
  printf '%s\n' "$root"
}

run_new() { # bridge prompt [content] [mode]
  local bridge=$1 prompt=$2 content=${3:-} mode=${4:-ok} calls handoff preflight rc=0
  handoff=$(init_handoff "$bridge")
  calls="$TMP/calls-$RANDOM"
  preflight="$TMP/preflight-$RANDOM"
  [[ -z $content ]] || printf '%s' "$content" >"$handoff/payload.md"
  SPAR_TEST_CALLS=$calls SPAR_TEST_PREFLIGHT=$preflight SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
    "$bridge" new "$handoff" "$prompt" >/dev/null 2>/dev/null || rc=$?
  BRIDGE_RC=$rc
  BRIDGE_CALLED=0
  [[ ! -s $calls ]] || BRIDGE_CALLED=1
  PREFLIGHT_CALLED=0
  [[ ! -s $preflight ]] || PREFLIGHT_CALLED=1
}

hook_decision() { # target
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}\n' "$1" |
    "$ROOT/claude-code/.claude/hooks/spar-handoff-approve.sh" |
    jq -r '.hookSpecificOutput.permissionDecision'
}

# Initialization removes a private directory if manifest durability fails before output.
mkdir -p "$TMP/fail-bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/fail-bin/sync"
chmod 755 "$TMP/fail-bin/sync"
mkdir -p "$TMP/uuid-bin"
cat >"$TMP/uuid-bin/cat" <<'SHIM'
#!/usr/bin/env bash
if [[ $# == 1 && $1 == /proc/sys/kernel/random/uuid ]]; then
  printf '%s\n' "$SPAR_TEST_UUID"
else
  exec /usr/bin/cat "$@"
fi
SHIM
chmod 755 "$TMP/uuid-bin/cat"
fixture_uuid=$(cat /proc/sys/kernel/random/uuid)
expected_handoff="/var/tmp/spar-$fixture_uuid"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  if SPAR_TEST_UUID=$fixture_uuid PATH="$TMP/uuid-bin:$TMP/fail-bin:$PATH" \
    "$bridge" init >/dev/null 2>/dev/null; then
    fail "${bridge##*/} accepted a failed manifest flush"
  fi
  [[ ! -e $expected_handoff && ! -L $expected_handoff ]] ||
    fail "${bridge##*/} leaked a handoff after init failure"

  if SPAR_TEST_UUID=$fixture_uuid PATH="$TMP/uuid-bin:$PATH" \
    "$bridge" init >/dev/full 2>/dev/null; then
    fail "${bridge##*/} accepted a failed handoff-path write"
  fi
  [[ ! -e $expected_handoff && ! -L $expected_handoff ]] ||
    fail "${bridge##*/} leaked a handoff after output failure"
done

# Filesystem root cannot become a repository-wide reviewer grant.
mkdir -p "$TMP/root-git-bin"
cat >"$TMP/root-git-bin/git" <<'SHIM'
#!/usr/bin/env bash
[[ ${1:-} == rev-parse && ${2:-} == --show-toplevel ]] || exit 1
printf '/\n'
SHIM
chmod 755 "$TMP/root-git-bin/git"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  if PATH="$TMP/root-git-bin:$PATH" "$bridge" init >/dev/null 2>/dev/null; then
    fail "${bridge##*/} accepted filesystem root as a repository"
  fi
done

# A nested mount target inside the repository fails before handoff creation.
mkdir -p "$TMP/mount-bin"
cat >"$TMP/mount-bin/findmnt" <<'SHIM'
#!/usr/bin/env bash
printf '{"filesystems":[{"target":"%s","children":[{"target":"%s/nested"}]}]}\n' \
  "$SPAR_TEST_MOUNT_ROOT" "$SPAR_TEST_MOUNT_ROOT"
SHIM
chmod 755 "$TMP/mount-bin/findmnt"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  if SPAR_TEST_MOUNT_ROOT=$REPO_ROOT PATH="$TMP/mount-bin:$PATH" \
    "$bridge" init >/dev/null 2>/dev/null; then
    fail "${bridge##*/} accepted a nested repository mount"
  fi
done

# A denied-directory basename on the repository root cannot prune validation.
mkdir -p "$TMP/root-name"
git init -q "$TMP/root-name/secrets"
printf 'root-name hard-link fixture\n' >"$TMP/root-name-source"
ln -- "$TMP/root-name-source" "$TMP/root-name/secrets/public-alias.md"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  unexpected=""
  if unexpected=$(/usr/bin/env -C "$TMP/root-name/secrets" "$bridge" init 2>/dev/null); then
    [[ -z $unexpected ]] || track_handoff "$unexpected"
    fail "${bridge##*/} pruned repository validation by root basename"
  fi
done
rm -- "$TMP/root-name/secrets/public-alias.md" "$TMP/root-name-source"

repository_path_cases=(
  'file:Secrets'
  'file:.ENV_BAK'
  'file:PRIVATE.PEM~OLD'
  'file:odd"name'
  "file:odd'name"
  'file:odd\name'
  $'file:control\nname'
  $'file:control\u0085name'
  $'file:nonutf8-\xff'
  'dir:.env-old'
  'dir:service-credentials'
  'dir:vendor/.git'
)
case_index=0
for entry in "${repository_path_cases[@]}"; do
  ((case_index += 1))
  kind=${entry%%:*}
  path=${entry#*:}
  repo="$TMP/repository-path-$case_index"
  git init -q "$repo"
  parent=${path%/*}
  [[ $parent == "$path" ]] || mkdir -p "$repo/$parent"
  if [[ $kind == dir ]]; then
    mkdir -p "$repo/$path"
  else
    printf 'harmless\n' >"$repo/$path"
  fi
  for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
    unexpected=""
    if unexpected=$(/usr/bin/env -C "$repo" "$bridge" init 2>/dev/null); then
      [[ -z $unexpected ]] || track_handoff "$unexpected"
      fail "${bridge##*/} accepted unsafe repository path spelling: $path"
    fi
  done
done

unsafe_root="$TMP/"$'repository-root-\a'
git init -q "$unsafe_root"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  unexpected=""
  if unexpected=$(/usr/bin/env -C "$unsafe_root" "$bridge" init 2>/dev/null); then
    [[ -z $unexpected ]] || track_handoff "$unexpected"
    fail "${bridge##*/} accepted an unsafe canonical-root component"
  fi
done

repository_symlink_cases=(
  'vendor/.git:../public-dir'
  'vendor/id_rsa:../public.txt'
  'vendor/secrets/public-link:../../public.txt'
)
case_index=0
for entry in "${repository_symlink_cases[@]}"; do
  ((case_index += 1))
  path=${entry%%:*}
  target=${entry#*:}
  repo="$TMP/repository-symlink-$case_index"
  git init -q "$repo"
  mkdir -p "$repo/${path%/*}" "$repo/public-dir"
  printf 'harmless\n' >"$repo/public.txt"
  ln -s -- "$target" "$repo/$path"
  for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
    unexpected=""
    if unexpected=$(/usr/bin/env -C "$repo" "$bridge" init 2>/dev/null); then
      [[ -z $unexpected ]] || track_handoff "$unexpected"
      fail "${bridge##*/} accepted an unsupported repository symlink: $path"
    fi
  done
done

git init -q "$TMP/public-path-repo"
printf 'harmless\n' >"$TMP/public-path-repo/secretary.md"
printf 'harmless\n' >"$TMP/public-path-repo/id_rsa2-test-vector.txt"
mkdir -p "$TMP/public-path-repo/vendor/secrets"
printf 'harmless\n' >"$TMP/public-path-repo/vendor/secrets/public.txt"
ln -s -- secretary.md "$TMP/public-path-repo/public-link.md"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(/usr/bin/env -C "$TMP/public-path-repo" "$bridge" init) ||
    fail "${bridge##*/} rejected public separator-free repository names"
  track_handoff "$handoff"
done

# Native handoff writes reserve control and instruction filenames through aliases.
handoff=$(raw_handoff)
[[ $(hook_decision "$handoff/spar-plan.md") == allow ]] || fail "hook rejected a valid handoff write"
for target in "$handoff/reviewer-id" "$handoff/.env" "$handoff/.env~" "$handoff/.env-old" \
  "$handoff/.env_bak" "$handoff/AGENTS.md" "$handoff/Agents.md" "$handoff/CLAUDE.md" \
  "$handoff/private.p12~" "$handoff/id_ed25519.bak"; do
  [[ $(hook_decision "$target") == deny ]] || fail "hook allowed reserved target: $target"
done
ln -s -- "$handoff" "$TMP/handoff-alias"
[[ $(hook_decision "$TMP/handoff-alias/reviewer-id") == deny ]] || fail "hook allowed a reviewer-id alias"
rm -- "$TMP/handoff-alias"

# Outbound scanning is bounded, preserves the prompt, skips the private manifest,
# and blocks sensitive paths, values, unsafe metadata, and instruction filenames.
handoff=$(raw_handoff)
printf 'manifest-only synthetic value\n' >"$handoff/reviewer-id"
[[ $(printf 'Review ordinary material.' | "$SCANNER" outbound "$handoff") == 'Review ordinary material.' ]] ||
  fail "scanner did not preserve a safe prompt"
printf 'binary\0content' >"$handoff/payload.bin"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "binary handoff passed scanner"
fi
rm -- "$handoff/payload.bin"

printf '\377' >"$handoff/non-utf8.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "non-UTF-8 handoff passed scanner"
fi
rm -- "$handoff/non-utf8.md"

printf 'outside\n' >"$TMP/alias-target"
ln -s -- "$TMP/alias-target" "$handoff/linked.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "linked handoff entry passed scanner"
fi
rm -- "$handoff/linked.md"

printf 'hard-link fixture\n' >"$handoff/hard-source.md"
ln -- "$handoff/hard-source.md" "$handoff/hard-linked.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "hard-linked handoff entry passed scanner"
fi
rm -- "$handoff/hard-source.md" "$handoff/hard-linked.md"

chmod 755 "$handoff"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "unsafe handoff root mode passed scanner"
fi
chmod 700 "$handoff"

for name in .env .env~ .env-old .env_bak .netrc private.pem.bak private.p12~ id_rsa~ \
  AGENTS.md CLAUDE.md Reviewer-ID; do
  handoff=$(raw_handoff)
  printf 'harmless\n' >"$handoff/$name"
  if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
    fail "sensitive handoff filename passed scanner: $name"
  fi
done

handoff=$(raw_handoff)
for name in secretary.md id_rsa2-test-vector.txt "'auth.json'" 'notes\.env'; do
  printf 'harmless\n' >"$handoff/$name"
done
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "public separator-free or literal-path names were rejected"

handoff=$(raw_handoff)
mkdir -p "$handoff/a/.env-old"
printf 'harmless\n' >"$handoff/a/.env-old/config"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "sensitive nested handoff path passed scanner"
fi

unknown_token=$(printf '%s%s' 'sk-' 'UNKNOWNFIXTURE0123456789ABCDEF')
handoff=$(raw_handoff)
printf 'OPENAI_API_KEY=%s\n' "$unknown_token" >"$handoff/payload.md"
rc=0
diagnostic=$(printf 'Review.' | "$SCANNER" outbound "$handoff" 2>&1 >/dev/null) || rc=$?
if [[ $rc == 0 ]]; then
  fail "unknown credential-shaped content passed scanner"
fi
[[ $diagnostic != *"$unknown_token"* && ! $diagnostic =~ [0-9a-f]{64} ]] ||
  fail "scanner diagnostic exposed a credential value or derived digest"

blocked_scanner_vectors=(
  '//registry.example.invalid/:_authToken=PUBLICPACKAGEAUTH123'
  $'machine example.invalid\npassword PUBLICNETRC123'
)
for content in "${blocked_scanner_vectors[@]}"; do
  handoff=$(raw_handoff)
  printf '%s\n' "$content" >"$handoff/payload.md"
  if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
    fail "credential detector accepted its public-placeholder fixture"
  fi
done

public_scanner_vectors=(
  '-----BEGIN TEST PRIVATE KEY-----|-----BEGIN TESTX |PRIVATE KEY-----'
  'ghp_PUBLICFIXTURE0123456789AB|ghp_MUTATEDFIXTURE|0123456789AB'
  'AKIAPUBLICFIXTURE123|AKIAMUTATED|FIXTURE12'
)
for entry in "${public_scanner_vectors[@]}"; do
  content=${entry%%|*}
  mutation_parts=${entry#*|}
  mutated=$(printf '%s%s' "${mutation_parts%%|*}" "${mutation_parts#*|}")
  handoff=$(raw_handoff)
  printf '%s\n' "$content" >"$handoff/payload.md"
  printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
    fail "exact public detector fixture was rejected"
  printf '%s\n' "$mutated" >"$handoff/payload.md"
  if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
    fail "mutated public detector fixture passed scanner"
  fi
done

handoff=$(raw_handoff)
printf '%s\n' 'OPENAI_API_KEY=placeholder-token' \
  '//registry.example.invalid/:_authToken=example-token' "PASSWORD=\${PASSWORD}" \
  >"$handoff/payload.md"
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "scanner rejected documented placeholder values"

handoff=$(raw_handoff)
for _ in $(seq 1 10); do printf 'OPENAI_API_KEY=%s\n' "$unknown_token"; done >"$handoff/many.md"
rc=0
diagnostic=$(printf 'Review.' | "$SCANNER" outbound "$handoff" 2>&1 >/dev/null) || rc=$?
finding_count=$(grep -c '^SPAR-PAYLOAD FINDING:' <<<"$diagnostic")
[[ $rc != 0 && $finding_count == 9 && $diagnostic == *'12 additional findings omitted'* ]] ||
  fail "scanner finding report was not bounded"

diff_headers=(
  'diff --git a/.env.production b/.env.production'
  'diff --git a/a/.env-old/config b/a/.env-old/config'
  'diff --git a/private.pem/key.txt b/private.pem/key.txt'
  'diff --git "a/\056env" "b/\056env"'
  'diff --cc secrets/config'
  'diff --cc .netrc/token'
  'diff --combined private.pem'
  '--- a/.netrc'
  '+++ b/auth.json'
  '+++ b/auth.json/config'
  'rename from credentials.old'
  'rename to credentials.new'
  'rename old .env-old'
  'rename new auth.json.bak'
  'rename to id_rsa/public.txt'
  'copy from id_ed25519'
  'copy to .env_bak'
)
for header in "${diff_headers[@]}"; do
  handoff=$(raw_handoff)
  printf '%s\n' "$header" >"$handoff/payload.md"
  if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
    fail "sensitive diff header passed scanner: $header"
  fi
done

malformed_git_headers=(
  'diff --git "a/.env"x" "b/public"'
  'diff --git "a/.env\000x" "b/.env\000x"'
  'diff --git "a/public" "b/public"   '
  'diff --git a/public old b/public new'
  'rename to ".env"x"'
  '--- "a/.env"x"'
)
for header in "${malformed_git_headers[@]}"; do
  handoff=$(raw_handoff)
  printf '%s\n' "$header" >"$handoff/payload.md"
  if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
    fail "malformed Git diff header passed scanner: $header"
  fi
done

handoff=$(raw_handoff)
printf '%s\n' 'diff --git "a/public\040file" "b/public\040file"' >"$handoff/payload.md"
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "safe Git C-quoted diff path was rejected"

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public file b/public file' >"$handoff/payload.md"
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "safe unquoted Git diff path with spaces was rejected"

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public .env-old/config b/public .env-old/config' \
  'diff --git "a/caf\303\251.txt" b/public file.txt' \
  'diff --git a/public file.txt "b/caf\303\251.txt"' \
  'diff --git a/public old b/public new' \
  'similarity index 100%' \
  'rename from public old' \
  'rename to public new' >"$handoff/payload.md"
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "safe spaced or mixed-quoted Git diff path was rejected"

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public  b/public ' $'--- a/public \t' \
  $'+++ b/public \t' 'rename from  .env' >"$handoff/payload.md"
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "safe significant-whitespace Git path was rejected"

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public old b/public new/.env' \
  'similarity index 100%' \
  'rename from public old' \
  'rename to public new/.env' >"$handoff/payload.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "sensitive unquoted Git rename passed scanner"
fi

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public private.pem b/public' \
  'similarity index 100%' \
  'rename from public private.pem' \
  'rename to public' >"$handoff/payload.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "false Git header split hid a sensitive path"
fi

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public private.pem b/public' \
  'similarity index 100%' \
  'rename from public' \
  'rename to private.pem b/public' >"$handoff/payload.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "mismatched Git headers selected a false split"
fi

handoff=$(raw_handoff)
printf '%s\n' 'diff --git a/public old b/public new/.env' \
  'similarity index 100%' \
  'rename from public old' \
  'rename to public new' >"$handoff/payload.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "mismatched Git rename headers resolved an ambiguous path"
fi

unicode_repo="$TMP/unicode-diff-repo"
unicode_directory=$'public\u2028'
git init -q "$unicode_repo"
printf 'harmless\n' >"$unicode_repo/public"
git -C "$unicode_repo" add public
mkdir -p "$unicode_repo/$unicode_directory"
git -C "$unicode_repo" mv -- public "$unicode_directory/.env"
handoff=$(raw_handoff)
git -C "$unicode_repo" -c core.quotePath=false diff --cached --binary >"$handoff/payload.md"
[[ $(<"$handoff/payload.md") == *$'\u2028'* ]] ||
  fail "Git did not emit the literal Unicode line-separator fixture"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "Unicode line separator split a sensitive Git path"
fi

public_token=$(printf '%s%s' 'github_pat_' 'PUBLICFIXTURE0123456789ABCDEF')
handoff=$(raw_handoff)
printf 'GITHUB_TOKEN=%s\n' "$public_token" >"$handoff/payload.md"
printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1 ||
  fail "exact public synthetic fixture was rejected"
printf 'GITHUB_TOKEN=%sX\n' "$public_token" >"$handoff/payload.md"
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "mutated public synthetic fixture passed scanner"
fi

printf 'The .env path is denied.\n' | "$SCANNER" reply >/dev/null ||
  fail "reply scanner rejected sensitive-path prose"
if printf 'OPENAI_API_KEY=%s\n' "$unknown_token" | "$SCANNER" reply >/dev/null 2>&1; then
  fail "reply scanner accepted a credential value"
fi

handoff=$(raw_handoff)
python3 - "$handoff/oversized.md" <<'PY'
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text("x" * (512 * 1024 + 1))
PY
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "oversized handoff entry passed scanner"
fi

handoff=$(raw_handoff)
for index in $(seq 1 129); do printf 'x' >"$handoff/$index"; done
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "excessive handoff entry count passed scanner"
fi

handoff=$(raw_handoff)
for index in 1 2 3; do
  python3 - "$handoff/$index.md" <<'PY'
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text("x" * 400_000)
PY
done
if printf 'Review.' | "$SCANNER" outbound "$handoff" >/dev/null 2>&1; then
  fail "oversized aggregate payload passed scanner"
fi
if python3 -c 'import sys; sys.stdout.write("x" * (256 * 1024 + 1))' |
  "$SCANNER" outbound "$(raw_handoff)" >/dev/null 2>&1; then
  fail "oversized prompt passed scanner"
fi

# Both bridges reject outbound findings before auth and keep inbound path prose.
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  run_new "$bridge" "Review ordinary material."
  [[ $BRIDGE_RC == 0 && $BRIDGE_CALLED == 1 && $PREFLIGHT_CALLED == 1 ]] ||
    fail "ordinary review failed for ${bridge##*/}"

  run_new "$bridge" "OPENAI_API_KEY=$unknown_token"
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 && $PREFLIGHT_CALLED == 0 ]] ||
    fail "sensitive prompt reached ${bridge##*/} preflight"

  run_new "$bridge" "Review handoff." "OPENAI_API_KEY=$unknown_token"
  [[ $BRIDGE_RC != 0 && $BRIDGE_CALLED == 0 && $PREFLIGHT_CALLED == 0 ]] ||
    fail "sensitive handoff reached ${bridge##*/} preflight"

  run_new "$bridge" "Review reply channels." "" path-reply
  [[ $BRIDGE_RC == 0 ]] || fail "path prose reply was rejected by ${bridge##*/}"

  handoff=$(init_handoff "$bridge")
  calls="$TMP/reply-secret-${bridge##*/}"
  rc=0
  diagnostic=$(SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=sensitive-reply SPAR_TEST_SECRET="$unknown_token" \
    PATH="$TMP/bin:$PATH" "$bridge" new "$handoff" "Review reply channels." 2>&1 >/dev/null) || rc=$?
  [[ ${rc:-0} != 0 && $diagnostic != *"$unknown_token"* ]] ||
    fail "sensitive reply was exposed by ${bridge##*/}"
  rc=0
done

# Initialization writes a six-field repository binding. Old manifests, other
# bridges, other repositories, and cold sessions cannot resume.
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(init_handoff "$bridge")
  awk -F '\t' -v repo="$REPO_ROOT" 'NF == 6 && $3 == "initializer" && $4 == "initialized" && $5 == "-" && $6 == repo { ok=1 } END { exit ok ? 0 : 1 }' \
    "$handoff/reviewer-id" || fail "${bridge##*/} init did not bind the canonical repository"

  handoff=$(raw_handoff)
  printf '2026-08-17T00:00:00+00:00\tprimary\tstarted\t11111111-1111-4111-8111-111111111111\n' >"$handoff/reviewer-id"
  calls="$TMP/legacy-${bridge##*/}"
  if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$bridge" resume \
    11111111-1111-4111-8111-111111111111 "$handoff" "Resume legacy." >/dev/null 2>/dev/null; then
    fail "${bridge##*/} accepted a four-field manifest"
  fi
  [[ ! -s $calls ]] || fail "${bridge##*/} invoked a legacy resume"
done

# Lifecycle commands validate, report, flush, and remove owned handoffs.
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(init_handoff "$bridge")
  printf 'lifecycle\n' >"$handoff/spar-plan.md"
  "$bridge" flush "$handoff" || fail "${bridge##*/} could not flush its handoff"
  status=$("$bridge" status) || fail "${bridge##*/} could not report handoff status"
  [[ $status == *"handoff"$'\t'"$handoff"* && $status == *"manifest"$'\t'* ]] ||
    fail "${bridge##*/} status omitted its handoff or manifest"
  "$bridge" clean "$handoff" || fail "${bridge##*/} could not clean its handoff"
  [[ ! -e $handoff && ! -L $handoff ]] || fail "${bridge##*/} left its cleaned handoff"
done

handoff=$(init_handoff "$CLAUDE_BRIDGE")
calls="$TMP/cross-bridge"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$CODEX_BRIDGE" new "$handoff" \
  "Review wrong bridge." >/dev/null 2>/dev/null; then
  fail "Codex accepted a Claude-owned handoff"
fi
[[ ! -s $calls ]] || fail "Codex invoked a cross-bridge handoff"

git init -q "$TMP/other-repo"
mkdir -p "$TMP/other-repo/subdir"
for reviewer in claude codex; do
  cat >"$TMP/other-repo/$reviewer" <<'SHIM'
#!/usr/bin/env bash
: >"$SPAR_TEST_HOSTILE_PATH"
exit 99
SHIM
  chmod 755 "$TMP/other-repo/$reviewer"
done
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(/usr/bin/env -C "$TMP/other-repo/subdir" PATH=".:$TMP/bin:$PATH" "$bridge" init) ||
    fail "${bridge##*/} could not initialize the relative-PATH fixture"
  track_handoff "$handoff"
  marker="$TMP/hostile-path-${bridge##*/}"
  SPAR_TEST_HOSTILE_PATH=$marker SPAR_TEST_CALLS="$TMP/path-calls-${bridge##*/}" \
    PATH=".:$TMP/bin:$PATH" /usr/bin/env -C "$TMP/other-repo/subdir" \
    "$bridge" new "$handoff" "Review executable resolution." >/dev/null 2>/dev/null ||
    fail "${bridge##*/} did not retain its pre-chdir reviewer executable"
  [[ ! -e $marker ]] || fail "${bridge##*/} resolved a reviewer after changing directory"
done
rm -- "$TMP/other-repo/claude" "$TMP/other-repo/codex"

handoff=$(init_handoff "$CLAUDE_BRIDGE")
calls="$TMP/cross-repo"
if /usr/bin/env -C "$TMP/other-repo" SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" \
  "$CLAUDE_BRIDGE" new "$handoff" "Review wrong repository." >/dev/null 2>/dev/null; then
  fail "Claude accepted a handoff from another repository"
fi
[[ ! -s $calls ]] || fail "Claude invoked a cross-repository handoff"

# Caller Git routing and repository aliases cannot broaden reviewer context.
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  redirected=""
  if redirected=$(GIT_WORK_TREE="$TMP" "$bridge" init 2>/dev/null); then
    [[ -z $redirected ]] || track_handoff "$redirected"
    fail "${bridge##*/} accepted caller-directed Git discovery"
  fi

  handoff=$(/usr/bin/env -C "$TMP/other-repo" "$bridge" init) ||
    fail "${bridge##*/} could not initialize the hard-link fixture"
  track_handoff "$handoff"
  printf 'public alias fixture\n' >"$TMP/hardlink-source-${bridge##*/}"
  ln -- "$TMP/hardlink-source-${bridge##*/}" "$TMP/other-repo/public-alias.md"
  calls="$TMP/hardlink-calls-${bridge##*/}"
  if /usr/bin/env -C "$TMP/other-repo" SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" \
    "$bridge" new "$handoff" "Review hard-link fixture." >/dev/null 2>/dev/null; then
    fail "${bridge##*/} accepted a repository hard-link alias"
  fi
  [[ ! -s $calls ]] || fail "${bridge##*/} invoked a reviewer for a hard-link alias"
  rm -- "$TMP/other-repo/public-alias.md" "$TMP/hardlink-source-${bridge##*/}"
done

git init -q "$TMP/deep-repo"
handoff=$(/usr/bin/env -C "$TMP/deep-repo" "$CODEX_BRIDGE" init) ||
  fail "spar-codex could not initialize the depth fixture"
track_handoff "$handoff"
deep="$TMP/deep-repo"
for _ in $(seq 1 64); do deep="$deep/d"; done
deep="$deep/.git"
mkdir -p "$deep"
calls="$TMP/deep-calls"
if /usr/bin/env -C "$TMP/deep-repo" SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" new "$handoff" "Review deep fixture." >/dev/null 2>/dev/null; then
  fail "spar-codex accepted a repository beyond its deny-glob depth"
fi
[[ ! -s $calls ]] || fail "spar-codex invoked a reviewer beyond its deny-glob depth"

# New and resumed calls use identical isolation controls, the canonical
# repository cwd, the handoff as an extra read root, and scanned prompt stdin.
handoff=$(init_handoff "$CLAUDE_BRIDGE")
calls="$TMP/claude-flags"
pwds="$TMP/claude-pwds"
stdin_file="$TMP/claude-stdin"
CLAUDE_CODE_EFFORT_LEVEL=max SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds \
  SPAR_TEST_STDIN=$stdin_file PATH="$TMP/bin:$PATH" \
  "$CLAUDE_BRIDGE" new "$handoff" "Review Claude flags." >/dev/null 2>/dev/null
claude_new=$(<"$calls")
claude_sid=$(awk -F '\t' '$3 == "primary" && $4 == "allocated" { print $5; exit }' "$handoff/reviewer-id")
rm -- "$calls"
CLAUDE_CODE_EFFORT_LEVEL=max SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds \
  SPAR_TEST_STDIN=$stdin_file PATH="$TMP/bin:$PATH" \
  "$CLAUDE_BRIDGE" resume "$claude_sid" "$handoff" "Resume Claude flags." >/dev/null 2>/dev/null
claude_resume=$(<"$calls")
for flag in '--add-dir' '--permission-mode dontAsk' '--tools Read,Glob,Grep' '--model opus' \
  '--effort xhigh' '--safe-mode' '--setting-sources=' '--strict-mcp-config' '--mcp-config' '--system-prompt'; do
  [[ $claude_new == *"$flag"* && $claude_resume == *"$flag"* ]] || fail "Claude isolation missing: $flag"
done
for rule in "Read(/$REPO_ROOT/**)" "Read(/$handoff/**)" "Read(/$REPO_ROOT/.git)" \
  "Read(/$REPO_ROOT/.git/**)" "Read(/$handoff/reviewer-id)" 'Read(./.git)' \
  'Read(./**/.git)' 'Read(./**/.env)' 'Read(./**/.env-*)' 'Read(./**/.env_*)' \
  'Read(./**/.env~*)' 'Read(./secret~*)' 'Read(./**/secrets/**)' \
  'Read(./**/*.pem.*)' 'Read(./**/*.p12~*)' \
  'Read(./**/auth.json_*)' 'Read(./**/.netrc~*)' 'Read(./**/.npmrc-*)' \
  'Read(./**/.pypirc.*)' 'Read(./**/id_rsa~*)' 'Read(./**/id_ed25519_*)' \
  'Read(./**/*credentials*)' "Read(/$HOME/.aws/**)" "Read(/$HOME/.claude/.credentials.json)" \
  "Read(/$HOME/.config/gh/hosts.yml)" "Read(/$HOME/.docker/config.json)" \
  "Read(/$HOME/.gnupg/**)" "Read(/$HOME/.kube/**)" \
  "Read(/$HOME/.local/share/opencode/auth.json)" "Read(/$HOME/.ssh/**)"; do
  [[ $claude_new == *"$rule"* && $claude_resume == *"$rule"* ]] || fail "Claude permission rule missing: $rule"
done
[[ $claude_new != *'Read(./**/secret*)'* && $claude_resume != *'Read(./**/secret*)'* ]] ||
  fail "Claude policy overmatched public secret-prefixed paths"
[[ $claude_new != *'Read(./**/id_rsa*)'* && $claude_resume != *'Read(./**/id_rsa*)'* ]] ||
  fail "Claude policy overmatched public OpenSSH-prefix paths"
[[ $(sort -u "$pwds") == "$REPO_ROOT" && $(wc -l <"$pwds") == 2 ]] ||
  fail "Claude did not launch new and resume from the canonical repository"
[[ $(<"$stdin_file") == 'Resume Claude flags.' ]] || fail "Claude did not receive its scanned prompt on stdin"

handoff=$(init_handoff "$CLAUDE_BRIDGE")
calls="$TMP/claude-cold"
SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$CLAUDE_BRIDGE" new "$handoff" \
  "Cold review." cold >/dev/null 2>/dev/null
cold_sid=$(awk -F '\t' '$3 == "cold" && $4 == "allocated" { print $5; exit }' "$handoff/reviewer-id")
rm -- "$calls"
if SPAR_TEST_CALLS=$calls PATH="$TMP/bin:$PATH" "$CLAUDE_BRIDGE" resume "$cold_sid" \
  "$handoff" "Improper cold resume." >/dev/null 2>/dev/null; then
  fail "Claude resumed a cold reviewer"
fi
[[ ! -s $calls ]] || fail "Claude invoked a cold resume"

handoff=$(init_handoff "$CODEX_BRIDGE")
calls="$TMP/codex-flags"
pwds="$TMP/codex-pwds"
stdin_file="$TMP/codex-stdin"
SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds SPAR_TEST_STDIN=$stdin_file PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" new "$handoff" "Review Codex flags." >/dev/null 2>/dev/null
codex_new=$(<"$calls")
rm -- "$calls"
SPAR_TEST_CALLS=$calls SPAR_TEST_PWDS=$pwds SPAR_TEST_STDIN=$stdin_file PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" resume 11111111-1111-4111-8111-111111111111 "$handoff" \
  "Resume Codex flags." >/dev/null 2>/dev/null
codex_resume=$(<"$calls")
for flag in --ignore-user-config --ignore-rules --strict-config 'default_permissions="spar-reviewer"' \
  'forced_login_method="chatgpt"' 'model="gpt-5.6-sol"' 'model_reasoning_effort="xhigh"' \
  'model_reasoning_summary="none"' 'project_doc_max_bytes=0' 'project_doc_fallback_filenames=[]' \
  'project_root_markers=[]' 'trust_level="untrusted"' \
  'features.plugins=false' 'features.remote_plugin=false' 'features.multi_agent=false' \
  'web_search="disabled"' 'network={enabled=false}' 'service_tier="fast"'; do
  [[ $codex_new == *"$flag"* && $codex_resume == *"$flag"* ]] || fail "Codex isolation missing: $flag"
done
project_isolation="projects={\"$REPO_ROOT\"={trust_level=\"untrusted\"}}"
[[ $codex_new == *"$project_isolation"* && $codex_resume == *"$project_isolation"* ]] ||
  fail "Codex untrusted-project isolation is not bound to the canonical repository"
[[ $codex_new != *'"**/.git/**"="deny"'* && $codex_resume != *'"**/.git/**"="deny"'* ]] ||
  fail "Codex restored the recursive Git deny that breaks sandbox startup"
profile_prefix="filesystem={\":root\"=\"deny\",\":minimal\"=\"read\",\":tmpdir\"=\"deny\",\":slash_tmp\"=\"deny\",\"$TMP/bin/codex\"=\"read\",\"$REPO_ROOT\"=\"read\",\"$handoff\"=\"read\""
[[ $codex_new == *"$profile_prefix"* && $codex_resume == *"$profile_prefix"* ]] ||
  fail "Codex runtime-minimal grants or grant ordering drifted"
for rule in "\"$REPO_ROOT\"=\"read\"" "\"$handoff\"=\"read\"" \
  "\"$REPO_ROOT/.git\"=\"deny\"" "\"$handoff/reviewer-id\"=\"deny\"" \
  '":workspace_roots"' '"**/.env"="deny"' '"**/.env-*"="deny"' \
  '"**/.env_*"="deny"' '"**/.env~*"="deny"' '"**/*.pem.*"="deny"' \
  '"**/*.p12~*"="deny"' '"secret~*"="deny"' '"**/secrets/**"="deny"' \
  '"**/auth.json_*"="deny"' '"**/.netrc~*"="deny"' \
  '"**/.npmrc-*"="deny"' '"**/.pypirc.*"="deny"' \
  '"**/id_rsa~*"="deny"' '"**/id_ed25519_*"="deny"' '"**/*credentials*"="deny"'; do
  [[ $codex_new == *"$rule"* && $codex_resume == *"$rule"* ]] || fail "Codex permission rule missing: $rule"
done
[[ $codex_new != *'"**/secret*"="deny"'* && $codex_resume != *'"**/secret*"="deny"'* ]] ||
  fail "Codex policy overmatched public secret-prefixed paths"
[[ $codex_new != *'"**/id_rsa*"="deny"'* && $codex_resume != *'"**/id_rsa*"="deny"'* ]] ||
  fail "Codex policy overmatched public OpenSSH-prefix paths"
[[ $codex_new == *'-C '"$REPO_ROOT"* && $codex_resume == *'-C '"$REPO_ROOT"* ]] ||
  fail "Codex repository directory flag is missing"
[[ $(sort -u "$pwds") == "$REPO_ROOT" && $(wc -l <"$pwds") == 2 ]] ||
  fail "Codex did not launch new and resume from the canonical repository"
[[ $(<"$stdin_file") == *'Resume Codex flags.' && $codex_resume == *'resume -- 11111111-1111-4111-8111-111111111111 -'* ]] ||
  fail "Codex did not receive its scanned prompt through stdin"

# Subscription, routing, state, and plugin preflights fail before review.
for variable in CODEX_API_KEY CODEX_HOME CODEX_SQLITE_HOME OPENAI_BASE_URL HTTPS_PROXY; do
  handoff=$(init_handoff "$CODEX_BRIDGE")
  calls="$TMP/codex-env-$variable"
  if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" "$variable=sentinel" \
    "$CODEX_BRIDGE" new "$handoff" "Review isolation." >/dev/null 2>/dev/null; then
    fail "Codex accepted $variable"
  fi
  [[ ! -s $calls ]] || fail "Codex invoked a review after accepting $variable"
done
for mode in plugin-leak plugin-null plugin-object plugin-string plugin-missing; do
  handoff=$(init_handoff "$CODEX_BRIDGE")
  calls="$TMP/codex-plugins-$mode"
  if SPAR_TEST_CALLS=$calls SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
    "$CODEX_BRIDGE" new "$handoff" "Review plugins." >/dev/null 2>/dev/null; then
    fail "Codex accepted plugin preflight mode $mode"
  fi
  [[ ! -s $calls ]] || fail "Codex invoked a review after plugin preflight failure: $mode"
done

for variable in ANTHROPIC_AUTH_TOKEN ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_CUSTOM_HEADERS \
  CLAUDE_CODE_USE_ANTHROPIC_AWS CLAUDE_CODE_USE_MANTLE CLAUDE_CODE_SKIP_ANTHROPIC_AWS_AUTH \
  CLAUDE_CODE_SKIP_MANTLE_AUTH ANTHROPIC_AWS_API_KEY ANTHROPIC_AWS_BASE_URL \
  ANTHROPIC_AWS_WORKSPACE_ID ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_BEDROCK_MANTLE_BASE_URL \
  HTTPS_PROXY; do
  handoff=$(init_handoff "$CLAUDE_BRIDGE")
  calls="$TMP/claude-env-$variable"
  if env SPAR_TEST_CALLS="$calls" PATH="$TMP/bin:$PATH" "$variable=sentinel" \
    "$CLAUDE_BRIDGE" new "$handoff" "Review isolation." >/dev/null 2>/dev/null; then
    fail "Claude accepted $variable"
  fi
  [[ ! -s $calls ]] || fail "Claude invoked a review after accepting $variable"
done

printf 'printf sourced >"$%s"\n' 'SPAR_TEST_BASH_ENV_HIT' >"$TMP/hostile-bash-env"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(init_handoff "$bridge")
  calls="$TMP/bash-env-${bridge##*/}"
  hit="$TMP/bash-env-hit-${bridge##*/}"
  BASH_ENV="$TMP/hostile-bash-env" SPAR_TEST_BASH_ENV_HIT=$hit SPAR_TEST_CALLS=$calls \
    PATH="$TMP/bin:$PATH" "$bridge" new "$handoff" "Review startup." >/dev/null 2>/dev/null ||
    fail "${bridge##*/} failed under hostile BASH_ENV"
  [[ ! -e $hit ]] || fail "${bridge##*/} executed caller Bash startup code"
done

# Terminal contracts reject malformed streams, scan diagnostics, retain failed
# new-session identifiers, and bound reviewer process groups on every exit path.
for mode in eof empty malformed failure item-before-thread; do
  handoff=$(init_handoff "$CODEX_BRIDGE")
  if SPAR_TEST_CALLS="$TMP/codex-$mode" SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
    "$CODEX_BRIDGE" new "$handoff" "Review terminal events." >/dev/null 2>/dev/null; then
    fail "Codex accepted terminal mode $mode"
  fi
done

handoff=$(init_handoff "$CODEX_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/codex-duplicate" SPAR_TEST_MODE=duplicate PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" new "$handoff" "Review terminal events." 2>&1 >/dev/null) || rc=$?
[[ $rc == 5 && $diagnostic == *'SPAR-BRIDGE THREAD:'* ]] ||
  fail "Codex did not report a valid new thread after a later event-order failure"

for mode in eof duplicate empty failure missing-model wrong-model mixed-model missing-session wrong-session; do
  handoff=$(init_handoff "$CLAUDE_BRIDGE")
  rc=0
  diagnostic=$(SPAR_TEST_CALLS="$TMP/claude-$mode" SPAR_TEST_MODE=$mode PATH="$TMP/bin:$PATH" \
    "$CLAUDE_BRIDGE" new "$handoff" "Review terminal events." 2>&1 >/dev/null) || rc=$?
  [[ $rc == 5 && $diagnostic != *'review failed'* ]] || fail "Claude terminal mode contract failed: $mode"
  [[ $diagnostic == *'SPAR-BRIDGE SESSION:'* ]] || fail "Claude did not report its failed new session"
done

mkdir -p "$TMP/mktemp-fail-bin"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/mktemp-fail-bin/mktemp"
chmod 755 "$TMP/mktemp-fail-bin/mktemp"
handoff=$(init_handoff "$CLAUDE_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/claude-mktemp-failure" \
  PATH="$TMP/mktemp-fail-bin:$TMP/bin:$PATH" "$CLAUDE_BRIDGE" new "$handoff" \
  "Review early recovery." 2>&1 >/dev/null) || rc=$?
[[ $rc == 2 && $diagnostic == *'SPAR-BRIDGE SESSION:'* ]] ||
  fail "Claude did not report an allocated session after workdir creation failed"

handoff=$(init_handoff "$CLAUDE_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/claude-final-output" PATH="$TMP/bin:$PATH" \
  "$CLAUDE_BRIDGE" new "$handoff" "Review final delivery." 2>&1 >/dev/full) || rc=$?
[[ $rc != 0 && $diagnostic == *'SPAR-BRIDGE SESSION:'* ]] ||
  fail "Claude did not report an allocated session after final delivery failed"

# Diagnostic write failures preserve reviewer status and cannot retain private output.
mkdir -p "$TMP/mktemp-bin"
cat >"$TMP/mktemp-bin/mktemp" <<'SHIM'
#!/usr/bin/env bash
[[ ${1:-} == -d ]] || exit 1
mkdir -m 700 -- "$SPAR_TEST_WORKDIR"
printf '%s\n' "$SPAR_TEST_WORKDIR"
SHIM
chmod 755 "$TMP/mktemp-bin/mktemp"
for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(init_handoff "$bridge")
  workdir="$TMP/failed-diagnostic-${bridge##*/}"
  rc=0
  SPAR_TEST_WORKDIR=$workdir SPAR_TEST_CALLS="$TMP/full-stderr-${bridge##*/}" \
    SPAR_TEST_MODE=duplicate PATH="$TMP/mktemp-bin:$TMP/bin:$PATH" \
    "$bridge" new "$handoff" "Review failed diagnostic cleanup." >/dev/null 2>/dev/full || rc=$?
  [[ $rc == 5 ]] || fail "${bridge##*/} changed reviewer status after a diagnostic write failure"
  [[ ! -e $workdir && ! -L $workdir ]] ||
    fail "${bridge##*/} retained a private work directory after a diagnostic write failure"
done

handoff=$(init_handoff "$CODEX_BRIDGE")
SPAR_TEST_CALLS="$TMP/codex-resume-seed" PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" new "$handoff" "Seed resume binding." >/dev/null 2>/dev/null
if SPAR_TEST_CALLS="$TMP/codex-wrong-thread" SPAR_TEST_MODE=wrong-thread PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" resume 11111111-1111-4111-8111-111111111111 "$handoff" \
  "Resume exact thread." >/dev/null 2>/dev/null; then
  fail "Codex accepted a resumed event for another thread"
fi

handoff=$(init_handoff "$CLAUDE_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/claude-limit" SPAR_TEST_MODE=limit PATH="$TMP/bin:$PATH" \
  "$CLAUDE_BRIDGE" new "$handoff" "Review limit." 2>&1 >/dev/null) || rc=$?
[[ $rc == 3 && $diagnostic == *'usage limit'* ]] || fail "Claude did not classify a usage limit"

handoff=$(init_handoff "$CODEX_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/codex-stderr" SPAR_TEST_MODE=stderr-failure PATH="$TMP/bin:$PATH" \
  "$CODEX_BRIDGE" new "$handoff" "Review stderr." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'transport handshake failed while reading .env policy'* && \
  $diagnostic == *'SPAR-BRIDGE THREAD:'* ]] || fail "Codex did not scan and relay bounded safe stderr"

handoff=$(init_handoff "$CODEX_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/codex-secret-stderr" SPAR_TEST_MODE=stderr-sensitive \
  SPAR_TEST_SECRET="$unknown_token" PATH="$TMP/bin:$PATH" "$CODEX_BRIDGE" new "$handoff" \
  "Review stderr." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'withheld by content gate'* && $diagnostic != *"$unknown_token"* ]] ||
  fail "Codex exposed sensitive stderr"

handoff=$(init_handoff "$CODEX_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/codex-limit-stderr" SPAR_TEST_MODE=stderr-limit \
  PATH="$TMP/bin:$PATH" "$CODEX_BRIDGE" new "$handoff" "Review limit stderr." 2>&1) || rc=$?
[[ $rc == 3 && $diagnostic == *'usage limit'* ]] || fail "Codex did not classify stderr-only limit"

handoff=$(init_handoff "$CODEX_BRIDGE")
rc=0
diagnostic=$(SPAR_TEST_CALLS="$TMP/codex-oversized-stderr" SPAR_TEST_MODE=stderr-oversized \
  PATH="$TMP/bin:$PATH" "$CODEX_BRIDGE" new "$handoff" "Review oversized stderr." 2>&1) || rc=$?
[[ $rc == 5 && $diagnostic == *'exceeds 8192-byte relay bound'* && $diagnostic != *'0000000000000000'* ]] ||
  fail "Codex relayed oversized stderr"

for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  handoff=$(init_handoff "$bridge")
  child_pid_file="$TMP/normal-child-${bridge##*/}"
  SPAR_TEST_CALLS="$TMP/normal-${bridge##*/}" SPAR_TEST_MODE=normal-child \
    SPAR_TEST_CHILD_PID=$child_pid_file PATH="$TMP/bin:$PATH" \
    "$bridge" new "$handoff" "Review normal cleanup." >/dev/null 2>/dev/null ||
    fail "${bridge##*/} rejected a valid normal-exit fixture"
  sleep 0.1
  if [[ -s $child_pid_file ]] && kill -0 "$(<"$child_pid_file")" 2>/dev/null; then
    fail "${bridge##*/} left a descendant after normal leader exit"
  fi
done

for bridge in "$CLAUDE_BRIDGE" "$CODEX_BRIDGE"; do
  for mode in stall ceiling; do
    handoff=$(init_handoff "$bridge")
    child_pid_file="$TMP/child-${bridge##*/}-$mode"
    start=$(date +%s)
    rc=0
    diagnostic=$(SPAR_TEST_CALLS="$TMP/timeout-${bridge##*/}-$mode" SPAR_TEST_MODE=$mode \
      SPAR_TEST_CHILD_PID=$child_pid_file SPAR_BRIDGE_STALL=1 SPAR_BRIDGE_CEILING=2 \
      PATH="$TMP/bin:$PATH" "$bridge" new "$handoff" "Review timeout." 2>&1 >/dev/null) || rc=$?
    if [[ $mode == stall ]]; then
      [[ $rc == 4 && $diagnostic == *'SPAR-BRIDGE STALL:'* ]] ||
        fail "${bridge##*/} misclassified a stall"
    else
      [[ $rc == 124 && $diagnostic == *'SPAR-BRIDGE CEILING:'* ]] ||
        fail "${bridge##*/} misclassified a hard-kill ceiling"
    fi
    elapsed=$(($(date +%s) - start))
    [[ $elapsed -le 6 ]] || fail "${bridge##*/} timeout cleanup was not bounded"
    if [[ -s $child_pid_file ]] && kill -0 "$(<"$child_pid_file")" 2>/dev/null; then
      fail "${bridge##*/} left a descendant after $mode"
    fi
  done

  handoff=$(init_handoff "$bridge")
  child_pid_file="$TMP/signal-child-${bridge##*/}"
  diagnostic="$TMP/signal-diagnostic-${bridge##*/}"
  SPAR_TEST_CALLS="$TMP/signal-${bridge##*/}" SPAR_TEST_MODE=stall \
    SPAR_TEST_CHILD_PID=$child_pid_file SPAR_BRIDGE_STALL=30 SPAR_BRIDGE_CEILING=60 \
    PATH="$TMP/bin:$PATH" "$bridge" new "$handoff" "Review signal." \
    >/dev/null 2>"$diagnostic" &
  bridge_pid=$!
  for _ in $(seq 1 50); do [[ -s $child_pid_file ]] && break; sleep 0.1; done
  kill -TERM "$bridge_pid"
  kill -TERM "$bridge_pid" 2>/dev/null || true
  rc=0
  wait "$bridge_pid" || rc=$?
  [[ $rc == 130 ]] || fail "${bridge##*/} did not return 130 after TERM"
  [[ $(<"$diagnostic") != *"not a pid or valid job spec"* ]] || fail "${bridge##*/} waited on an empty pid"
  if [[ -s $child_pid_file ]] && kill -0 "$(<"$child_pid_file")" 2>/dev/null; then
    fail "${bridge##*/} left a descendant after TERM"
  fi
done

cleanup_handoffs
while IFS= read -r handoff; do
  [[ ! -e $handoff && ! -L $handoff ]] || fail "fixture cleanup left a handoff: $handoff"
done <"$HANDOFF_REGISTRY"

printf 'ok: spar bridges expose bounded read-only repository context with repository-bound sessions\n'
