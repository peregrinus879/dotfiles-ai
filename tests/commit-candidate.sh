#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

STATUS_GIT_ARGS=(
  --no-optional-locks
  -c core.quotePath=true
  -c color.status=false
  -c status.renames=false
)
STATUS_ARGS=(--porcelain=v2 -z --untracked-files=all)
TRACKED_GIT_ARGS=(
  --no-optional-locks
  -c core.quotePath=true
  -c color.ui=false
  -c color.diff=false
  -c core.compression=0
  -c diff.orderFile=/dev/null
  -c diff.suppressBlankEmpty=false
)
TRACKED_DIFF_ARGS=(
  --binary
  --full-index
  --no-ext-diff
  --no-textconv
  --no-renames
  --no-indent-heuristic
  --diff-algorithm=myers
  --unified=3
  --no-relative
  --src-prefix=a/
  --dst-prefix=b/
)

status_command="git ${STATUS_GIT_ARGS[*]} status ${STATUS_ARGS[*]} | sha256sum"
tracked_command="git ${TRACKED_GIT_ARGS[*]} diff [--cached] ${TRACKED_DIFF_ARGS[*]} \"<base>\" -- \"<base-present-intended-path>\"... | sha256sum"
skill="$ROOT/claude-code/.claude/skills/commit/SKILL.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fq "$status_command" "$skill" || fail 'candidate-status-v1 documentation drifted'
grep -Fq "$tracked_command" "$skill" || fail 'candidate-tracked-v1 documentation drifted'
grep -Fq 'sha256sum -- "<path>"' "$skill" || fail 'candidate-new-v1 regular digest drifted'
grep -Fq 'git hash-object --no-filters -- "<path>"' "$skill" || fail 'candidate-new-v1 regular object drifted'
grep -Fq 'readlink -n -- "<path>" | sha256sum' "$skill" || fail 'candidate-new-v1 symlink digest drifted'
grep -Fq 'readlink -n -- "<path>" | git hash-object --stdin' "$skill" || fail 'candidate-new-v1 symlink object drifted'

hash_stream() {
  local digest
  read -r digest _
  printf '%s\n' "$digest"
}

status_fingerprint() {
  local repo=$1
  git -C "$repo" "${STATUS_GIT_ARGS[@]}" status "${STATUS_ARGS[@]}" |
    sha256sum | hash_stream
}

tracked_fingerprint() {
  local repo=$1 source=$2
  shift 2
  local -a source_args=()
  [[ $source == index ]] && source_args+=(--cached)
  git -C "$repo" "${TRACKED_GIT_ARGS[@]}" diff "${source_args[@]}" \
    "${TRACKED_DIFF_ARGS[@]}" HEAD -- "$@" | sha256sum | hash_stream
}

init_repo() {
  local repo=$1
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name 'Fixture User'
  git -C "$repo" config user.email 'fixture@example.invalid'
  git -C "$repo" config core.autocrlf false
}

repo="$TMP/candidate"
init_repo "$repo"
git -C "$repo" config core.fileMode true
printf 'base text\n' >"$repo/text.txt"
printf '\x00\x01base\xff' >"$repo/binary.bin"
printf 'delete me\n' >"$repo/delete.txt"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/mode.sh"
printf 'rename me\n' >"$repo/old.txt"
printf 'unrelated\n' >"$repo/omitted.txt"
chmod 644 "$repo/mode.sh"
git -C "$repo" add -- binary.bin delete.txt mode.sh old.txt omitted.txt text.txt
git -C "$repo" commit -qm base

printf 'changed text\n' >"$repo/text.txt"
printf '\x00\x02changed\xfe' >"$repo/binary.bin"
rm -- "$repo/delete.txt"
chmod 755 "$repo/mode.sh"
mv -- "$repo/old.txt" "$repo/renamed.txt"
printf 'new file\n' >"$repo/new.txt"
ln -s new.txt "$repo/new.link"

tracked_paths=(binary.bin delete.txt mode.sh old.txt text.txt)
tracked_before=$(tracked_fingerprint "$repo" worktree "${tracked_paths[@]}")
[[ -n $tracked_before ]] || fail 'candidate-tracked-v1 produced no digest'
git -C "$repo" diff --summary HEAD -- mode.sh | grep -Fq 'mode change' ||
  fail 'mode-capable worktree did not expose the intended mode change'

status_before=$(status_fingerprint "$repo")
printf 'unrelated changed\n' >"$repo/omitted.txt"
status_after=$(status_fingerprint "$repo")
[[ $status_before != "$status_after" ]] || fail 'candidate-status-v1 missed an omitted tracked change'

new_sha_before=$(sha256sum -- "$repo/new.txt" | hash_stream)
new_blob_before=$(git -C "$repo" hash-object --no-filters -- new.txt)
link_sha_before=$(readlink -n -- "$repo/new.link" | sha256sum | hash_stream)
link_blob_before=$(readlink -n -- "$repo/new.link" | git -C "$repo" hash-object --stdin)

git -C "$repo" add -- binary.bin delete.txt mode.sh new.link new.txt old.txt renamed.txt text.txt
tracked_after=$(tracked_fingerprint "$repo" index "${tracked_paths[@]}")
[[ $tracked_before == "$tracked_after" ]] || fail 'candidate-tracked-v1 changed across staging'

read -r new_mode new_blob _ < <(git -C "$repo" ls-files --stage -- new.txt)
[[ $new_mode == 100644 && $new_blob == "$new_blob_before" ]] ||
  fail 'candidate-new-v1 regular-file binding changed across staging'
[[ $(sha256sum -- "$repo/new.txt" | hash_stream) == "$new_sha_before" ]] ||
  fail 'candidate-new-v1 regular-file worktree digest drifted'

read -r link_mode link_blob _ < <(git -C "$repo" ls-files --stage -- new.link)
[[ $link_mode == 120000 && $link_blob == "$link_blob_before" ]] ||
  fail 'candidate-new-v1 symlink binding changed across staging'
[[ $(readlink -n -- "$repo/new.link" | sha256sum | hash_stream) == "$link_sha_before" ]] ||
  fail 'candidate-new-v1 symlink target drifted'

expected_paths=$'binary.bin\ndelete.txt\nmode.sh\nnew.link\nnew.txt\nold.txt\nrenamed.txt\ntext.txt'
staged_paths=$(git -C "$repo" diff --cached --name-only --no-renames HEAD)
[[ $staged_paths == "$expected_paths" ]] || fail 'approved staged path set did not match'
[[ -z $(git -C "$repo" diff --name-only -- "${tracked_paths[@]}" new.link new.txt renamed.txt) ]] ||
  fail 'an intended path retained unstaged drift'

git -C "$repo" add -- omitted.txt
[[ $(git -C "$repo" diff --cached --name-only --no-renames HEAD) != "$expected_paths" ]] ||
  fail 'staged path-set check missed an unintended path'

mode_repo="$TMP/mode-incapable"
init_repo "$mode_repo"
printf '#!/usr/bin/env bash\nexit 0\n' >"$mode_repo/tool.sh"
chmod 644 "$mode_repo/tool.sh"
git -C "$mode_repo" add -- tool.sh
git -C "$mode_repo" commit -qm base
git -C "$mode_repo" config core.fileMode false
chmod 755 "$mode_repo/tool.sh"
[[ $(git -C "$mode_repo" config --type=bool --get core.fileMode) == false ]] ||
  fail 'mode-incapable fixture did not report core.fileMode=false'
git -C "$mode_repo" diff --quiet HEAD -- tool.sh ||
  fail 'core.fileMode=false unexpectedly represented an intended mode change'

filter_repo="$TMP/filtered"
init_repo "$filter_repo"
printf '*.txt filter=uppercase\n' >"$filter_repo/.gitattributes"
git -C "$filter_repo" config filter.uppercase.clean 'tr a-z A-Z'
git -C "$filter_repo" config filter.uppercase.smudge cat
git -C "$filter_repo" add -- .gitattributes
git -C "$filter_repo" commit -qm base
printf 'filtered content\n' >"$filter_repo/new.txt"
[[ $(git -C "$filter_repo" check-attr filter -- new.txt) == *': uppercase' ]] ||
  fail 'active content conversion was not detected'
[[ $(git -C "$filter_repo" hash-object --path=new.txt -- new.txt) != \
  $(git -C "$filter_repo" hash-object --no-filters -- new.txt) ]] ||
  fail 'active content conversion did not alter the would-be staged blob'

gitlink_repo="$TMP/gitlink-parent"
init_repo "$gitlink_repo"
printf 'parent\n' >"$gitlink_repo/parent.txt"
git -C "$gitlink_repo" add -- parent.txt
git -C "$gitlink_repo" commit -qm base
init_repo "$gitlink_repo/nested"
printf 'nested\n' >"$gitlink_repo/nested/file.txt"
git -C "$gitlink_repo/nested" add -- file.txt
git -C "$gitlink_repo/nested" commit -qm base
git -C "$gitlink_repo" add -- nested 2>/dev/null
read -r gitlink_mode _ < <(git -C "$gitlink_repo" ls-files --stage -- nested)
[[ $gitlink_mode == 160000 ]] || fail 'unsupported gitlink fixture was not detected'

printf 'ok: commit candidates remain concise and fingerprint-bound\n'
