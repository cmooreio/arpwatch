#!/usr/bin/env bash
# Arpwatch Docker Image - Smoke Tests
# Basic functionality tests to verify the image works correctly

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load version info
# shellcheck source=../versions.env
source "$PROJECT_DIR/versions.env"

# Test configuration
IMAGE="${IMAGE:-cmooreio/arpwatch:latest}"
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Logging functions
log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

# Test: Image exists
test_image_exists() {
    log_test "Checking if image exists: $IMAGE"

    if docker image inspect "$IMAGE" &>/dev/null; then
        log_pass "Image exists"
        return 0
    else
        log_fail "Image does not exist"
        return 1
    fi
}

# Test: Arpwatch binary exists and is executable
test_binary_exists() {
    log_test "Checking if arpwatch binary exists and is executable"

    if docker run --rm "$IMAGE" which arpwatch &>/dev/null; then
        log_pass "Arpwatch binary exists"
        return 0
    else
        log_fail "Arpwatch binary not found"
        return 1
    fi
}

# Test: Arpwatch version command works
test_version_command() {
    log_test "Testing arpwatch version command"

    # Note: arpwatch -v returns non-zero exit code, but still outputs version
    # Use || true to handle the exit code, then check if output contains version info
    local output
    output=$(docker run --rm "$IMAGE" arpwatch -v 2>&1 || true)

    if echo "$output" | grep -q "Version"; then
        log_pass "Version command works"
        return 0
    else
        log_fail "Version command failed"
        return 1
    fi
}

# Test: Container runs as non-root user
test_non_root_user() {
    log_test "Checking if container runs as non-root user"

    local uid
    uid=$(docker run --rm "$IMAGE" id -u)

    if [[ "$uid" == "102" ]]; then
        log_pass "Running as non-root user (UID: $uid)"
        return 0
    else
        log_fail "Not running as expected user (UID: $uid, expected: 102)"
        return 1
    fi
}

# Test: Arpwatch user exists
test_arpwatch_user() {
    log_test "Checking if arpwatch user exists"

    if docker run --rm "$IMAGE" id arpwatch &>/dev/null; then
        log_pass "Arpwatch user exists"
        return 0
    else
        log_fail "Arpwatch user does not exist"
        return 1
    fi
}

# Test: Required directories exist
test_directories_exist() {
    log_test "Checking if required directories exist"

    local dirs=("/var/lib/arpwatch" "/var/log/arpwatch")
    local all_exist=true

    for dir in "${dirs[@]}"; do
        if ! docker run --rm "$IMAGE" test -d "$dir"; then
            log_fail "Directory does not exist: $dir"
            all_exist=false
        fi
    done

    if [[ "$all_exist" == "true" ]]; then
        log_pass "All required directories exist"
        return 0
    else
        return 1
    fi
}

# Test: Data directory has correct permissions
test_directory_permissions() {
    log_test "Checking directory permissions"

    local owner
    owner=$(docker run --rm "$IMAGE" stat -c '%U:%G' /var/lib/arpwatch)

    if [[ "$owner" == "arpwatch:arpwatch" ]]; then
        log_pass "Data directory has correct ownership: $owner"
        return 0
    else
        log_fail "Data directory has incorrect ownership: $owner (expected: arpwatch:arpwatch)"
        return 1
    fi
}

# Test: User shell is nologin
test_user_shell() {
    log_test "Checking user shell restrictions"

    local shell
    shell=$(docker run --rm "$IMAGE" getent passwd arpwatch | cut -d: -f7)

    if [[ "$shell" == "/sbin/nologin" ]] || [[ "$shell" == "/usr/sbin/nologin" ]]; then
        log_pass "User has nologin shell: $shell"
        return 0
    else
        log_fail "User has interactive shell: $shell (expected: nologin)"
        return 1
    fi
}

# Test: Entrypoint script exists
test_entrypoint_exists() {
    log_test "Checking if entrypoint script exists"

    if docker run --rm "$IMAGE" test -f /usr/local/bin/docker-entrypoint.sh; then
        log_pass "Entrypoint script exists"
        return 0
    else
        log_fail "Entrypoint script not found"
        return 1
    fi
}

# Test: Entrypoint script is executable
test_entrypoint_executable() {
    log_test "Checking if entrypoint script is executable"

    if docker run --rm "$IMAGE" test -x /usr/local/bin/docker-entrypoint.sh; then
        log_pass "Entrypoint script is executable"
        return 0
    else
        log_fail "Entrypoint script is not executable"
        return 1
    fi
}

# Test: Image has proper labels
test_image_labels() {
    log_test "Checking OCI labels"

    local labels
    labels=$(docker image inspect "$IMAGE" --format='{{json .Config.Labels}}')

    if echo "$labels" | grep -q "org.opencontainers.image.version"; then
        log_pass "Image has OCI labels"
        return 0
    else
        log_fail "Image missing OCI labels"
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "======================================"
    echo "Smoke Test Summary"
    echo "======================================"
    echo "Image: $IMAGE"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "======================================"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All smoke tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Arpwatch Smoke Tests"
    log_info "Image: $IMAGE"
    log_info "Version: $VERSION"
    echo ""

    # Run all tests
    test_image_exists || true
    test_binary_exists || true
    test_version_command || true
    test_non_root_user || true
    test_arpwatch_user || true
    test_directories_exist || true
    test_directory_permissions || true
    test_user_shell || true
    test_entrypoint_exists || true
    test_entrypoint_executable || true
    test_image_labels || true

    # Print summary
    print_summary
}

# Run tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
