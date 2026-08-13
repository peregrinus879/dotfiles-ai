#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATUSLINE="$ROOT/claude-code/.claude/statusline.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

runtime="$TMP/runtime"
mkdir -m 700 -- "$runtime"
uid=$(id -u)
state_root="$runtime/claude-statusline-$uid"
cwd="$ROOT"
session="statusline-security-probe"
cwd_key=$(printf '%s' "$cwd" | sha256sum | cut -d' ' -f1)
session_key=$(printf '%s' "$session" | sha256sum | cut -d' ' -f1)
git_state="$state_root/git-$cwd_key"
extra_state="$state_root/extra-$session_key"

input=$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Test"},"rate_limits":{"five_hour":{"used_percentage":100},"seven_day":{"used_percentage":10}},"cost":{"total_cost_usd":1.25},"session_id":"%s"}\n' "$cwd" "$session")
XDG_RUNTIME_DIR="$runtime" "$STATUSLINE" <<<"$input" >/dev/null

[[ $(stat -c '%u:%a' -- "$state_root") == "$uid:700" ]] || fail "state root is not owner-only"
for state in "$git_state" "$extra_state"; do
  [[ -f $state && ! -L $state ]] || fail "state file is not regular: $state"
  [[ $(stat -c '%u:%a:%h' -- "$state") == "$uid:600:1" ]] || fail "state file metadata is unsafe: $state"
done
compgen -G "$state_root/.state.*" >/dev/null && fail "atomic-write temporary file remained"

without_session=${input/\"session_id\":\"$session\"/\"session_id\":\"\"}
before_count=$(printf '%s\n' "$state_root"/extra-* | wc -l)
XDG_RUNTIME_DIR="$runtime" "$STATUSLINE" <<<"$without_session" >/dev/null
after_count=$(printf '%s\n' "$state_root"/extra-* | wc -l)
[[ $before_count == "$after_count" ]] || fail "missing session id created shared cost state"

rm -- "$git_state"
printf 'canary\n' >"$TMP/symlink-canary"
chmod 600 -- "$TMP/symlink-canary"
ln -s -- "$TMP/symlink-canary" "$git_state"
XDG_RUNTIME_DIR="$runtime" "$STATUSLINE" <<<"$input" >/dev/null
[[ $(<"$TMP/symlink-canary") == canary ]] || fail "statusline followed a state-file symlink"
[[ -L $git_state ]] || fail "statusline replaced an unsafe state-file symlink"

rm -- "$git_state"
printf 'hardlink-canary\n' >"$TMP/hardlink-canary"
chmod 600 -- "$TMP/hardlink-canary"
ln -- "$TMP/hardlink-canary" "$git_state"
XDG_RUNTIME_DIR="$runtime" "$STATUSLINE" <<<"$input" >/dev/null
[[ $(<"$TMP/hardlink-canary") == hardlink-canary ]] || fail "statusline wrote through a state-file hard link"
[[ $(stat -c '%h' -- "$git_state") == 2 ]] || fail "statusline replaced an unsafe state-file hard link"

rm -rf -- "$state_root"
mkdir -m 700 -- "$TMP/outside"
ln -s -- "$TMP/outside" "$state_root"
XDG_RUNTIME_DIR="$runtime" "$STATUSLINE" <<<"$input" >/dev/null
shopt -s nullglob dotglob
outside_files=("$TMP/outside"/*)
[[ ${#outside_files[@]} == 0 ]] || fail "statusline followed a state-root symlink"

printf 'ok: statusline runtime state rejects symlink and hard-link attacks\n'
