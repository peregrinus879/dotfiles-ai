#!/usr/bin/env bash
# Commit gate and publish scripts: the gate denies every commit-producing Git
# command a tool runs in any spelling, commit-apply is the only path and
# commits exactly the recorded candidate with the recorded identity or moves
# the branch back, publish-bind binds a fast-forward push to both ends, fails
# closed on a finding, quotes the repository path, and refuses destructive or
# destination-less pushes, and publish-verify confirms the destination after
# the push. The hook is also run exactly as each tool's configuration invokes
# it.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
export PATH="$ROOT/templates/hooks:$ROOT/agents/.agents/skills/commit/scripts:$ROOT/agents/.agents/skills/publish/scripts:$PATH"
export EYRAGENTS_RECORD_ROOT="$TMP/records"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" alias.ci commit
git config --file "$GIT_CONFIG_GLOBAL" alias.st status

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

payload() { # command -> hook JSON
  jq -cn --arg cwd "$repo" --arg command "$1" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}'
}
gate() { # command -> exit status of commit-gate
  if commit-gate <<<"$(payload "$1")" >/dev/null 2>&1; then echo 0; else echo $?; fi
}

repo="$TMP/re po/repo"
remote="$TMP/remote.git"
mkdir -p "$repo"
git init -q -b main "$repo"
git -C "$repo" config user.name Test
git -C "$repo" config user.email 1+test@users.noreply.github.com
cd "$repo"
printf 'one\n' >a.txt
git add a.txt
git commit -q -m 'chore: seed'
git init -q --bare "$remote"
git remote add origin "$remote"
git push -q -u origin main

# The gate: every spelling of a commit-producing command is denied, everything else passes.
# The literal dollar signs, backticks, and braces below are the point: they reach the gate unexpanded.
# shellcheck disable=SC2016
for denied in 'git commit -q -F -' 'git commit --dry-run; git commit -m x' 'command git commit -m x' \
  '/usr/bin/git commit -m x' 'GIT_DIR=.git git commit -m x' "bash -c 'git commit -m x'" 'git commit -am x' \
  "git -C '$repo' commit -q -F -" 'git -c user.email=x@y commit -m x' 'git --git-dir=.git commit -m x' \
  'cd elsewhere && git commit -m x' $'echo start\ngit commit --amend' 'make lint && git commit -q -F -' \
  'git ci -m x' 'git commit -- a.txt' 'eval "git commit -m x"' "git co''mmit -m x" 'git co""mmit -m x' \
  'git -c alias.x=commit x -m x' $'git \\\ncommit -m x' 'git co\mmit -m x' 'git cherry-pick abc' 'git merge topic' \
  'git pull' 'git rebase main' 'git revert HEAD' 'git am patch' 'git commit-tree HEAD^{tree}' \
  'git update-ref refs/heads/main abc' 'git merge --ff-only x && git commit -m y' 'git replace a b' \
  'git filter-branch --all' "git ch'e'rry-pick abc" 'git cherry\-pick abc' "git \$'cherry-pick' abc" \
  'sub=cherry-pick; git "$sub" abc' 'git $(printf commit) -m x' 'git `echo commit` -m x' 'git {commit,x} -m y' \
  '"$(git --exec-path)/git-commit" -m x' '/usr/lib/git-core/git-cherry-pick abc' 'git stash push' 'git stash' \
  'git notes add -m x' 'git fast-import <dump' "g''it commit -m x" 'gi\t commit -m x'; do
  [[ $(gate "$denied") == 2 ]] || fail "gate allowed: $denied"
done
# shellcheck disable=SC2016
for allowed in 'git status' 'git log --grep commit' 'commit-apply' 'git st' 'git merge --ff-only origin/main' \
  'git pull --ff-only' 'git fetch' 'git rev-parse HEAD^{commit}' 'git log --oneline' 'git stash list' \
  'git stash show -p' 'git write-tree' 'git diff --stat' 'echo "$commit"' 'git -C "$ROOT" diff --binary "$empty_tree" -- x' \
  'git diff --stat $ref' 'git -C "$ROOT" log -1 $sha' \
  $'grep -i -E x file && cat <<\'EOT\' >note\nthe gate denies any git\ncommit that differs\nEOT'; do
  [[ $(gate "$allowed") == 0 ]] || fail "gate denied: $allowed"
done

# The hook exactly as each tool's configuration invokes it, with the installed copy under a fake HOME.
fake_home="$TMP/home"
install -D -m 755 "$ROOT/templates/hooks/commit-gate" "$fake_home/.agents/hooks/commit-gate"
claude_hook=$(jq -r '[.hooks.PreToolUse[].hooks[] | select(.type == "command") | .command][0]' "$ROOT/claude-code/.claude/settings.json")
codex_hook=$(python3 -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); print(c["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$ROOT/templates/codex/config.toml")
for hook in "$claude_hook" "$codex_hook"; do
  if HOME=$fake_home sh -c "$hook" <<<"$(payload 'git commit -m x')" >/dev/null 2>&1; then fail "the configured hook did not deny: $hook"; fi
  HOME=$fake_home sh -c "$hook" <<<"$(payload 'git status')" >/dev/null 2>&1 || fail "the configured hook denied a plain command: $hook"
done
cp -- "$ROOT/opencode/.config/opencode/plugins/commit-gate.js" "$TMP/plugin.mjs"
# The template literal below is JavaScript, not shell.
# shellcheck disable=SC2016
HOME=$fake_home node --input-type=module -e '
const { CommitGate } = await import(process.argv[1]);
const hooks = await CommitGate({ directory: process.argv[2] });
const before = hooks["tool.execute.before"];
for (const command of ["git commit -m x", "git ci -m x", "git cherry-pick abc", "g''it commit -m x"]) {
  let denied = false;
  try { await before({ tool: "bash" }, { args: { command } }); } catch { denied = true; }
  if (!denied) { console.error(`plugin allowed: ${command}`); process.exit(1); }
}
await before({ tool: "bash" }, { args: { command: "git status" } });
await before({ tool: "read" }, { args: { filePath: "git commit" } });
' "$TMP/plugin.mjs" "$repo" || fail 'the OpenCode plugin did not enforce the gate'

# The candidate: message validation, index discipline, and the record.
trailer='Co-Authored-By: Test Model <noreply@anthropic.com>'
printf 'two\n' >b.txt
if printf 'Bad subject\n\n%s\n' "$trailer" | commit-candidate -- b.txt >/dev/null 2>&1; then fail 'candidate accepted a bad subject'; fi
if printf 'feat: no trailer\n' | commit-candidate -- b.txt >/dev/null 2>&1; then fail 'candidate accepted a message without the trailer'; fi
if printf 'feat: session\n\nClaude-Session: https://claude.ai/code/session_x\n\n%s\n' "$trailer" | commit-candidate -- b.txt >/dev/null 2>&1; then
  fail 'candidate accepted session metadata'
fi
[[ -z $(git diff --cached --name-only) ]] || fail 'a rejected message staged files'
# A symlink is its own index entry and is named by its own path, not its target's.
ln -s b.txt link.txt
printf 'feat: add link\n\n%s\n' "$trailer" | commit-candidate -- link.txt >/dev/null || fail 'candidate refused a symlink named by its own path'
[[ $(git diff --cached --name-only) == link.txt ]] || fail 'candidate staged something other than the link'
commit-candidate --clear >/dev/null
git reset -q link.txt
rm link.txt
message=$(printf 'feat: add b\n\n# A line that looks like a comment stays.\nBody line.\n\n%s' "$trailer")
out=$(printf '%s\n' "$message" | commit-candidate -- b.txt) || fail 'candidate failed'
grep -q '^tree=' <<<"$out" || fail 'candidate printed no tree'
grep -q '^scan: accepted' <<<"$out" || fail 'candidate did not report the scan'
printf 'three\n' >c.txt
git add c.txt
if printf '%s\n' "$message" | commit-candidate -- b.txt >/dev/null 2>&1; then fail 'candidate accepted an index with an unrelated staged change'; fi
git reset -q c.txt
rm c.txt

# commit-apply: drift, identity, verbatim message, consumption.
printf 'three\n' >c.txt
git add c.txt
if commit-apply >/dev/null 2>&1; then fail 'commit-apply committed a drifted index'; fi
git reset -q c.txt
rm c.txt
git config user.email 2+other@users.noreply.github.com
if commit-apply >/dev/null 2>&1; then fail 'commit-apply committed under a different identity'; fi
git config user.email 1+test@users.noreply.github.com
out=$(commit-apply) || fail 'commit-apply failed'
grep -q '^hash: ' <<<"$out" || fail 'commit-apply printed no hash'
[[ $(git log -1 --format=%s) == 'feat: add b' ]] || fail 'commit-apply committed the wrong subject'
[[ $(git log -1 --format=%B) == "$message" ]] || fail 'the committed message differs from the approved one'
[[ -z $(find "$EYRAGENTS_RECORD_ROOT" -name record) ]] || fail 'the record survived commit-apply'
if commit-apply >/dev/null 2>&1; then fail 'commit-apply committed without a record'; fi

# A deletion can be recorded twice: the second run finds the path gone from the
# worktree and the index, with HEAD still holding it.
rm b.txt
printf 'feat: drop b\n\n%s\n' "$trailer" | commit-candidate -- b.txt >/dev/null || fail 'candidate refused a deletion'
printf 'feat: drop b again\n\n%s\n' "$trailer" | commit-candidate -- b.txt >/dev/null || fail 'candidate could not re-record a staged deletion'
[[ $(git diff --cached --name-status) == $'D\tb.txt' ]] || fail 'the staged deletion changed on re-record'
commit-candidate --clear >/dev/null
git restore --staged b.txt
git restore b.txt

# A hook that changes the commit: the branch moves back and nothing is amended.
printf 'hooked\n' >hooked.txt
printf 'four\n' >d.txt
printf 'feat: add d\n\n%s\n' "$trailer" | commit-candidate -- d.txt >/dev/null || fail 'candidate for d failed'
before=$(git rev-parse HEAD)
printf '#!/bin/sh\ngit add hooked.txt\n' >.git/hooks/pre-commit
printf '#!/bin/sh\ngit checkout -q --detach HEAD\n' >.git/hooks/post-commit
chmod +x .git/hooks/pre-commit .git/hooks/post-commit
if commit-apply >/dev/null 2>"$TMP/apply.err"; then fail 'commit-apply accepted a commit a hook changed'; fi
grep -q 'was rejected' "$TMP/apply.err" || fail 'commit-apply did not report the rejection'
[[ $(git rev-parse HEAD) == "$before" ]] || fail 'the branch kept the rejected commit'
[[ $(git symbolic-ref -q HEAD) == refs/heads/main ]] || fail 'the session was left detached after the rejection'
[[ -n $(find "$EYRAGENTS_RECORD_ROOT" -name record.failed) ]] || fail 'the failed record was not kept'
rm -f .git/hooks/pre-commit .git/hooks/post-commit
git reset -q
rm -f hooked.txt d.txt

# publish-bind and publish-verify around a real push to a local bare remote.
out=$(publish-bind) || fail "publish-bind failed: $out"
head=$(git rev-parse HEAD)
base=$(git rev-parse origin/main)
command_line=$(grep -E '^git -C ' <<<"$out") || fail 'publish-bind printed no command'
grep -q -- "push origin $head:refs/heads/main --force-with-lease=refs/heads/main:$base" <<<"$command_line" || fail 'publish-bind printed the wrong command'
grep -q 're\\ po' <<<"$command_line" || fail 'publish-bind did not quote the repository path'
grep -q 'made through commit-apply\]' <<<"$out" || fail 'publish-bind did not recognize the commit-apply commit'
grep -q 'flat diff: accepted' <<<"$out" || fail 'publish-bind did not scan the flat diff'
out=$(publish-bind --remote origin --branch main) || fail 'publish-bind refused an explicit destination'
if publish-verify >/dev/null 2>&1; then fail 'publish-verify passed before the push'; fi
(cd / && eval "$command_line -q") || fail 'the printed command did not run from another directory'
out=$(publish-verify) || fail 'publish-verify failed after the push'
grep -q 'none defined' <<<"$out" || fail 'publish-verify did not report the missing published verification'
[[ -z $(find "$EYRAGENTS_RECORD_ROOT" -name publish) ]] || fail 'the binding survived publish-verify'
out=$(publish-bind) || fail 'publish-bind failed when up to date'
grep -q '^up to date' <<<"$out" || fail 'publish-bind did not report an up-to-date destination'

# A finding leaves no binding and no command.
printf 'five\n' >e.txt
git add e.txt
git -c user.email=someone@example.com commit -q -m 'chore: leak identity'
out=$(publish-bind 2>/dev/null || true)
grep -q 'IDENTITY' <<<"$out" || fail 'publish-bind did not report the identity finding'
if grep -q '^== command' <<<"$out"; then fail 'a finding still printed the command'; fi
[[ -z $(find "$EYRAGENTS_RECORD_ROOT" -name publish) ]] || fail 'a finding still recorded a binding'
if publish-bind >/dev/null 2>&1; then fail 'publish-bind bound a delta with an identity finding'; fi
git reset -q --hard HEAD~1

# Destructive and destination-less pushes.
git reset -q --hard HEAD~1
printf 'x\n' >f.txt
git add f.txt
git commit -q -m 'chore: diverge'
if publish-bind >/dev/null 2>&1; then fail 'publish-bind bound a destructive push'; fi
git checkout -q -b topic
if publish-bind >/dev/null 2>&1; then fail 'publish-bind bound a branch without an upstream'; fi

printf 'ok: commit gate denies every tool-run commit; commit-apply and the publish scripts hold to the record\n'
