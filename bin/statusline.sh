#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_epoch_time() {
    local epoch=$1
    local style=$2
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -j -r "$epoch" +"%l:%M%p" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%l:%M%P" 2>/dev/null)
            result=$(echo "$result" | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        datetime)
            result=$(date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null)
            result=$(echo "$result" | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]')
            ;;
        *)
            result=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%b %-d" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    printf "%s" "$result"
}

iso_to_epoch() {
    local iso_str="$1"

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

fmt_cost() {
    awk -v c="$1" 'BEGIN { if (c >= 100) printf "$%d", c; else printf "$%.2f", c }'
}

# ── Extract stdin (single jq pass) ─────────────────────
eval "$(echo "$input" | jq -r '@sh "
model_name=\(.model.display_name // "Claude")
size=\(.context_window.context_window_size // 200000)
stdin_ctx_pct=\(.context_window.used_percentage // "")
input_tokens=\(.context_window.current_usage.input_tokens // 0)
cache_create=\(.context_window.current_usage.cache_creation_input_tokens // 0)
cache_read=\(.context_window.current_usage.cache_read_input_tokens // 0)
cwd=\(.cwd // "")
session_start=\(.session.start_time // "")
session_cost=\(.cost.total_cost_usd // "")
lines_added=\(.cost.total_lines_added // "")
lines_removed=\(.cost.total_lines_removed // "")
effort=\(.effort.level // "")
stdin_five_pct=\(.rate_limits.five_hour.used_percentage // "")
five_hour_reset_epoch=\(.rate_limits.five_hour.resets_at // "")
stdin_seven_pct=\(.rate_limits.seven_day.used_percentage // "")
seven_day_reset_epoch=\(.rate_limits.seven_day.resets_at // "")
"' 2>/dev/null)"

# jq's @sh is all-or-nothing: on malformed stdin or an unexpected non-scalar
# field every variable above is left unset — re-establish safe defaults
model_name=${model_name:-Claude}
input_tokens=${input_tokens:-0}
cache_create=${cache_create:-0}
cache_read=${cache_read:-0}
[[ "$size" =~ ^[1-9][0-9]*$ ]] || size=200000

# rate-limit fields feed arithmetic and printf — keep them numeric.
# resets_at is an epoch today; tolerate an ISO timestamp if that ever changes.
[[ "$stdin_five_pct" =~ ^[0-9.]+$ ]] || stdin_five_pct=""
[[ "$stdin_seven_pct" =~ ^[0-9.]+$ ]] || stdin_seven_pct=""
if [ -n "$five_hour_reset_epoch" ] && ! [[ "$five_hour_reset_epoch" =~ ^[0-9]+$ ]]; then
    five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_epoch")
fi
if [ -n "$seven_day_reset_epoch" ] && ! [[ "$seven_day_reset_epoch" =~ ^[0-9]+$ ]]; then
    seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_epoch")
fi

if [ -n "$stdin_ctx_pct" ]; then
    pct_used=$(printf "%.0f" "$stdin_ctx_pct")
else
    current=$(( input_tokens + cache_create + cache_read ))
    pct_used=$(( current * 100 / size ))
fi

# effort from stdin; settings.json fallback (also read voice toggle in the same pass)
voice_on=false
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ]; then
    IFS=$'\t' read -r settings_effort voice_on <<< "$(jq -r '[(.effortLevel // "default"), (.voice.enabled // false)] | @tsv' "$settings_path" 2>/dev/null)"
fi
[ -z "$effort" ] && effort="${settings_effort:-default}"

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session · $ │ +/- │ Effort │ Toggles ──
pct_color=$(color_for_pct "$pct_used")
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
fi

session_duration=""
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    if [ -n "$start_epoch" ]; then
        now_epoch=$(date +%s)
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi

skip_perms=""
parent_cmd=$(ps -o args= -p "$PPID" 2>/dev/null)
if [[ "$parent_cmd" == *"--dangerously-skip-permissions"* ]]; then
    skip_perms="⚡  "
fi

line1="${blue}${model_name}${reset}"
line1+="${sep}"
line1+="✍️ ${pct_color}${pct_used}%${reset}"
line1+="${sep}"
line1+="${skip_perms}${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    line1+=" ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
fi
if [ -n "$session_duration" ]; then
    line1+="${sep}"
    line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
    if [ -n "$session_cost" ] && awk -v c="$session_cost" 'BEGIN{exit !(c > 0)}'; then
        line1+=" ${dim}·${reset} ${white}$(fmt_cost "$session_cost")${reset}"
    fi
fi
if [ -n "$lines_added$lines_removed" ] && [ "${lines_added:-0}${lines_removed:-0}" != "00" ]; then
    line1+="${sep}"
    line1+="${green}+${lines_added:-0}${reset}${dim}/${reset}${red}-${lines_removed:-0}${reset}"
fi
line1+="${sep}"
case "$effort" in
    max|xhigh|high) line1+="${magenta}● ${effort}${reset}" ;;
    medium)         line1+="${dim}◑ ${effort}${reset}" ;;
    low)            line1+="${dim}◔ ${effort}${reset}" ;;
    *)              line1+="${dim}◑ ${effort}${reset}" ;;
esac

# toggles: mic (voice mode on) and remote control (active bridge session)
mic_dot="${red}${dim}●${reset}"
[ "$voice_on" = "true" ] && mic_dot="${green}●${reset}"
remote_dot="${red}${dim}●${reset}"
[ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID}${CLAUDE_CODE_REMOTE_SESSION_ID}" ] && remote_dot="${green}●${reset}"
line1+="${sep}🎙${mic_dot} 🖥${remote_dot}"

# ── Rate limits from stdin (primary) ───────────────────
has_stdin_rates=false
five_hour_pct=""
seven_day_pct=""

if [ -n "$stdin_five_pct" ]; then
    has_stdin_rates=true
    five_hour_pct=$(printf "%.0f" "$stdin_five_pct")
    [ -n "$stdin_seven_pct" ] && seven_day_pct=$(printf "%.0f" "$stdin_seven_pct")
fi

# ── Fallback: API call (cached) ────────────────────────
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
mkdir -p /tmp/claude

usage_data=""
extra_enabled="false"

if ! $has_stdin_rates; then
    needs_refresh=true

    if [ -f "$cache_file" ]; then
        cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        now=$(date +%s)
        cache_age=$(( now - cache_mtime ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            needs_refresh=false
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if $needs_refresh; then
        token=""
        if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
            token="$CLAUDE_CODE_OAUTH_TOKEN"
        elif command -v security >/dev/null 2>&1; then
            blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            creds_file="${HOME}/.claude/.credentials.json"
            if [ -f "$creds_file" ]; then
                token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            if command -v secret-tool >/dev/null 2>&1; then
                blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
                if [ -n "$blob" ]; then
                    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                fi
            fi
        fi

        if [ -n "$token" ] && [ "$token" != "null" ]; then
            response=$(curl -s --max-time 5 \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "User-Agent: claude-code/2.1.34" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
                usage_data="$response"
                echo "$response" > "$cache_file"
            fi
        fi
        if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
        five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
        five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
        five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_iso")
        seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
        seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
        seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_iso")

        extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    fi
else
    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
            extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
        fi
    fi
fi

# ── Cost engine: $ per 5h block / day / week / month ───
# API-equivalent cost computed from ~/.claude/projects JSONLs (tokens × pricing),
# deduped by requestId, cached 60s. Windows align to official rate-limit resets.
block_cost="" day_cost="" week_cost="" month_cost="" burn_rate=""

now=$(date +%s)
block_start=$(( ${five_hour_reset_epoch:-0} > 0 ? five_hour_reset_epoch - 18000 : now - 18000 ))
week_start=$(( ${seven_day_reset_epoch:-0} > 0 ? seven_day_reset_epoch - 604800 : now - 604800 ))
day_start=$(date -d "today 00:00" +%s 2>/dev/null || date -j -f "%H:%M" "00:00" +%s 2>/dev/null)
month_start=$(date -d "$(date +%Y-%m-01) 00:00" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m)-01 00:00" +%s 2>/dev/null)
scan_cutoff=$(( week_start < month_start ? week_start : month_start ))

cost_cache="/tmp/claude/statusline-cost-cache"
cost_lock="/tmp/claude/statusline-cost.lock"

scan_costs() {
    # BSD find has no -newermt "@epoch"; stamp a reference file instead (POSIX -newer)
    local ref="${cost_cache}.ref"
    touch -d "@$scan_cutoff" "$ref" 2>/dev/null ||
        touch -t "$(date -j -r "$scan_cutoff" +%Y%m%d%H%M.%S 2>/dev/null)" "$ref" 2>/dev/null || return
    find "$HOME/.claude/projects" -name '*.jsonl' -newer "$ref" -print0 2>/dev/null |
    xargs -0 -r -n1 jq -rR '
        fromjson? |
        select(.type == "assistant" and .message.usage != null) |
        [ (try (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch 0),
          (.requestId // .uuid // ""),
          (.message.model // ""),
          (.message.usage.input_tokens // 0),
          (.message.usage.output_tokens // 0),
          (.message.usage.cache_creation.ephemeral_5m_input_tokens // .message.usage.cache_creation_input_tokens // 0),
          (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0),
          (.message.usage.cache_read_input_tokens // 0),
          (.costUSD // "") ] | @tsv' 2>/dev/null |
    awk -F'\t' -v bs="$block_start" -v ds="$day_start" -v ws="$week_start" -v ms="$month_start" '
        # ponytail: pattern-matched pricing table (per MTok), unknown models bill as opus
        function pin(m)  { if (m ~ /fable|mythos/) return 10; if (m ~ /haiku/) return 1; if (m ~ /sonnet/) return 3; return 5 }
        function pout(m) { if (m ~ /fable|mythos/) return 50; if (m ~ /haiku/) return 5; if (m ~ /sonnet/) return 15; return 25 }
        {
            if ($1 == 0 || $2 == "" || seen[$2]++) next
            ts = $1
            if ($9 != "") c = $9 + 0
            else c = ($4*pin($3) + $5*pout($3) + $6*1.25*pin($3) + $7*2*pin($3) + $8*0.1*pin($3)) / 1000000
            if (ts >= ms) month += c
            if (ts >= ws) week += c
            if (ts >= ds) day += c
            if (ts >= bs) { block += c; if (!bf || ts < bf) bf = ts; if (ts > bl) bl = ts }
        }
        END { printf "%.4f %.4f %.4f %.4f %d\n", block, day, week, month, (bl > bf ? (bl - bf) / 60 : 0) }'
}

cost_fresh=false
if [ -f "$cost_cache" ]; then
    cc_mtime=$(stat -c %Y "$cost_cache" 2>/dev/null || stat -f %m "$cost_cache" 2>/dev/null)
    [ $(( now - cc_mtime )) -lt 60 ] && cost_fresh=true
fi

if ! $cost_fresh; then
    # clear a lock abandoned by a killed run
    if [ -d "$cost_lock" ]; then
        lk_mtime=$(stat -c %Y "$cost_lock" 2>/dev/null || stat -f %m "$cost_lock" 2>/dev/null)
        [ $(( now - lk_mtime )) -gt 120 ] && rmdir "$cost_lock" 2>/dev/null
    fi
    if mkdir "$cost_lock" 2>/dev/null; then
        scan_costs > "${cost_cache}.tmp" && mv "${cost_cache}.tmp" "$cost_cache"
        rmdir "$cost_lock" 2>/dev/null
    fi
fi

if [ -f "$cost_cache" ]; then
    read -r block_cost day_cost week_cost month_cost block_elapsed_min < "$cost_cache"
fi

have_costs=false
if [ -n "$month_cost" ] && awk -v m="$month_cost" -v w="$week_cost" 'BEGIN{exit !(m > 0 || w > 0)}'; then
    have_costs=true
    if [ "${block_elapsed_min:-0}" -ge 5 ] && awk -v b="$block_cost" 'BEGIN{exit !(b > 0)}'; then
        burn_rate=$(awk -v b="$block_cost" -v e="$block_elapsed_min" 'BEGIN{printf "%.2f", b / e * 60}')
    fi
fi

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
bar_width=10

if [ -n "$five_hour_pct" ]; then
    five_hour_reset=$(format_epoch_time "$five_hour_reset_epoch" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
    five_hour_pct_color=$(color_for_pct "$five_hour_pct")
    five_hour_pct_fmt=$(printf "%3d" "$five_hour_pct")

    rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct_fmt}%${reset}"
    [ -n "$five_hour_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"
    if $have_costs; then
        rate_lines+=" ${dim}·${reset} ${white}$(fmt_cost "$block_cost")${reset}"
        [ -n "$burn_rate" ] && rate_lines+=" 🔥 ${white}\$${burn_rate}${reset}${dim}/hr${reset}"
    fi
fi

if [ -n "$seven_day_pct" ]; then
    seven_day_reset=$(format_epoch_time "$seven_day_reset_epoch" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
    seven_day_pct_color=$(color_for_pct "$seven_day_pct")
    seven_day_pct_fmt=$(printf "%3d" "$seven_day_pct")

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}weekly${reset}  ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct_fmt}%${reset}"
    [ -n "$seven_day_reset" ] && rate_lines+=" ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"
    $have_costs && rate_lines+=" ${dim}·${reset} ${white}$(fmt_cost "$week_cost")${reset}"
fi

if $have_costs; then
    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}month${reset}   ${white}$(fmt_cost "$month_cost")${reset} ${dim}api-equiv · today${reset} ${white}$(fmt_cost "$day_cost")${reset}"
fi

if [ "$extra_enabled" = "true" ] && [ -n "$usage_data" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")
    extra_pct_color=$(color_for_pct "$extra_pct")

    extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ -z "$extra_reset" ]; then
        extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    fi

    [ -n "$rate_lines" ] && rate_lines+="\n"
    rate_lines+="${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0
