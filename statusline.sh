#!/bin/bash

# Claude Code Statusline — Real-time usage, context, and git info
# https://github.com/educlopez/claude-statusline

# Read JSON input from stdin
input=$(cat)

# Extract information from JSON
model_name=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')

# Extract context window information
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
current_usage=$(echo "$input" | jq '.context_window.current_usage')

# Calculate context percentage
if [ "$current_usage" != "null" ]; then
    current_tokens=$(echo "$current_usage" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    context_percent=$((current_tokens * 100 / context_size))
else
    context_percent=0
fi

# Build context progress bar (15 chars wide)
bar_width=15
filled=$((context_percent * bar_width / 100))
empty=$((bar_width - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# Get directory name (basename)
dir_name=$(basename "$current_dir")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
MAGENTA='\033[0;95m'
NC='\033[0m' # No Color

# --- Usage/Quota fetch (cached) ---
usage_info=""
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Resolve ~ if present
config_dir="${config_dir/#\~/$HOME}"
cache_dir="$config_dir/.usage-cache"
cache_file="$cache_dir/usage.json"
cache_ttl=60  # seconds

fetch_usage() {
    local creds_file="$config_dir/.credentials.json"
    [ ! -f "$creds_file" ] && return 1

    local access_token
    access_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
    [ -z "$access_token" ] && return 1

    local sub_type
    sub_type=$(jq -r '.claudeAiOauth.subscriptionType // empty' "$creds_file" 2>/dev/null)

    # Skip for API-only users (no quota system)
    case "$sub_type" in
        ""|api|*api*) return 1 ;;
    esac

    # Check token expiry
    local expires_at
    expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' "$creds_file" 2>/dev/null)
    local now_ms=$(($(date +%s) * 1000))
    if [ "$expires_at" -gt 0 ] && [ "$now_ms" -gt "$expires_at" ]; then
        return 1  # Token expired
    fi

    # Call the usage API
    local response
    response=$(curl -s --max-time 5 \
        -H "Authorization: Bearer $access_token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-statusline/1.0" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

    [ -z "$response" ] && return 1

    # Validate response has expected structure
    echo "$response" | jq -e '.five_hour or .seven_day' >/dev/null 2>&1 || return 1

    # Write cache
    mkdir -p "$cache_dir"
    jq -n --argjson data "$response" --arg ts "$(date +%s)" --arg plan "$sub_type" \
        '{data: $data, timestamp: ($ts | tonumber), plan: $plan}' > "$cache_file" 2>/dev/null
}

get_usage_display() {
    local now=$(date +%s)

    # Check cache freshness
    if [ -f "$cache_file" ]; then
        local cached_ts
        cached_ts=$(jq -r '.timestamp // 0' "$cache_file" 2>/dev/null)
        local age=$(( now - cached_ts ))
        if [ "$age" -lt "$cache_ttl" ]; then
            # Cache is fresh, use it
            render_usage "$cache_file"
            return
        fi
    fi

    # Cache stale or missing — fetch in background to not block statusline
    # but still try to render stale cache if available
    if [ -f "$cache_file" ]; then
        render_usage "$cache_file"
        # Refresh in background
        fetch_usage &
    else
        # First run — fetch synchronously (one-time ~1s delay)
        fetch_usage
        [ -f "$cache_file" ] && render_usage "$cache_file"
    fi
}

render_usage() {
    local file="$1"
    local five_h seven_d plan_raw

    five_h=$(jq -r '.data.five_hour.utilization // empty' "$file" 2>/dev/null)
    seven_d=$(jq -r '.data.seven_day.utilization // empty' "$file" 2>/dev/null)
    plan_raw=$(jq -r '.plan // empty' "$file" 2>/dev/null)

    [ -z "$five_h" ] && return

    # Derive plan display name
    local plan_name=""
    case "$plan_raw" in
        *max*|*Max*) plan_name="Max" ;;
        *pro*|*Pro*) plan_name="Pro" ;;
        *team*|*Team*) plan_name="Team" ;;
        *) plan_name="$plan_raw" ;;
    esac

    # Round to integer
    five_h=$(printf '%.0f' "$five_h")
    [ -n "$seven_d" ] && seven_d=$(printf '%.0f' "$seven_d")

    # Color based on usage level
    local color="$CYAN"
    if [ "$five_h" -ge 90 ]; then
        color="$RED"
    elif [ "$five_h" -ge 75 ]; then
        color="$MAGENTA"
    elif [ "$five_h" -ge 50 ]; then
        color="$YELLOW"
    fi

    # Build usage bar (10 chars)
    local u_bar_width=10
    local u_filled=$((five_h * u_bar_width / 100))
    [ "$u_filled" -gt "$u_bar_width" ] && u_filled=$u_bar_width
    local u_empty=$((u_bar_width - u_filled))
    local u_bar=""
    for ((i=0; i<u_filled; i++)); do u_bar+="█"; done
    for ((i=0; i<u_empty; i++)); do u_bar+="░"; done

    # Reset time for 5h window
    local reset_str=""
    local reset_at
    reset_at=$(jq -r '.data.five_hour.resets_at // empty' "$file" 2>/dev/null)
    if [ -n "$reset_at" ]; then
        # Normalize: strip fractional seconds and convert +00:00 to Z
        local clean_date
        clean_date=$(echo "$reset_at" | sed -E 's/\.[0-9]+//; s/\+00:00$/Z/')
        local reset_epoch
        # macOS uses date -j -f, Linux uses date -d
        reset_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_date" +%s 2>/dev/null \
            || date -d "$clean_date" +%s 2>/dev/null)
        if [ -n "$reset_epoch" ]; then
            local remaining=$(( reset_epoch - $(date +%s) ))
            if [ "$remaining" -gt 0 ]; then
                local hours=$((remaining / 3600))
                local mins=$(( (remaining % 3600) / 60 ))
                if [ "$hours" -gt 0 ]; then
                    reset_str=" ${GRAY}${hours}h${mins}m${NC}"
                else
                    reset_str=" ${GRAY}${mins}m${NC}"
                fi
            fi
        fi
    fi

    # Compose
    local display="${color}${u_bar}${NC} ${color}${five_h}%${NC}${reset_str}"

    # Add 7-day if above 70%
    if [ -n "$seven_d" ] && [ "$seven_d" -ge 70 ]; then
        local s_color="$CYAN"
        [ "$seven_d" -ge 90 ] && s_color="$RED"
        [ "$seven_d" -ge 75 ] && [ "$seven_d" -lt 90 ] && s_color="$MAGENTA"
        display="${display} ${GRAY}7d:${NC}${s_color}${seven_d}%${NC}"
    fi

    usage_info=" ${GRAY}|${NC} ${GRAY}${plan_name}${NC} ${display}"
}

# Fetch usage display (non-blocking after first run)
get_usage_display

# --- Git info ---
cd "$current_dir" 2>/dev/null || cd /
export GIT_OPTIONAL_LOCKS=0

git_info=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    status_output=$(git status --porcelain 2>/dev/null)

    if [ -n "$status_output" ]; then
        total_files=$(echo "$status_output" | wc -l | xargs)
        line_stats=$(git diff --numstat HEAD 2>/dev/null | awk '{added+=$1; removed+=$2} END {print added+0, removed+0}')
        added=$(echo $line_stats | cut -d' ' -f1)
        removed=$(echo $line_stats | cut -d' ' -f2)

        git_info=" ${YELLOW}($branch${NC} ${YELLOW}|${NC} ${GRAY}${total_files} files${NC}"
        [ "$added" -gt 0 ] && git_info="${git_info} ${GREEN}+${added}${NC}"
        [ "$removed" -gt 0 ] && git_info="${git_info} ${RED}-${removed}${NC}"
        git_info="${git_info} ${YELLOW})${NC}"
    else
        git_info=" ${YELLOW}($branch)${NC}"
    fi
fi

# --- Build context bar display ---
context_info="${GRAY}${bar}${NC} ${context_percent}%"

# --- Output ---
echo -e "${BLUE}${dir_name}${NC} ${GRAY}|${NC} ${CYAN}${model_name}${NC} ${GRAY}|${NC} ${context_info}${usage_info}${git_info:+ ${GRAY}|${NC}}${git_info}"
