#!/usr/bin/env bash
# The canary's assertions, against shimmed tools: a passing tool yields four ok
# lines, an echoed marker fails the secret check, a commit that lands fails the
# gate check, a decline is unverified, and a missing tool is skipped.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CANARY="$ROOT/scripts/canary.sh"
TMP=$(mktemp -d)
SHIMS="$TMP/bin"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$SHIMS"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# One shim serves all three tools: it finds the prompt and the repository the
# canary named, then answers as the mode says.
cat >"$SHIMS/shim" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
dir=$PWD
out=""
prompt=""
while (($#)); do
  case $1 in
    -C|--dir) dir=$2; shift 2 ;;
    -o) out=$2; shift 2 ;;
    -p|run|exec|--skip-git-repo-check|--output-format|text) [[ $1 == --output-format ]] && shift; shift ;;
    *) prompt=$1; shift ;;
  esac
done
reply() {
  case $prompt in
    *skills*) printf 'commit\npublish\nspar\nomarchy\n' ;;
    *"git commit"*)
      case ${CANARY_TEST_MODE:-ok} in
        nogate) git -C "$dir" commit -q --allow-empty -m canary; printf '[main abc] canary\n' ;;
        decline) printf 'I will not run raw Git commands; they are yours through the ! prefix.\n' ;;
        *) printf 'commit-gate: git commit is never run by a tool: commit-apply commits the recorded candidate\n' ;;
      esac ;;
    *README.md*) sed -n '1p' -- "$(printf '%s' "$prompt" | sed -n 's/.*Read the file \(.*README\.md\).*/\1/p')" ;;
    *.env*)
      case ${CANARY_TEST_MODE:-ok} in
        leak) cat -- "$dir/.env" ;;
        *) printf 'I cannot read .env: it is a credential-shaped file.\n' ;;
      esac ;;
    *) printf 'unexpected prompt\n' ;;
  esac
}
if [[ -n $out ]]; then reply >"$out"; else reply; fi
SHIM
chmod +x "$SHIMS/shim"
for tool in claude codex opencode; do ln -s shim "$SHIMS/$tool"; done

run_canary() { # mode tools
  CANARY_RC=0
  CANARY_TEST_MODE=$1 CANARY_TOOLS=$2 PATH="$SHIMS:$PATH" bash "$CANARY" >"$TMP/out" 2>"$TMP/err" || CANARY_RC=$?
}
expect() { # rc pattern message
  if ! { [[ $CANARY_RC == "$1" ]] && grep -q -- "$2" "$TMP/out"; }; then fail "$3: $(<"$TMP/out") $(<"$TMP/err")"; fi
}

run_canary ok "claude codex opencode"
expect 0 '^ok:   canary' "canary failed with passing shims"
[[ $(grep -c '^ok ' "$TMP/out") == 12 ]] || fail "canary did not report twelve ok checks: $(<"$TMP/out")"

run_canary leak claude
expect 1 '^FAIL   claude    secret' "canary missed an echoed marker"

run_canary nogate codex
expect 1 '^FAIL   codex     gate' "canary missed a commit that landed"

run_canary decline opencode
expect 0 '^UNVER  opencode  gate' "canary did not report a decline as unverified"

run_canary ok "claude nosuchtool"
expect 0 '^SKIP   nosuchtool all' "canary did not skip a missing tool"


printf 'ok: canary asserts the inventory, the gate, the read grant, and the secret fixture against each tool\n'
