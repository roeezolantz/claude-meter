#!/usr/bin/env bash
set -f
input=$(cat)
[ -z "$input" ] && { echo "Claude"; exit 0; }
command -v jq >/dev/null || { echo "Claude [needs jq]"; exit 0; }

# Colors
C=$'\033[36m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' D=$'\033[2m' N=$'\033[0m' B=$'\033[1m'
SEP=$'\037'
NOW=$(date +%s)
S=" ${D}│${N} "

# ── Cache helpers ──
_cache_dir_ok() { [ -d "$1" ] && [ ! -L "$1" ] && [ -O "$1" ] && [ -w "$1" ]; }
_read_cache_record() {
  local line="$1" delim rest field; CACHE_FIELDS=()
  [[ "$line" == *"$SEP"* ]] && delim="$SEP" || delim='|'
  rest="$line"
  while [[ "$rest" == *"$delim"* ]]; do
    field=${rest%%"$delim"*}; CACHE_FIELDS+=("$field"); rest=${rest#*"$delim"}
  done
  CACHE_FIELDS+=("$rest")
}
_load_cache() {
  local path="$1" line=""; [ -f "$path" ] || return 1
  IFS= read -r line <"$path" || line=""; _read_cache_record "$line"
}
_write_cache() {
  local path="$1" tmp dir; shift; dir=${path%/*}
  tmp=$(mktemp "${dir}/cm-tmp-XXXXXX" 2>/dev/null || true); [ -n "$tmp" ] || return 1
  ( IFS="$SEP"; printf '%s\n' "$*" ) >"$tmp" && mv "$tmp" "$path"
}
_stale() { [ ! -f "$1" ] || [ $((NOW - $(stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0))) -gt "$2" ]; }
_minutes_until() {
  local epoch="$1" mins; [[ "$epoch" =~ ^[0-9]+$ ]] && ((epoch > 0)) || return
  mins=$(((epoch - NOW) / 60)); ((mins < 0)) && mins=0; printf '%s\n' "$mins"
}
_valid_quota() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$2" =~ ^[0-9]+$ ]] && [[ "$3" =~ ^[0-9]+$ ]] && [[ "$4" =~ ^[0-9]+$ ]] && (($3 > NOW && $4 > NOW))
}
_color_pct() {
  local u="$1"
  if [[ ! "$u" =~ ^[0-9]+$ ]]; then printf "%s" "$u"
  elif ((u >= 90)); then printf "${R}%d%%${N}" "$u"
  elif ((u >= 70)); then printf "${Y}%d%%${N}" "$u"
  else printf "${G}%d%%${N}" "$u"; fi
}
_fmt_countdown() {
  local rm="$1"; [[ "$rm" =~ ^[0-9]+$ ]] || return
  ((rm >= 1440)) && { printf " ${D}%dd${N}" $((rm / 1440)); return; }
  ((rm >= 60)) && { printf " ${D}%dh${N}" $((rm / 60)); return; }
  printf " ${D}%dm${N}" "$rm"
}

# Cache dir
_CD="" CACHE_OK=0
for _BASE in "${XDG_RUNTIME_DIR:-}" "${HOME}/.cache"; do
  [ -n "$_BASE" ] || continue
  _CAND="${_BASE%/}/claude-meter"
  [ -e "$_CAND" ] || mkdir -p -m 700 "$_CAND" 2>/dev/null || continue
  _cache_dir_ok "$_CAND" || continue; _CD="$_CAND"; CACHE_OK=1; break
done
QC=""; [[ "$CACHE_OK" == "1" ]] && QC="${_CD}/quota"

# ── Parse stdin JSON ──
HAS_RL=0
IFS=$'\t' read -r MODEL DIR PCT CTX COST EFF HAS_RL U5 U7 R5 R7 DUR_MS < <(
  jq -r --slurpfile cfg <(cat ~/.claude/settings.json 2>/dev/null || echo '{}') \
    '[(.model.display_name//"?"),(.workspace.project_dir//"."),
    (.context_window.used_percentage//0|floor),(.context_window.context_window_size//0),
    (.cost.total_cost_usd//0),
    ($cfg[0].effortLevel//"default"),
    (if .rate_limits then 1 else 0 end),
    (.rate_limits.five_hour.used_percentage//null|if type=="number" then floor else "--" end),
    (.rate_limits.seven_day.used_percentage//null|if type=="number" then floor else "--" end),
    (.rate_limits.five_hour.resets_at//0),
    (.rate_limits.seven_day.resets_at//0),
    (.cost.total_duration_ms//0|floor)]|@tsv' <<<"$input"
)

# ══════════════════════════════════════
# COL 1: MODEL / PROGRESS BAR
# ══════════════════════════════════════
case "${EFF:-default}" in low) EF='◌';; high) EF='◎';; xhigh) EF='◉';; max) EF='●';; *) EF='○';; esac
if ((CTX >= 1000000)); then CL="$((CTX / 1000000))M"
elif ((CTX > 0)); then CL="$((CTX / 1000))K"
else CL=""; fi
MODEL=${MODEL/ context)/)}
[[ "$CTX" -gt 0 && "$MODEL" != *"("* ]] && MODEL="${MODEL} (${CL})"
_ML="${MODEL} ${EF}"; ((${#_ML} > 22)) && MODEL="${MODEL:0:$((22 - 2 - ${#EF}))}…"

COL1_TOP="${C}${MODEL} ${EF}${N}"

F=$((PCT / 10)); ((F < 0)) && F=0; ((F > 10)) && F=10
if ((PCT >= 90)); then BC=$R; elif ((PCT >= 70)); then BC=$Y; else BC=$G; fi
BAR=""; for ((i=0;i<F;i++)); do BAR+='█'; done; for ((i=F;i<10;i++)); do BAR+='░'; done
COL1_BOT="${BC}${BAR}${N} ${PCT}%"

# ══════════════════════════════════════
# COL 2: SESSION DURATION + COST / RATE LIMITS
# ══════════════════════════════════════
DUR_S=$((DUR_MS / 1000))
if ((DUR_S >= 3600)); then DUR_FMT="$((DUR_S / 3600))h$((DUR_S % 3600 / 60))m"
elif ((DUR_S >= 60)); then DUR_FMT="$((DUR_S / 60))m"
else DUR_FMT="${DUR_S}s"; fi

printf -v COST_FMT "\$%.2f" "$COST" 2>/dev/null || COST_FMT="\$0.00"
RATE_FMT=""
if ((DUR_S > 60)); then
  RATE=$(echo "$COST $DUR_S" | awk '{printf "%.2f", $1 / $2 * 3600}')
  [[ "$RATE" != "0.00" ]] && RATE_FMT=" ${D}(${N}\$${RATE}/hr${D})${N}"
fi

COL2_TOP="${D}⏱${N} ${DUR_FMT}  ${COST_FMT}${RATE_FMT}"

# Rate limits
SHOW_COST=0
if [[ "$HAS_RL" == "1" ]]; then
  RM5=$(_minutes_until "$R5"); RM7=$(_minutes_until "$R7")
  [[ -n "$QC" ]] && _valid_quota "$U5" "$U7" "$R5" "$R7" && {
    if [ -f "$QC" ] && _load_cache "$QC"; then
      [[ "${CACHE_FIELDS[0]:-}" == "$U5" && "${CACHE_FIELDS[1]:-}" == "$U7" && "${CACHE_FIELDS[2]:-}" == "$R5" && "${CACHE_FIELDS[3]:-}" == "$R7" ]] || _write_cache "$QC" "$U5" "$U7" "$R5" "$R7"
    else _write_cache "$QC" "$U5" "$U7" "$R5" "$R7"; fi
  }
else
  U5="--" U7="--" RM5="" RM7="" SHOW_COST=1
  if [[ -n "$QC" ]] && _load_cache "$QC"; then
    _valid_quota "${CACHE_FIELDS[0]:-}" "${CACHE_FIELDS[1]:-}" "${CACHE_FIELDS[2]:-}" "${CACHE_FIELDS[3]:-}" && {
      U5="${CACHE_FIELDS[0]}"; U7="${CACHE_FIELDS[1]}"; R5="${CACHE_FIELDS[2]}"; R7="${CACHE_FIELDS[3]}"
      RM5=$(_minutes_until "$R5"); RM7=$(_minutes_until "$R7"); SHOW_COST=0
    }
  fi
fi
COL2_BOT="5h $(_color_pct "$U5")$(_fmt_countdown "$RM5")  7d $(_color_pct "$U7")$(_fmt_countdown "$RM7")"

# ══════════════════════════════════════
# COL 3: USER PROFILE / CURRENT DIR (last 2 folders)
# ══════════════════════════════════════
UNAME="${USER:-$(whoami 2>/dev/null || echo '?')}"
COL3_TOP="${B}${UNAME}${N}"

# Last 2 path components
DIR_SHORT="${DIR%/}"
_P="${DIR_SHORT%/*}"; _LAST="${DIR_SHORT##*/}"
_PARENT="${_P##*/}"
[ -n "$_PARENT" ] && DIR_SHORT="${_PARENT}/${_LAST}" || DIR_SHORT="$_LAST"
((${#DIR_SHORT} > 30)) && DIR_SHORT="…${DIR_SHORT: -29}"
COL3_BOT="${D}${DIR_SHORT}${N}"

# ══════════════════════════════════════
# COL 4: GIT BRANCH / WORKTREE
# ══════════════════════════════════════
_git_info() {
  BR="" AHEAD=0 BEHIND=0 STASH=0 GIT_STATE="" FC=0 AD=0 DL=0
  git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  BR=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null)
  local upstream
  upstream=$(git -C "$DIR" --no-optional-locks rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || upstream=""
  if [ -n "$upstream" ]; then
    local ab; ab=$(git -C "$DIR" --no-optional-locks rev-list --left-right --count HEAD..."$upstream" 2>/dev/null)
    [ -n "$ab" ] && { AHEAD=${ab%%$'\t'*}; BEHIND=${ab##*$'\t'}; }
  fi
  STASH=$(git -C "$DIR" --no-optional-locks stash list 2>/dev/null | wc -l | tr -d ' ')
  while IFS=$'\t' read -r a d _; do
    [[ "$a" =~ ^[0-9]+$ ]] || continue; FC=$((FC + 1)); AD=$((AD + a)); DL=$((DL + d))
  done < <(git -C "$DIR" --no-optional-locks diff HEAD --numstat 2>/dev/null)
  local gitdir; gitdir=$(git -C "$DIR" rev-parse --git-dir 2>/dev/null)
  if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then GIT_STATE="REBASING"
  elif [ -f "$gitdir/MERGE_HEAD" ]; then GIT_STATE="MERGING"
  elif [ -f "$gitdir/CHERRY_PICK_HEAD" ]; then GIT_STATE="CHERRY-PICK"
  fi
}

BR="" AHEAD=0 BEHIND=0 STASH=0 GIT_STATE="" FC=0 AD=0 DL=0
if [[ "$CACHE_OK" == "1" ]]; then
  GC="${_CD}/git-$(printf '%s' "$DIR" | { shasum 2>/dev/null || sha1sum; } | cut -c1-16)"
  if _stale "$GC" 5; then
    if _git_info; then
      _write_cache "$GC" "$BR" "$AHEAD" "$BEHIND" "$STASH" "$GIT_STATE" "$FC" "$AD" "$DL"
    else
      _write_cache "$GC" "" "" "" "" "" "" "" ""
    fi
  elif _load_cache "$GC"; then
    BR=${CACHE_FIELDS[0]:-}; AHEAD=${CACHE_FIELDS[1]:-}; BEHIND=${CACHE_FIELDS[2]:-}
    STASH=${CACHE_FIELDS[3]:-}; GIT_STATE=${CACHE_FIELDS[4]:-}
    FC=${CACHE_FIELDS[5]:-}; AD=${CACHE_FIELDS[6]:-}; DL=${CACHE_FIELDS[7]:-}
  fi
  [[ "$AHEAD" =~ ^[0-9]+$ ]] || AHEAD=0; [[ "$BEHIND" =~ ^[0-9]+$ ]] || BEHIND=0
  [[ "$STASH" =~ ^[0-9]+$ ]] || STASH=0
  [[ "$FC" =~ ^[0-9]+$ ]] || FC=0; [[ "$AD" =~ ^[0-9]+$ ]] || AD=0; [[ "$DL" =~ ^[0-9]+$ ]] || DL=0
else
  _git_info || true
fi

# PR status (cached 60s, network call)
PR_NUM="" PR_URL=""
if [ -n "$BR" ] && command -v gh >/dev/null 2>&1; then
  if [[ "$CACHE_OK" == "1" ]]; then
    PC="${_CD}/pr-$(printf '%s' "${DIR}:${BR}" | { shasum 2>/dev/null || sha1sum; } | cut -c1-16)"
    if _stale "$PC" 60; then
      _pr_json=$(gh pr view --json number,url --jq '[.number,.url]|@tsv' 2>/dev/null) || _pr_json=""
      if [ -n "$_pr_json" ]; then
        IFS=$'\t' read -r PR_NUM PR_URL <<<"$_pr_json"
        _write_cache "$PC" "$PR_NUM" "$PR_URL"
      else
        _write_cache "$PC" "" ""
      fi
    elif _load_cache "$PC"; then
      PR_NUM=${CACHE_FIELDS[0]:-}; PR_URL=${CACHE_FIELDS[1]:-}
    fi
  else
    _pr_json=$(gh pr view --json number,url --jq '[.number,.url]|@tsv' 2>/dev/null) || _pr_json=""
    [ -n "$_pr_json" ] && IFS=$'\t' read -r PR_NUM PR_URL <<<"$_pr_json"
  fi
fi

# Top: branch + PR + ahead/behind + state
COL4_TOP=""
if [ -n "$BR" ]; then
  ((${#BR} > 25)) && BR="${BR:0:25}…"
  COL4_TOP="${C}${BR}${N}"
  if [ -n "$PR_NUM" ]; then
    COL4_TOP+=" ${G}"$'\033]8;;'"${PR_URL}"$'\033\\'"PR #${PR_NUM}"$'\033]8;;\033\\'"${N}"
  fi
  ((AHEAD > 0)) && COL4_TOP+=" ${G}↑${AHEAD}${N}"
  ((BEHIND > 0)) && COL4_TOP+=" ${R}${B}⬇ PULL (${BEHIND})${N}"
  ((STASH > 0)) && COL4_TOP+=" ${D}≡${STASH}${N}"
  [ -n "$GIT_STATE" ] && COL4_TOP+=" ${R}${B}${GIT_STATE}${N}"
else
  COL4_TOP="${D}no repo${N}"
fi

# Bottom: worktree name or diff stats
IS_WT=0 WT_NAME=""
if [[ "${DIR/#$HOME/\~}" =~ /([^/]+)/\.claude/worktrees/([^/]+) ]]; then
  IS_WT=1; WT_NAME="${BASH_REMATCH[2]}"
fi

COL4_BOT=""
if [[ "$IS_WT" == "1" ]] && [ -n "$WT_NAME" ]; then
  COL4_BOT="${Y}⎇ ${WT_NAME}${N}"
else
  if ((FC > 0)) 2>/dev/null; then
    COL4_BOT="${FC}f ${G}+${AD}${N} ${R}-${DL}${N}"
  else
    COL4_BOT="${D}clean${N}"
  fi
fi

# ══════════════════════════════════════
# OUTPUT — pad columns so │ separators align
# ══════════════════════════════════════
# Strip ANSI codes to measure visible width
_vlen() { local s; s=$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'); printf '%s' "${#s}"; }

# Pad a string with trailing spaces to reach target visible width
_pad() {
  local str="$1" target="$2"
  local vl; vl=$(_vlen "$str")
  local diff=$((target - vl))
  if ((diff > 0)); then
    printf '%s%*s' "$str" "$diff" ""
  else
    printf '%s' "$str"
  fi
}

# Compute max visible width per column
_v1t=$(_vlen "$COL1_TOP"); _v1b=$(_vlen "$COL1_BOT"); ((_v1t>_v1b)) && W1=$_v1t || W1=$_v1b
_v2t=$(_vlen "$COL2_TOP"); _v2b=$(_vlen "$COL2_BOT"); ((_v2t>_v2b)) && W2=$_v2t || W2=$_v2b
_v3t=$(_vlen "$COL3_TOP"); _v3b=$(_vlen "$COL3_BOT"); ((_v3t>_v3b)) && W3=$_v3t || W3=$_v3b

printf '%s\n' "$(_pad "$COL1_TOP" "$W1")${S}$(_pad "$COL2_TOP" "$W2")${S}$(_pad "$COL3_TOP" "$W3")${S}${COL4_TOP}"
printf '%s\n' "$(_pad "$COL1_BOT" "$W1")${S}$(_pad "$COL2_BOT" "$W2")${S}$(_pad "$COL3_BOT" "$W3")${S}${COL4_BOT}"
