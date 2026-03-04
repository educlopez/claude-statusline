#!/bin/bash
set -euo pipefail

# Claude Statusline Installer
# https://github.com/educlopez/claude-statusline
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/educlopez/claude-statusline/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/educlopez/claude-statusline/main/install.sh | bash -s -- --force

REPO_URL="https://raw.githubusercontent.com/educlopez/claude-statusline/main"
SCRIPT_NAME="statusline-command.sh"

# Parse flags
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

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

info "Claude config directory: $config_dir"

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

# --- Configure settings.json ---
statusline_config="{\"type\":\"command\",\"command\":\"bash $script_dest\"}"

if [ -f "$settings_file" ]; then
    # Check if statusLine is already configured
    existing=$(jq -r '.statusLine // empty' "$settings_file" 2>/dev/null)
    if [ -n "$existing" ] && [ "$FORCE" = false ]; then
        info "statusLine already configured in settings.json (use --force to overwrite)"
    else
        # Backup existing settings
        cp "$settings_file" "$settings_file.backup"
        info "Backed up settings.json to settings.json.backup"

        # Inject statusLine key
        jq --argjson sl "$statusline_config" '.statusLine = $sl' "$settings_file.backup" > "$settings_file"
        ok "Updated settings.json with statusLine configuration"
    fi
else
    # Create minimal settings.json
    mkdir -p "$config_dir"
    jq -n --argjson sl "$statusline_config" '{statusLine: $sl}' > "$settings_file"
    ok "Created settings.json with statusLine configuration"
fi

# --- Done ---
echo ""
echo -e "${GREEN}Claude Statusline installed successfully!${NC}"
echo ""
echo "  What was installed:"
echo "    Script:   $script_dest"
echo "    Config:   $settings_file (statusLine key)"
echo ""
echo "  Restart Claude Code to see the statusline."
echo ""
echo "  To uninstall:"
echo "    curl -fsSL $REPO_URL/uninstall.sh | bash"
echo ""
