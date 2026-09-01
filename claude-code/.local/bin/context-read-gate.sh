#!/bin/bash
# Validate explicitly requested external reads before product approval.
set -euo pipefail

MAX_DIRECTORY_ENTRIES=128
MAX_DIRECTORY_DEPTH=8
MAX_NAME_BYTES=1024

emit() {
  local decision=$1 reason=$2
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
    "$decision" "$reason"
  exit 0
}

deny() { emit deny "$1"; }

gate_error() {
  printf 'context-read-gate: %s; blocking (fail closed)\n' "$1" >&2
  exit 2
}

is_contained() {
  local root=${1%/} target=$2
  [[ $target == "$root" || $target == "$root/"* ]]
}

is_sensitive_component() {
  local name=${1,,}
  case $name in
    .git | \
      .env | .env.* | .env-* | .env_* | .env~* | \
      .netrc | .netrc.* | .netrc-* | .netrc_* | .netrc~* | \
      .npmrc | .npmrc.* | .npmrc-* | .npmrc_* | .npmrc~* | \
      .pypirc | .pypirc.* | .pypirc-* | .pypirc_* | .pypirc~* | \
      auth.json | auth.json.* | auth.json-* | auth.json_* | auth.json~* | \
      secret | secret.* | secret-* | secret_* | secret~* | \
      secrets | secrets.* | secrets-* | secrets_* | secrets~* | \
      *.key | *.key.* | *.key-* | *.key_* | *.key~* | \
      *.pem | *.pem.* | *.pem-* | *.pem_* | *.pem~* | \
      *.p12 | *.p12.* | *.p12-* | *.p12_* | *.p12~* | \
      *.pfx | *.pfx.* | *.pfx-* | *.pfx_* | *.pfx~* | \
      id_rsa | id_rsa.* | id_rsa-* | id_rsa_* | id_rsa~* | \
      id_dsa | id_dsa.* | id_dsa-* | id_dsa_* | id_dsa~* | \
      id_ecdsa | id_ecdsa.* | id_ecdsa-* | id_ecdsa_* | id_ecdsa~* | \
      id_ed25519 | id_ed25519.* | id_ed25519-* | id_ed25519_* | id_ed25519~* | \
      *credentials*)
      return 0 ;;
  esac
  return 1
}

validate_components() {
  local value=$1 component
  local -a components
  IFS=/ read -r -a components <<<"${value#/}"
  for component in "${components[@]}"; do
    [[ -n $component ]] || continue
    (( ${#component} <= MAX_NAME_BYTES )) || deny "external context path component is too long"
    [[ ! $component =~ [[:cntrl:]] ]] || deny "external context path contains a control character"
    [[ $component != *\\* && $component != *\"* && $component != *\'* ]] ||
      deny "external context path contains an unsupported character"
    [[ $component != *\** && $component != *\?* && $component != *\[* && $component != *\]* &&
      $component != *\{* && $component != *\}* ]] ||
      deny "external context path contains a glob character"
    is_sensitive_component "$component" && deny "external context path is sensitive-shaped"
  done
  return 0
}

validate_known_roots() {
  local target=$1 root
  [[ -n ${HOME:-} ]] || gate_error "HOME is unavailable"
  [[ ! $target =~ ^/var/tmp/spar-[^/]+(/|$) ]] ||
    deny "external context path is a managed spar handoff"
  for root in \
    /dev /proc /run /sys \
    "$HOME/.aws" "$HOME/.config/gh" "$HOME/.docker" "$HOME/.gnupg" "$HOME/.kube" "$HOME/.ssh"; do
    is_contained "$root" "$target" && deny "external context path is protected"
  done
  return 0
}

scan_directory() {
  local root=$1 relative kind links depth separators count=0 completed=0
  while IFS= read -r -d '' relative &&
    IFS= read -r -d '' kind &&
    IFS= read -r -d '' links; do
    if [[ -z $relative && -z $kind && -z $links ]]; then
      completed=1
      break
    fi
    ((count += 1))
    (( count <= MAX_DIRECTORY_ENTRIES )) || deny "external context directory exceeds the entry bound"
    separators=${relative//[^\/]/}
    depth=$(( ${#separators} + 1 ))
    (( depth <= MAX_DIRECTORY_DEPTH )) || deny "external context directory exceeds the depth bound"
    validate_components "$relative"
    case $kind in
      d) ;;
      f) [[ $links == 1 ]] || deny "external context directory contains a hard-linked file" ;;
      l) deny "external context directory contains a symlink" ;;
      *) deny "external context directory contains an unsupported entry type" ;;
    esac
  done < <(find "$root" -mindepth 1 -printf '%P\0%y\0%n\0' && printf '\0\0\0')
  (( completed == 1 )) || gate_error "directory metadata scan failed"
}

validate_external_target() {
  local requested=$1 normalized canonical links
  [[ $requested == /* ]] || deny "external context target must be absolute"
  normalized=$(realpath -m -- "$requested" 2>/dev/null) || gate_error "cannot normalize external context target"
  [[ $normalized == "$requested" ]] || deny "external context target must use its normalized spelling"
  validate_components "$normalized"
  validate_known_roots "$normalized"
  [[ -e $normalized || -L $normalized ]] || deny "external context target does not exist"
  canonical=$(realpath -e -- "$normalized" 2>/dev/null) || gate_error "cannot resolve external context target"
  [[ $canonical == "$normalized" ]] || deny "external context target traverses a symlink"
  validate_components "$canonical"
  validate_known_roots "$canonical"

  if [[ -f $canonical && ! -L $canonical ]]; then
    links=$(stat -c '%h' -- "$canonical" 2>/dev/null) || gate_error "cannot inspect external context file"
    [[ $links == 1 ]] || deny "external context file has hard links"
  elif [[ -d $canonical && ! -L $canonical ]]; then
    scan_directory "$canonical"
  else
    deny "external context target must be a regular file or directory"
  fi
  VALIDATED_TARGET=$canonical
}

for dependency in find jq realpath stat; do
  command -v "$dependency" >/dev/null 2>&1 || gate_error "$dependency is required and missing"
done

input=$(cat 2>/dev/null) || gate_error "cannot read hook input"
tool=$(jq -er '.tool_name | select(type == "string" and length > 0)' <<<"$input" 2>/dev/null) ||
  gate_error "cannot parse hook tool name"

case $tool in
  Read | Grep | Glob)
    cwd=$(jq -er '.cwd | select(type == "string" and startswith("/"))' <<<"$input" 2>/dev/null) ||
      gate_error "Claude hook cwd is invalid"
    cwd=$(realpath -e -- "$cwd" 2>/dev/null) || gate_error "Claude hook cwd cannot be resolved"
    target=$(jq -er '
      if .tool_name == "Read" then .tool_input.file_path
      else (.tool_input.path // .cwd)
      end | select(type == "string" and length > 0)
    ' <<<"$input" 2>/dev/null) || gate_error "Claude read target is invalid"
    [[ $target == /* ]] || target="$cwd/$target"
    normalized=$(realpath -m -- "$target" 2>/dev/null) || gate_error "Claude read target cannot be normalized"
    if [[ -e $normalized || -L $normalized ]]; then
      resolved=$(realpath -e -- "$normalized" 2>/dev/null) || gate_error "Claude read target cannot be resolved"
      is_contained "$cwd" "$resolved" && exit 0
    elif is_contained "$cwd" "$normalized"; then
      exit 0
    fi
    validate_external_target "$normalized"
    emit ask "explicit external context read requires one-call approval"
    ;;
  request_permissions)
    if jq -e '(.agent_id // .agent_type // .tool_input.agent_id // null) != null' <<<"$input" >/dev/null 2>&1; then
      deny "subagents cannot request external context"
    fi
    jq -e '
      (.tool_input | type == "object") and
      ((.tool_input | keys - ["permissions", "reason"]) | length == 0) and
      (.tool_input.reason | type == "string" and length > 0) and
      (.tool_input.permissions | type == "object") and
      ((.tool_input.permissions | keys) == ["file_system"]) and
      (.tool_input.permissions.file_system | type == "object") and
      ((.tool_input.permissions.file_system | keys - ["read", "write"]) | length == 0) and
      (.tool_input.permissions.file_system.read | type == "array" and length == 1) and
      (.tool_input.permissions.file_system.read[0] | type == "string" and startswith("/")) and
      ((.tool_input.permissions.file_system.write // []) | type == "array" and length == 0)
    ' <<<"$input" >/dev/null 2>&1 || deny "request_permissions must request one exact filesystem read only"
    cwd=$(jq -er '.cwd | select(type == "string" and startswith("/"))' <<<"$input" 2>/dev/null) ||
      gate_error "Codex hook cwd is invalid"
    cwd=$(realpath -e -- "$cwd" 2>/dev/null) || gate_error "Codex hook cwd cannot be resolved"
    target=$(jq -er '.tool_input.permissions.file_system.read[0]' <<<"$input" 2>/dev/null) ||
      gate_error "Codex read target is invalid"
    validate_external_target "$target"
    target=$VALIDATED_TARGET
    is_contained "$cwd" "$target" && deny "workspace paths do not require external context grants"
    exit 0
    ;;
  *) exit 0 ;;
esac
