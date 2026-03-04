#!/usr/bin/env bats

# Tests for uninstall.sh
# Validates removal of each component and graceful handling of missing files.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    UNINSTALLER="$PROJECT_ROOT/uninstall.sh"
}

# ─── Helper to set up a full installation ───

_create_full_install() {
    mkdir -p "$CLAUDE_CONFIG_DIR/.usage-cache"
    echo "#!/bin/bash" > "$CLAUDE_CONFIG_DIR/statusline-command.sh"
    chmod +x "$CLAUDE_CONFIG_DIR/statusline-command.sh"
    echo '{"modules":["model","context"]}' > "$CLAUDE_CONFIG_DIR/.statusline-config.json"
    echo '{"statusLine":{"type":"command","command":"bash test"},"otherKey":"keep"}' > "$CLAUDE_CONFIG_DIR/settings.json"
    echo "cached-data" > "$CLAUDE_CONFIG_DIR/.usage-cache/usage.json"
}

# ─── Removal tests ───

@test "uninstall: removes statusline-command.sh" {
    _create_full_install
    [ -f "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]

    [ ! -f "$CLAUDE_CONFIG_DIR/statusline-command.sh" ]
}

@test "uninstall: removes .statusline-config.json" {
    _create_full_install
    [ -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]

    [ ! -f "$CLAUDE_CONFIG_DIR/.statusline-config.json" ]
}

@test "uninstall: removes statusLine key from settings.json while preserving other keys" {
    _create_full_install

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]

    # settings.json should still exist
    [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]

    # statusLine key should be gone
    local has_sl
    has_sl=$(jq 'has("statusLine")' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$has_sl" = "false" ]

    # Other keys should be preserved
    local other
    other=$(jq -r '.otherKey' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$other" = "keep" ]
}

@test "uninstall: removes .usage-cache directory" {
    _create_full_install
    [ -d "$CLAUDE_CONFIG_DIR/.usage-cache" ]

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]

    [ ! -d "$CLAUDE_CONFIG_DIR/.usage-cache" ]
}

# ─── Graceful handling of missing components ───

@test "uninstall: handles missing script gracefully" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    # No statusline-command.sh exists

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"already removed"* ]]
}

@test "uninstall: handles missing config gracefully" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    # No .statusline-config.json exists

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No module config"* ]] || [[ "$output" == *"not found"* ]]
}

@test "uninstall: handles missing settings.json gracefully" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    # No settings.json exists

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No settings.json"* ]]
}

@test "uninstall: handles settings.json without statusLine key gracefully" {
    mkdir -p "$CLAUDE_CONFIG_DIR"
    echo '{"someOtherKey": "value"}' > "$CLAUDE_CONFIG_DIR/settings.json"

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already clean"* ]]

    # The other key should still be there
    local other
    other=$(jq -r '.someOtherKey' "$CLAUDE_CONFIG_DIR/settings.json")
    [ "$other" = "value" ]
}

# ─── Success message ───

@test "uninstall: prints success message" {
    _create_full_install

    run bash "$UNINSTALLER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"uninstalled successfully"* ]]
}
