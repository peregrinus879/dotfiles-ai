#!/usr/bin/env bash
# Render the status line from representative payloads and check each segment.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATUSLINE="$ROOT/claude-code/.claude/statusline.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

render() { XDG_RUNTIME_DIR="$TMP" HOME="$TMP" "$STATUSLINE" <<<"$1"; }

now=$(date +%s)
future_hour=$(( now + 3600 ))
future_days=$(( now + 5 * 86400 + 6 * 3600 + 38 * 60 + 30 ))
full=$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Test"},"context_window":{"used_percentage":42,"total_input_tokens":84000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":%s},"seven_day":{"used_percentage":95,"resets_at":%s}}}\n' "$ROOT" "$future_hour" "$future_days")
output=$(render "$full")
[[ $output == *"${ROOT##*/}"* ]] || fail "repository directory segment did not render"
expected_branch=$(git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null || git -C "$ROOT" rev-parse --short HEAD)
[[ -n $expected_branch && $output == *"$expected_branch"* ]] || fail "branch segment did not render"
[[ $output == *'Test'* && $output != *'Claude Test'* ]] || fail "model segment did not strip the Claude prefix"
[[ $output == *'ctx:'*'42%'*'(116k)'* ]] || fail "context segment did not render the remaining tokens"
re_5h='5h:.*20%.*\((59m|1h:0m)\)'
[[ $output =~ $re_5h ]] || fail "five-hour segment did not render its countdown in unit fields"
re_7d='7d:.*95%.*\(5d:6h:38m\)'
[[ $output =~ $re_7d ]] || fail "seven-day segment did not render its countdown in unit fields"
[[ $output != *'extra:'* && $output != *"$HOSTNAME"* ]] || fail "retired segment rendered"

sub_minute=$(printf '{"model":{"display_name":"Claude Test"},"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":%s}}}\n' "$(( now + 30 ))")
output=$(render "$sub_minute")
re_sub='5h:.*5%.*\(<1m\)'
[[ $output =~ $re_sub ]] || fail "sub-minute countdown did not render as <1m"

minimal=$(printf '{"workspace":{"current_dir":"%s/nope"},"model":{"display_name":"Claude Test"},"context_window":{"used_percentage":42}}\n' "$TMP")
output=$(render "$minimal")
[[ $output == *'42%'* && $output != *'('* ]] || fail "missing fields did not degrade to bare segments"

output=$(render 'not json')
[[ -z $output ]] || fail "malformed input did not degrade to an empty line"

[[ -z $(find "$TMP" -mindepth 1 -maxdepth 1) ]] || fail "status line wrote persistent state"

printf 'ok: statusline renders its segments without persistent state\n'
