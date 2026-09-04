#!/usr/bin/env bash
# publish-clip reports which clipboard tool took the command, or none, and the
# tool receives the command byte for byte: wl-copy only under Wayland, clip.exe
# wherever interop provides it, and nothing when no tool is on PATH.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLIP="$ROOT/agents/.agents/skills/publish/scripts/publish-clip"
TMP=$(mktemp -d)
SHIMS="$TMP/bin"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$SHIMS"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for tool in wl-copy clip.exe; do
  printf '#!/usr/bin/env bash\ncat >"%s/%s.received"\n' "$TMP" "$tool" >"$SHIMS/$tool"
  chmod +x "$SHIMS/$tool"
done
command='git -C ~/Projects/example push origin abc:refs/heads/main --force-with-lease=refs/heads/main:def'

out=$(printf '%s' "$command" | env -i PATH="$SHIMS:/usr/bin:/bin" WAYLAND_DISPLAY=wayland-1 bash "$CLIP")
[[ $out == 'clipboard: wl-copy' && $(<"$TMP/wl-copy.received") == "$command" ]] || fail "wl-copy did not take the command under Wayland: $out"

rm -f -- "$TMP"/*.received
out=$(printf '%s' "$command" | env -i PATH="$SHIMS:/usr/bin:/bin" bash "$CLIP")
[[ $out == 'clipboard: clip.exe' && $(<"$TMP/clip.exe.received") == "$command" && ! -e $TMP/wl-copy.received ]] ||
  fail "clip.exe was not chosen without a Wayland session: $out"

out=$(printf '%s' "$command" | env -i PATH="/usr/bin:/bin" WAYLAND_DISPLAY=wayland-1 bash "$CLIP")
[[ $out == 'clipboard: none' ]] || fail "a missing tool was not reported as none: $out"

out=$(printf '' | env -i PATH="$SHIMS:/usr/bin:/bin" WAYLAND_DISPLAY=wayland-1 bash "$CLIP")
[[ $out == 'clipboard: none (empty input)' && ! -e $TMP/wl-copy.received ]] || fail "empty input reached a clipboard tool: $out"

printf 'ok: publish-clip names the clipboard tool that took the command, or none\n'
