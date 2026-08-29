#!/bin/bash
# spar-handoff-approve.sh - PreToolUse validator for spar handoff writes.
# For every matched call it emits exactly one decision:
#   allow - the target sits directly inside a validated spar handoff directory
#           (/var/tmp/spar-<UUID>, non-symlink, mode 700, owner-owned, resolving
#           to itself), the basename is flat and not sensitive-shaped
#           (payload-scanner classes), and an existing target is a regular,
#           owner-owned file with hard-link count 1 (hard-link aliases refused);
#   deny  - a spar-shaped target fails one of those checks;
#   defer - every other file target follows the configured permission mode;
#   exit 2 (block) - the gate cannot decide (missing dependencies or input),
#           failing closed rather than silently skipping validation.
# Pinned sensitive-path deny rules override hook decisions in every case.
# Non-file tools reaching this hook are ignored (silent exit 0).

HANDOFF_RE='^/var/tmp/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
HANDOFF_TREE_RE='^/var/tmp/spar-[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}(/|$)'

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}

gate_error() {
  echo "spar-handoff-approve: $1; blocking (fail closed)" >&2
  exit 2
}

path_traverses_handoff() {
  local path=$1 cursor=/ part resolved
  local -a parts
  IFS=/ read -r -a parts <<<"$path"
  for part in "${parts[@]}"; do
    [[ -n $part ]] || continue
    cursor="${cursor%/}/$part"
    resolved=$(realpath -e -- "$cursor" 2>/dev/null) || break
    [[ $resolved =~ $HANDOFF_TREE_RE ]] && return 0
  done
  return 1
}

for dependency in jq realpath stat; do
  command -v "$dependency" >/dev/null 2>&1 || gate_error "$dependency is required and missing"
done
input=$(cat 2>/dev/null) || gate_error "cannot read hook input"
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || gate_error "cannot parse hook input"
case $tool in
  Edit | Write | NotebookEdit) ;;
  *) exit 0 ;;
esac
target=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null) ||
  gate_error "cannot parse the tool input path"
[[ -n $target ]] || gate_error "tool input path is empty"
if [[ $target == /* ]]; then requested=$target; else requested="$PWD/$target"; fi
target=$(realpath -m -- "$requested" 2>/dev/null) || gate_error "cannot resolve the tool input path"
if path_traverses_handoff "$requested" && [[ ! $target =~ $HANDOFF_TREE_RE ]]; then
  emit deny "spar handoff target escapes through an alias"
fi
[[ $target == /var/tmp/spar-* ]] || emit defer "use the configured permission mode"

parent=${target%/*}
name=${target##*/}
[[ $parent =~ $HANDOFF_RE ]] || emit deny "invalid spar handoff parent"
[[ -n $name && $name != . && $name != .. ]] || emit deny "invalid spar handoff basename"
[[ ! -L $parent && -d $parent ]] || emit deny "unsafe spar handoff directory"
[[ $(realpath -e -- "$parent" 2>/dev/null) == "$parent" ]] || emit deny "spar handoff directory does not resolve to itself"
[[ $(stat -c '%u' -- "$parent" 2>/dev/null) == $(id -u) ]] || emit deny "spar handoff directory has the wrong owner"
[[ $(stat -c '%a' -- "$parent" 2>/dev/null) == 700 ]] || emit deny "spar handoff directory has the wrong mode"

case ${name,,} in
  reviewer-id | agents.md | agents.override.md | claude.md | claude.local.md | .git)
    emit deny "bridge-owned or reviewer-instruction handoff target" ;;
  .env | .env.* | .env-* | .env_* | .env~* | \
    .netrc | .netrc.* | .netrc-* | .netrc_* | .netrc~* | \
    .npmrc | .npmrc.* | .npmrc-* | .npmrc_* | .npmrc~* | \
    .pypirc | .pypirc.* | .pypirc-* | .pypirc_* | .pypirc~* | \
    *.key | *.key.* | *.key~* | *.key-* | *.key_* | \
    *.pem | *.pem.* | *.pem~* | *.pem-* | *.pem_* | \
    *.p12 | *.p12.* | *.p12~* | *.p12-* | *.p12_* | \
    *.pfx | *.pfx.* | *.pfx~* | *.pfx-* | *.pfx_* | \
    *credentials* | auth.json | auth.json.* | auth.json~* | auth.json-* | auth.json_* | \
    secret | secret.* | secret~* | secret-* | secret_* | \
    secrets | secrets.* | secrets~* | secrets-* | secrets_*)
    emit deny "sensitive-shaped spar handoff target" ;;
esac

if [[ -e $target || -L $target ]]; then
  [[ -f $target && ! -L $target ]] || emit deny "unsafe spar handoff target type"
  [[ $(stat -c '%u' -- "$target" 2>/dev/null) == $(id -u) ]] || emit deny "spar handoff target has the wrong owner"
  [[ $(stat -c '%h' -- "$target" 2>/dev/null) == 1 ]] || emit deny "spar handoff target has hard links"
fi

emit allow "validated spar handoff scratch write"
