#!/usr/bin/env bats

# Tests for install.sh
# Validates flags, module configuration, settings.json handling, and update mode.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    INSTALLER="$PROJECT_ROOT/install.sh"

    # Mock curl: instead of downloading from GitHub, copy local statusline.sh
    create_mock "curl" "
        # Parse the -o flag to find the output file
        out_file=\"\"
        for arg in \"\$@\"; do
            if [ -n \"\$next_is_out\" ]; then
                out_file=\"\$arg\"
                next_is_out=\"\"
                continue
            fi
            case \"\$arg\" in
                -o) next_is_out=1 ;;
            esac
        done
        if [ -n \"\$out_file\" ]; then
            cp \"$PROJECT_ROOT/statusline.sh\" \"\$out_file\"
        fi
        exit 0
    "

    # Mock pgrep to not detect running claude processes
    create_mock "pgrep" 'exit 1'
}

# ─── Help and version flags ───

@test "install: --help prints usage and exits 0" {
    run bash "$INSTALLER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--force"* ]]
    [[ "$output" == *"--modules"* ]]
}

@test "install: -h also prints help" {
    run bash "$INSTALLER" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "install: --version prints version and exits 0" {
    run bash "$INSTALLER" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-statusline v"* ]]
}

@test "install: --help takes priority over other flags" {
    # --help should print help and exit, regardless of other flags
    run bash "$INSTALLER" --force --help --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ─── Module configuration ───

@test "install: --modules=model,context creates correct config JSON" {
    run bash "$INSTALLER" --modules=model,context
    [ "$status" -eq 0 ]

    # Verify config file exists and has correct modules
    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$modules" = "context,model" ]
}

@test "install: --all creates config with all 5 modules" {
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local count
    count=$(jq '.modules | length' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$count" -eq 5 ]

    # Verify all module names are present
    local modules
    modules=$(jq -r '.modules | sort | join(",")' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$modules" = "context,directory,git,model,usage" ]
}

# ─── Settings.json handling ───

@test "install: fresh install creates settings.json with statusLine key" {
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
    local sl_type
    sl_type=$(jq -r '.statusLine.type' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$sl_type" = "command" ]
}

@test "install: preserves existing keys in settings.json" {
    # Create pre-existing settings.json with a custom key
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"customKey": "customValue", "anotherKey": 42}' > "$CLAUDE_CONFIG_DIR/settings.json"

    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    # statusLine should be added
    local sl_type
    sl_type=$(jq -r '.statusLine.type' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$sl_type" = "command" ]

    # Original keys should be preserved
    local custom
    custom=$(jq -r '.customKey' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$custom" = "customValue" ]

    local another
    another=$(jq -r '.anotherKey' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$another" = "42" ]
}

@test "install: backup is created when modifying existing settings.json" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"existingKey": true}' > "$CLAUDE_CONFIG_DIR/settings.json"

    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    # Backup file should exist
    [ -f "$CLAUDE_CONFIG_DIR/settings.json.backup" ]
}

# ─── Force and skip behavior ───

@test "install: --force overwrites existing script" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo "old-content" > "$CLAUDE_CONFIG_DIR/statusline-command.sh"

    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    # Script should be overwritten (no longer "old-content")
    local content
    content=$(head -1 "$CLAUDE_CONFIG_DIR/statusline-command.sh")
    [[ "$content" == "#!/usr/bin/env bash" ]]
}

@test "install: without --force existing script is preserved" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo "original-content" > "$CLAUDE_CONFIG_DIR/statusline-command.sh"

    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    # Script should still have original content (not overwritten)
    local content
    content=$(cat "$CLAUDE_CONFIG_DIR/statusline-command.sh")
    [ "$content" = "original-content" ]
    [[ "$output" == *"already exists"* ]]
}

# ─── Update mode ───

@test "install: --update downloads script but does not touch config or settings" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    # Pre-create a config and settings
    echo '{"modules":["model"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    echo '{"statusLine":{"type":"command","command":"old"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
    echo "old-script" > "$CLAUDE_CONFIG_DIR/statusline-command.sh"

    run bash "$INSTALLER" --update
    [ "$status" -eq 0 ]

    # Script should be updated (not "old-script")
    local first_line
    first_line=$(head -1 "$CLAUDE_CONFIG_DIR/statusline-command.sh")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]

    # Config should be untouched
    local config_modules
    config_modules=$(jq -r '.modules[0]' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$config_modules" = "model" ]

    # Settings should be untouched
    local old_cmd
    old_cmd=$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$old_cmd" = "old" ]

    # Output should mention "preserved"
    [[ "$output" == *"preserved"* ]]
}

# ─── NO_COLOR ───

@test "install: NO_COLOR=1 produces output without ANSI escape codes" {
    run env NO_COLOR=1 bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    # Output should not contain the ESC character (0x1b) used in ANSI sequences.
    # Use printf to produce a literal ESC byte and check it does not appear.
    local esc
    esc=$(printf '\033')
    [[ "$output" != *"$esc"* ]]
}

# ─── Single module ───

@test "install: --modules=git creates config with only git" {
    run bash "$INSTALLER" --modules=git
    [ "$status" -eq 0 ]

    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
    local count
    count=$(jq '.modules | length' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$count" -eq 1 ]

    local module
    module=$(jq -r '.modules[0]' "$CLAUDE_CONFIG_DIR/.statusline-config.json")
    [ "$module" = "git" ]
}

# ─── Script is executable ───

@test "install: installed script is executable" {
    run bash "$INSTALLER" --all --force
    [ "$status" -eq 0 ]

    [ -x "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]
}

# ─── Success message ───

@test "install: success message shows installed paths" {
    run bash "$INSTALLER" --all
    [ "$status" -eq 0 ]

    [[ "$output" == *"installed successfully"* ]]
    [[ "$output" == *"statusline-command.sh"* ]]
    [[ "$output" == *".statusline-config.json"* ]]
    [[ "$output" == *"settings.json"* ]]
}
