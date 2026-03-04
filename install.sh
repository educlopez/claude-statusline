#!/usr/bin/env bash
set -euo pipefail

# Claude Statusline Installer
# https://github.com/educlopez/claude-statusline
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/educlopez/claude-statusline/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --force
#   curl -fsSL ... | bash -s -- --modules=directory,model,context
#   curl -fsSL ... | bash -s -- --all

REPO_URL="https://raw.githubusercontent.com/educlopez/claude-statusline/main"
SCRIPT_NAME="statusline-command.sh"

# Module definitions (parallel arrays for bash 3 compat)
MOD_NAMES="directory model context usage git"
MOD_DESC_1="Directory      my-project"
MOD_DESC_2="Model          Opus 4.6"
MOD_DESC_3="Context        ░░░░░░░░░░░░░░░ 12%"
MOD_DESC_4="Usage quota    Max ██████░░░░ 58% 3h42m"
MOD_DESC_5="Git status     (main | 3 files +42 -8)"

# Parse flags
FORCE=false
SKIP_MENU=false
MODULES_ARG=""

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        --all)   SKIP_MENU=true; MODULES_ARG="directory,model,context,usage,git" ;;
        --modules=*) SKIP_MENU=true; MODULES_ARG="${arg#--modules=}" ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

get_mod_desc() {
    case "$1" in
        1) echo "$MOD_DESC_1" ;; 2) echo "$MOD_DESC_2" ;; 3) echo "$MOD_DESC_3" ;;
        4) echo "$MOD_DESC_4" ;; 5) echo "$MOD_DESC_5" ;;
    esac
}

get_mod_name() {
    case "$1" in
        1) echo "directory" ;; 2) echo "model" ;; 3) echo "context" ;;
        4) echo "usage" ;; 5) echo "git" ;;
    esac
}

# --- Prerequisites ---
info "Checking prerequisites..."

command -v bash >/dev/null 2>&1 || error "bash is required"
command -v curl >/dev/null 2>&1 || error "curl is required — install it first"
command -v jq   >/dev/null 2>&1 || error "jq is required — install it with: brew install jq (macOS) or apt install jq (Linux)"

ok "All prerequisites found (bash, curl, jq)"

# --- Resolve config directory ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
config_dir="${config_dir/#\~/$HOME}"
settings_file="$config_dir/settings.json"
script_dest="$config_dir/$SCRIPT_NAME"
statusline_config="$config_dir/.statusline-config.json"

info "Claude config directory: $config_dir"

# --- Determine selected modules ---
SELECTED_MODULES=""

if [ "$SKIP_MENU" = true ] && [ -n "$MODULES_ARG" ]; then
    # From --modules or --all flag
    SELECTED_MODULES="$MODULES_ARG"
elif [ "$SKIP_MENU" = false ]; then
    # Try interactive menu
    CAN_INTERACT=false
    if [ -e /dev/tty ]; then
        CAN_INTERACT=true
    elif [ -t 0 ]; then
        CAN_INTERACT=true
    fi

    if [ "$CAN_INTERACT" = true ]; then
        # Track enabled state: 1=on, 0=off (all on by default)
        en_1=1; en_2=1; en_3=1; en_4=1; en_5=1

        get_en() {
            case "$1" in
                1) echo $en_1 ;; 2) echo $en_2 ;; 3) echo $en_3 ;;
                4) echo $en_4 ;; 5) echo $en_5 ;;
            esac
        }

        toggle() {
            case "$1" in
                1) if [ $en_1 -eq 1 ]; then en_1=0; else en_1=1; fi ;;
                2) if [ $en_2 -eq 1 ]; then en_2=0; else en_2=1; fi ;;
                3) if [ $en_3 -eq 1 ]; then en_3=0; else en_3=1; fi ;;
                4) if [ $en_4 -eq 1 ]; then en_4=0; else en_4=1; fi ;;
                5) if [ $en_5 -eq 1 ]; then en_5=0; else en_5=1; fi ;;
            esac
        }

        draw_menu() {
            echo ""
            echo -e "${BOLD}Claude Statusline — Choose your modules:${NC}"
            echo ""
            for i in 1 2 3 4 5; do
                local desc
                desc=$(get_mod_desc "$i")
                if [ "$(get_en "$i")" -eq 1 ]; then
                    echo -e "  ${GREEN}[x]${NC} ${BOLD}$i)${NC} $desc"
                else
                    echo -e "  ${GRAY}[ ] $i) $desc${NC}"
                fi
            done
            echo ""
            echo -e "  Toggle: enter number (e.g. ${BOLD}4${NC}). Accept: ${BOLD}Enter${NC}. All: ${BOLD}a${NC}"
        }

        MENU_LINES=10
        draw_menu

        while true; do
            echo -ne "  > "
            if ! read -r choice < /dev/tty 2>/dev/null; then
                # Can't read from tty, use all defaults
                break
            fi

            case "$choice" in
                "")
                    break
                    ;;
                a|A)
                    en_1=1; en_2=1; en_3=1; en_4=1; en_5=1
                    # Redraw
                    for _ in $(seq 1 $((MENU_LINES + 1))); do
                        tput cuu1 2>/dev/null && tput el 2>/dev/null || true
                    done
                    draw_menu
                    ;;
                [1-5])
                    toggle "$choice"
                    for _ in $(seq 1 $((MENU_LINES + 1))); do
                        tput cuu1 2>/dev/null && tput el 2>/dev/null || true
                    done
                    draw_menu
                    ;;
                *)
                    echo -e "  ${YELLOW}Enter 1-5, 'a' for all, or Enter to confirm${NC}"
                    ;;
            esac
        done

        # Build selected modules string
        result=""
        for i in 1 2 3 4 5; do
            if [ "$(get_en "$i")" -eq 1 ]; then
                name=$(get_mod_name "$i")
                if [ -n "$result" ]; then
                    result="$result,$name"
                else
                    result="$name"
                fi
            fi
        done
        SELECTED_MODULES="$result"
    else
        # Non-interactive, no flags: default all
        SELECTED_MODULES="directory,model,context,usage,git"
    fi
fi

# Fallback
if [ -z "$SELECTED_MODULES" ]; then
    SELECTED_MODULES="directory,model,context,usage,git"
fi

# Validate at least one module
if [ "$SELECTED_MODULES" = "" ]; then
    error "No modules selected. Run again and pick at least one."
fi

echo ""
info "Selected modules: $(echo "$SELECTED_MODULES" | tr ',' ' ')"

# --- Download statusline script ---
if [ -f "$script_dest" ] && [ "$FORCE" = false ]; then
    warn "Statusline script already exists at $script_dest"
    warn "Use --force to overwrite, or run: curl ... | bash -s -- --force"
    echo ""
    info "Skipping script download (existing file preserved)"
else
    info "Downloading statusline script..."
    mkdir -p "$config_dir"
    curl -fsSL "$REPO_URL/statusline.sh" -o "$script_dest"
    chmod +x "$script_dest"
    ok "Script installed to $script_dest"
fi

# --- Write module config ---
modules_json=$(echo "$SELECTED_MODULES" | tr ',' '\n' | jq -R . | jq -s '{modules: .}')
echo "$modules_json" > "$statusline_config"
ok "Module config saved to $statusline_config"

# --- Configure settings.json ---
statusline_setting="{\"type\":\"command\",\"command\":\"bash $script_dest\"}"

if [ -f "$settings_file" ]; then
    existing=$(jq -r '.statusLine // empty' "$settings_file" 2>/dev/null)
    if [ -n "$existing" ] && [ "$FORCE" = false ]; then
        info "statusLine already configured in settings.json (use --force to overwrite)"
    else
        cp "$settings_file" "$settings_file.backup"
        info "Backed up settings.json to settings.json.backup"
        jq --argjson sl "$statusline_setting" '.statusLine = $sl' "$settings_file.backup" > "$settings_file"
        ok "Updated settings.json with statusLine configuration"
    fi
else
    mkdir -p "$config_dir"
    jq -n --argjson sl "$statusline_setting" '{statusLine: $sl}' > "$settings_file"
    ok "Created settings.json with statusLine configuration"
fi

# --- Done ---
echo ""
echo -e "${GREEN}Claude Statusline installed successfully!${NC}"
echo ""
echo "  What was installed:"
echo "    Script:   $script_dest"
echo "    Config:   $statusline_config"
echo "    Settings: $settings_file (statusLine key)"
echo ""
echo "  Enabled modules: $(echo "$SELECTED_MODULES" | tr ',' ' ')"
echo ""
echo "  To change modules later, re-run the installer with --force"
echo "  or edit $statusline_config directly."
echo ""
echo "  Restart Claude Code to see the statusline."
echo ""
echo "  To uninstall:"
echo "    curl -fsSL $REPO_URL/uninstall.sh | bash"
echo ""
