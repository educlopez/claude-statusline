#!/usr/bin/env bats

# Tests for release.sh
# Validates semver parsing, git state checks, version bumping, and CHANGELOG validation.
# Each test creates an isolated git repo in BATS_TEST_TMPDIR.

setup() {
    load 'test_helper/common-setup'
    _common_setup

    RELEASE_SCRIPT="$PROJECT_ROOT/release.sh"

    # Create a temporary git repo with copies of the scripts
    TEMP_REPO="$BATS_TEST_TMPDIR/release-repo"
    mkdir -p "$TEMP_REPO"

    # Copy scripts into temp repo
    cp "$PROJECT_ROOT/statusline.sh" "$TEMP_REPO/"
    cp "$PROJECT_ROOT/install.sh" "$TEMP_REPO/"
    cp "$PROJECT_ROOT/uninstall.sh" "$TEMP_REPO/"
    cp "$PROJECT_ROOT/release.sh" "$TEMP_REPO/"

    # Create a CHANGELOG with entries for testing
    cat > "$TEMP_REPO/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [2.0.0] - 2026-04-01

### Added
- New feature

## [1.0.0] - 2026-03-04

### Added
- Initial release
EOF

    # Initialize git repo
    cd "$TEMP_REPO"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git add -A
    git commit -q -m "initial commit"
}

# ─── Argument validation ───

@test "release: missing argument shows error" {
    cd "$TEMP_REPO"
    run bash release.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "release: --help shows usage and exits 0" {
    cd "$TEMP_REPO"
    run bash release.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--push"* ]]
}

# ─── Semver validation ───

@test "release: valid semver 2.0.0 is accepted" {
    cd "$TEMP_REPO"
    run bash release.sh 2.0.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Release v2.0.0 complete"* ]]
}

@test "release: invalid semver '1.2' is rejected" {
    cd "$TEMP_REPO"
    run bash release.sh 1.2
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid version format"* ]]
}

@test "release: invalid semver 'abc' is rejected" {
    cd "$TEMP_REPO"
    run bash release.sh abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid version format"* ]]
}

@test "release: invalid semver '1.2.3.4' is rejected" {
    cd "$TEMP_REPO"
    run bash release.sh 1.2.3.4
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid version format"* ]]
}

# ─── Git state checks ───

@test "release: dirty working directory is rejected" {
    cd "$TEMP_REPO"
    echo "uncommitted change" >> statusline.sh
    run bash release.sh 2.0.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"not clean"* ]]
}

@test "release: existing tag is rejected" {
    cd "$TEMP_REPO"
    git tag -a "v2.0.0" -m "existing tag"
    run bash release.sh 2.0.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

# ─── Version bumping ───

@test "release: version is bumped in all 3 scripts" {
    cd "$TEMP_REPO"
    run bash release.sh 2.0.0
    [ "$status" -eq 0 ]

    # Check each script has the new version
    local v1 v2 v3
    v1=$(grep '^STATUSLINE_VERSION=' statusline.sh | head -1 | sed 's/STATUSLINE_VERSION="//' | sed 's/"//')
    v2=$(grep '^STATUSLINE_VERSION=' install.sh | head -1 | sed 's/STATUSLINE_VERSION="//' | sed 's/"//')
    v3=$(grep '^STATUSLINE_VERSION=' uninstall.sh | head -1 | sed 's/STATUSLINE_VERSION="//' | sed 's/"//')
    [ "$v1" = "2.0.0" ]
    [ "$v2" = "2.0.0" ]
    [ "$v3" = "2.0.0" ]
}

# ─── CHANGELOG validation ───

@test "release: missing CHANGELOG entry is rejected" {
    cd "$TEMP_REPO"
    run bash release.sh 9.9.9
    [ "$status" -eq 1 ]
    [[ "$output" == *"CHANGELOG.md does not contain"* ]]
}

# ─── --push flag ───

@test "release: --push flag is recognized" {
    cd "$TEMP_REPO"
    # We can't actually push (no remote), but the script should get past
    # the validation and attempt the push (which will fail).
    # We just verify the flag doesn't cause an argument error.
    # Create a fake remote to prevent git push from erroring in an unexpected way
    git remote add origin "$BATS_TEST_TMPDIR/fake-remote.git" 2>/dev/null || true
    mkdir -p "$BATS_TEST_TMPDIR/fake-remote.git"
    cd "$BATS_TEST_TMPDIR/fake-remote.git"
    git init -q --bare
    cd "$TEMP_REPO"

    run bash release.sh 2.0.0 --push
    # It may fail on push if bare repo doesn't accept, but should get past validation
    # The key thing is it doesn't say "Unexpected argument"
    [[ "$output" != *"Unexpected argument"* ]]
}

# ─── Git tag and commit creation ───

@test "release: creates annotated git tag" {
    cd "$TEMP_REPO"
    run bash release.sh 2.0.0
    [ "$status" -eq 0 ]

    # Verify the tag exists
    run git tag -l "v2.0.0"
    [[ "$output" == *"v2.0.0"* ]]
}
