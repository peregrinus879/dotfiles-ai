#!/bin/bash
# spar-handoff-approve.sh - PreToolUse gate for Edit|Write|NotebookEdit.
# This hook IS the per-file review gate: the settings ask list carries no bare
# Edit/Write/NotebookEdit entries, because a matching ask rule overrides a hook
# allow (live-verified; anthropics/claude-code#35136 documents rule-over-hook
# precedence). For every matched call it emits exactly one decision:
#   allow - the target sits directly inside a validated spar handoff directory
#           (/var/tmp/spar-<UUID>, non-symlink, mode 700, owner-owned, resolving
#           to itself), the basename is flat and not sensitive-shaped
#           (payload-scanner classes), and an existing target is a regular,
#           owner-owned file with hard-link count 1 (hard-link aliases refused);
#   ask   - every other file target, preserving deterministic per-file review;
#   exit 2 (block) - the gate cannot decide (missing dependencies or input),
#           failing closed rather than falling through to auto-mode defaults.
# Pinned sensitive-path deny rules override hook decisions in every case.
# Non-file tools reaching this hook are ignored (silent exit 0).

HANDOFF_RE='^/var/tmp/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}

gate_error() {
  echo "spar-handoff-approve: $1; blocking (fail closed)" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || gate_error "jq is required and missing"
command -v realpath >/dev/null 2>&1 || gate_error "realpath is required and missing"
command -v stat >/dev/null 2>&1 || gate_error "stat is required and missing"
input=$(cat 2>/dev/null) || gate_error "cannot read hook input"
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || gate_error "cannot parse hook input"
case $tool in
  Edit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac
target=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null) ||
  gate_error "cannot parse the tool input path"
[[ -n $target && $target == /var/tmp/spar-* ]] || emit ask "per-file review"

parent=${target%/*}
name=${target##*/}
[[ $parent =~ $HANDOFF_RE ]] || emit ask "per-file review"
[[ -n $name && $name != . && $name != .. ]] || emit ask "per-file review"
[[ ! -L $parent && -d $parent ]] || emit ask "per-file review"
[[ $(realpath -e -- "$parent" 2>/dev/null) == "$parent" ]] || emit ask "per-file review"
[[ $(stat -c '%u' -- "$parent" 2>/dev/null) == $(id -u) ]] || emit ask "per-file review"
[[ $(stat -c '%a' -- "$parent" 2>/dev/null) == 700 ]] || emit ask "per-file review"

case $name in
  .env | .env.* | *.key | *.pem | *credentials* | auth.json | secrets) emit ask "per-file review" ;;
esac

if [[ -e $target || -L $target ]]; then
  [[ -f $target && ! -L $target ]] || emit ask "per-file review"
  [[ $(stat -c '%u' -- "$target" 2>/dev/null) == $(id -u) ]] || emit ask "per-file review"
  [[ $(stat -c '%h' -- "$target" 2>/dev/null) == 1 ]] || emit ask "per-file review"
fi

emit allow "validated spar handoff scratch write"
