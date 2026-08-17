#!/usr/bin/env bash
# Claude Code status line
# Docs: https://code.claude.com/docs/en/statusline
#
# Design conventions:
# - Every segment must earn its place. No burn rate ($/hr); show extra-usage
#   spend only, cumulative. No duration segment.
# - No redundant indicators when the tool already surfaces the information natively.
# - Consistent label:value pattern (e.g., 5h:35%, 5h:52m, 7d:24h 0m).
# - Space separators between segments, not special characters.
# - Colors pin the Omarchy gruvbox palette as truecolor, so rendering does not
#   depend on the terminal's ANSI palette; re-pin when the theme changes.
# - Runtime state uses hashed keys in one owner-only directory. Existing state
#   must be a regular, owner-only, single-link file; updates replace atomically.
# - Intentionally no Bash strict mode, and [ ] guards throughout: parse failures
#   degrade to blank segments instead of killing the status line.

umask 077
input=$(cat)

# --- Parse JSON input (single jq call for performance) ---
readarray -t _f <<< "$(echo "$input" | jq -r '
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.context_window.used_percentage // ""),
  (.context_window.total_input_tokens // 0),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.cost.total_cost_usd // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.resets_at // ""),
  (.session_id // "")
')"
for i in "${!_f[@]}"; do _f[$i]="${_f[$i]%$'\r'}"; done
cwd="${_f[0]}" model="${_f[1]}" used_pct="${_f[2]}" ctx_tokens="${_f[3]}"
rate_5h="${_f[4]}" rate_7d="${_f[5]}" cost_usd="${_f[6]}"

# Round the rate percentages once; empty stands for absent or null.
rate_5h_int="" rate_7d_int=""
[ -n "$rate_5h" ] && rate_5h_int=$(printf '%.0f' "$rate_5h" 2>/dev/null)
[ -n "$rate_7d" ] && rate_7d_int=$(printf '%.0f' "$rate_7d" 2>/dev/null)
reset_5h="${_f[7]}" reset_7d="${_f[8]}" session_id="${_f[9]}"

# --- Colors: Omarchy gruvbox palette (themes/gruvbox/colors.toml), truecolor ---
dim='\033[38;2;124;111;100m'          # dark_foreground #7c6f64
bold_cyan='\033[1;38;2;137;180;130m'  # cyan #89b482
italic_cyan='\033[3;38;2;137;180;130m'
yellow='\033[38;2;216;166;87m'        # yellow #d8a657
bold_yellow='\033[1;38;2;216;166;87m'
green='\033[38;2;169;182;101m'        # green #a9b665
red='\033[38;2;234;105;98m'           # red #ea6962
reset='\033[0m'

# --- Helpers ---

# Color by percentage threshold
pct_color() {
  local pct=${1:-0}
  if [ "$pct" -ge 90 ] 2>/dev/null; then echo "$red"
  elif [ "$pct" -ge 70 ] 2>/dev/null; then echo "$yellow"
  else echo "$green"
  fi
}

# Format tokens: 200000 -> 200k
fmt_k() {
  local n=${1:-0}
  [ "$n" -gt 0 ] 2>/dev/null || { echo ""; return; }
  echo "$((n / 1000))k"
}

# Format seconds remaining to countdown: Xh Ym or Xm
fmt_countdown() {
  local remaining=${1:-0}
  if [ "$remaining" -le 0 ] 2>/dev/null; then echo ""; return; fi
  local h=$((remaining / 3600))
  local m=$(( (remaining % 3600) / 60 ))
  if [ "$h" -gt 0 ] 2>/dev/null; then
    echo "${h}h ${m}m"
  else
    echo "${m}m"
  fi
}

# Initialize one private runtime-state directory. A malformed or pre-positioned
# path disables persistence; the status line still renders without cached state.
state_ready=0
state_root=""
state_uid=$(id -u 2>/dev/null)
state_base="/tmp"

# dir_private <path>: a real, non-symlink directory resolving to itself and
# owned by this uid with mode exactly 700.
dir_private() {
  local dir=$1 meta real
  meta=$(stat -c '%u:%a' -- "$dir" 2>/dev/null)
  real=$(realpath -e -- "$dir" 2>/dev/null)
  [ -d "$dir" ] && [ ! -L "$dir" ] && \
    [ "$real" = "$dir" ] && [ "$meta" = "${state_uid}:700" ]
}

if [ -n "${XDG_RUNTIME_DIR:-}" ] && dir_private "${XDG_RUNTIME_DIR%/}"; then
  state_base="${XDG_RUNTIME_DIR%/}"
fi
if [ -n "$state_uid" ]; then
  state_root="$state_base/claude-statusline-$state_uid"
  if [ ! -e "$state_root" ] && [ ! -L "$state_root" ]; then
    mkdir -m 700 -- "$state_root" 2>/dev/null
  fi
  dir_private "$state_root" && state_ready=1
fi

state_key() {
  local digest
  digest=$(printf '%s' "$1" | sha256sum 2>/dev/null)
  digest=${digest%% *}
  case "$digest" in
    *[!0-9a-f]*|"") return 1 ;;
    *) printf '%s' "$digest" ;;
  esac
}

state_file_safe() {
  local metadata
  [ "$state_ready" -eq 1 ] && [ -f "$1" ] && [ ! -L "$1" ] || return 1
  metadata=$(stat -c '%u:%a:%h' -- "$1" 2>/dev/null)
  [ "$metadata" = "${state_uid}:600:1" ]
}

write_state() {
  local target=$1 temp
  shift
  [ "$state_ready" -eq 1 ] || return 1
  if [ -e "$target" ] || [ -L "$target" ]; then
    state_file_safe "$target" || return 1
  fi
  temp=$(mktemp "$state_root/.state.XXXXXX") || return 1
  chmod 600 -- "$temp" 2>/dev/null || { rm -f -- "$temp"; return 1; }
  printf '%s\n' "$@" > "$temp" || { rm -f -- "$temp"; return 1; }
  mv -fT -- "$temp" "$target" 2>/dev/null || { rm -f -- "$temp"; return 1; }
}

# Render one rate-limit segment on stdout
# Args: label pct reset_epoch date_fmt
build_rate_seg() {
  local label=$1 pct=$2 epoch=$3 dfmt=$4
  local color value rtime_part=""

  [ -z "$pct" ] && return
  color=$(pct_color "$pct")

  if [ "$pct" -ge 100 ] 2>/dev/null && [ "${epoch:-0}" -gt 0 ] 2>/dev/null; then
    local countdown
    countdown=$(fmt_countdown "$((epoch - now))")
    value="${countdown:-${pct}%}"
  else
    value="${pct}%"
  fi

  if [ "${epoch:-0}" -gt "$now" ] 2>/dev/null; then
    local rtime
    rtime=$(date -d "@$epoch" +"$dfmt" 2>/dev/null)
    [ -n "$rtime" ] && rtime_part=" ${dim}@${rtime}${reset}"
  fi

  printf '%s' "${dim}${label}:${reset}${color}${value}${reset}${rtime_part}"
}

# --- Detect extra usage (5h OR 7d at 100%) ---
extra_usage=0
[ "$rate_5h_int" -ge 100 ] 2>/dev/null && extra_usage=1
[ "$extra_usage" -eq 0 ] && [ "$rate_7d_int" -ge 100 ] 2>/dev/null && extra_usage=1

# --- Git cache (docs: cache expensive operations) ---
git_cache=""
if [ "$state_ready" -eq 1 ]; then
  cwd_key=$(state_key "$cwd") && git_cache="$state_root/git-$cwd_key"
fi
git_cache_max_age=60
now=$(date +%s)

git_cache_stale() {
  [ -n "$git_cache" ] && state_file_safe "$git_cache" || return 0
  [ $((now - $(stat -c %Y "$git_cache" 2>/dev/null || echo 0))) -gt $git_cache_max_age ]
}

# --- Segments ---

# SSH hostname (shown only for remote sessions)
host_seg=""
if [ -n "$SSH_CONNECTION" ]; then
  host_seg="${bold_yellow}${HOSTNAME%%.*}${reset}"
fi

# Directory and Git branch (cached, refreshed every 60s)
branch=""
repo_root=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  if git_cache_stale; then
    branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
             || GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    repo_root=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$git_cache" ] && write_state "$git_cache" "$branch" "$repo_root"
  else
    { read -r branch; read -r repo_root; } < "$git_cache"
  fi
fi

# Directory: repo root + relative path inside git repos, last 2 components outside
if [ -n "$repo_root" ]; then
  repo_name="${repo_root##*/}"
  rel_path="${cwd#"$repo_root"}"
  rel_path="${rel_path#/}"
  if [ -n "$rel_path" ]; then
    short_cwd="${repo_name}/${rel_path}"
  else
    short_cwd="$repo_name"
  fi
else
  short_cwd="${cwd/#$HOME/\~}"
  IFS='/' read -ra parts <<< "$short_cwd"
  n=${#parts[@]}
  if [ "$n" -gt 2 ]; then
    short_cwd="…/${parts[$((n-2))]}/${parts[$((n-1))]}"
  fi
fi
dir_seg="${short_cwd:+${bold_cyan}${short_cwd}${reset}}"
branch_seg="${branch:+${italic_cyan}${branch}${reset}}"

# Model (strip "Claude " prefix if present)
short_model="${model#Claude }"
model_seg="${short_model:+${dim}${short_model}${reset}}"

# Context window: ctx:pct%(tokens); tokens come exact from the payload
# used_percentage can be null early in session before first API call.
ctx_seg=""
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct" 2>/dev/null)
  ctx_tok=$(fmt_k "$ctx_tokens")
  ctx_seg="${dim}ctx:${reset}$(pct_color "$used_int")${used_int}%${reset}${ctx_tok:+${dim}(${ctx_tok})${reset}}"
fi

# Rate limits: 5h and 7d (with reset countdown and local reset time)
rate5_seg=$(build_rate_seg "5h" "$rate_5h_int" "$reset_5h" "%H:%M")
rate7_seg=$(build_rate_seg "7d" "$rate_7d_int" "$reset_7d" "%a.%H:%M")

# Session cost (tracks only extra usage spend)
# State: line 1 = active|frozen, line 2 = baseline, line 3 = prior extra, line 4 = last displayed
extra_state=""
if [ "$state_ready" -eq 1 ] && [ -n "$session_id" ]; then
  session_key=$(state_key "$session_id") && extra_state="$state_root/extra-$session_key"
fi
_st="" _bl="" _pr="" _ld=""
extra_state_ok=0
if [ -n "$extra_state" ] && state_file_safe "$extra_state"; then
  { read -r _st; read -r _bl; read -r _pr; read -r _ld; } < "$extra_state"
  extra_state_ok=1
fi
cost_seg=""
if [ "$extra_usage" -eq 1 ] 2>/dev/null; then
  if [ "$extra_state_ok" -eq 1 ]; then
    if [ "$_st" = "frozen" ]; then
      # Re-entering extra usage: carry over frozen value, set new baseline
      _pr="${_ld:-0}"
      _bl="${cost_usd:-0}"
    fi
  else
    _bl="${cost_usd:-0}" _pr="0" _ld="0"
  fi
  if [ -n "$cost_usd" ]; then
    extra_cost=$(jq -n --argjson c "$cost_usd" --argjson b "${_bl:-0}" --argjson p "${_pr:-0}" '[$p + $c - $b, 0] | max' 2>/dev/null) || extra_cost=0
    [ -n "$extra_state" ] && write_state "$extra_state" "active" "$_bl" "$_pr" "$extra_cost"
    cost_seg="${yellow}$(printf '$%.2f' "$extra_cost")${reset}"
  fi
else
  if [ "$extra_state_ok" -eq 1 ]; then
    if [ "$_st" = "active" ]; then
      # Transition to frozen: use last displayed value, not recomputed
      write_state "$extra_state" "frozen" "0" "0" "${_ld:-0}"
    fi
    cost_seg="${dim}$(printf '$%.2f' "${_ld:-0}")${reset}"
  else
    cost_seg="${dim}\$0.00${reset}"
  fi
fi

# --- Output ---
line=""
for seg in "$host_seg" "$dir_seg" "$branch_seg" "$model_seg" "$ctx_seg" "$rate5_seg" "$rate7_seg" "$cost_seg"; do
  [ -n "$seg" ] && line+="${line:+  }${seg}"
done
printf '%b\n' "$line"
