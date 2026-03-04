#!/usr/bin/env bash

# Common setup for all bats tests
# Provides isolation via CLAUDE_CONFIG_DIR and mock helpers

_common_setup() {
    # Load bats-support and bats-assert if available
    if [ -f "$BATS_TEST_DIRNAME/../lib/bats-support/load.bash" ]; then
        load "$BATS_TEST_DIRNAME/../lib/bats-support/load.bash"
        load "$BATS_TEST_DIRNAME/../lib/bats-assert/load.bash"
        BATS_ASSERT_LOADED=true
    elif [ -f "/usr/local/lib/bats-support/load.bash" ]; then
        load "/usr/local/lib/bats-support/load.bash"
        load "/usr/local/lib/bats-assert/load.bash"
        BATS_ASSERT_LOADED=true
    elif [ -f "$BATS_TEST_DIRNAME/../node_modules/bats-support/load.bash" ]; then
        load "$BATS_TEST_DIRNAME/../node_modules/bats-support/load.bash"
        load "$BATS_TEST_DIRNAME/../node_modules/bats-assert/load.bash"
        BATS_ASSERT_LOADED=true
    else
        BATS_ASSERT_LOADED=false
    fi

    # Project root (one level up from test/)
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PROJECT_ROOT

    # Isolated config directory — NEVER touches ~/.claude
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude-config"
    mkdir -p "$CLAUDE_CONFIG_DIR"

    # Mock bin directory
    MOCK_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
}

# Create an executable mock script in the mock bin directory
# Usage: create_mock <command-name> [script-body]
# If no script-body is given, the mock exits 0 silently.
create_mock() {
    local name="$1"
    local body="${2:-exit 0}"
    local mock_path="$MOCK_BIN/$name"

    cat > "$mock_path" <<MOCK_EOF
#!/usr/bin/env bash
$body
MOCK_EOF
    chmod +x "$mock_path"
}
