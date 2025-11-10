#!/usr/bin/env bash
# Arpwatch Docker Image - Integration Tests
# Comprehensive tests for arpwatch functionality and docker-compose integration

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

# Test: Container with environment variables
test_environment_variables() {
    log_test "Testing environment variable configuration"

    local output
    if output=$(docker run --rm \
        -e ARPWATCH_INTERFACES="eth0" \
        "$IMAGE" env 2>&1); then

        if echo "$output" | grep -q "ARPWATCH_INTERFACES=eth0"; then
            log_pass "Environment variables work correctly"
            return 0
        else
            log_fail "Environment variables not set correctly"
            return 1
        fi
    else
        log_fail "Failed to run container with environment variables"
        return 1
    fi
}

# Test: Entrypoint script validation
test_entrypoint_validation() {
    log_test "Testing entrypoint validation (no interfaces)"

    # Should fail when no interfaces provided
    if docker run --rm \
        -e ARPWATCH_INTERFACES="" \
        "$IMAGE" 2>&1 | grep -q "No interfaces specified"; then
        log_pass "Entrypoint validation works (correctly rejects empty interfaces)"
        return 0
    else
        log_fail "Entrypoint validation failed"
        return 1
    fi
}

# Test: Data directory persistence
test_data_persistence() {
    log_test "Testing data directory persistence"

    local container_name="arpwatch-test-$$"
    local test_file="test-$$.dat"

    # Create container with volume
    if docker run --rm \
        --name "$container_name" \
        -v "arpwatch-test-data:/var/lib/arpwatch" \
        "$IMAGE" \
        touch "/var/lib/arpwatch/$test_file" 2>/dev/null; then

        log_pass "Data directory is writable"

        # Cleanup
        docker volume rm arpwatch-test-data 2>/dev/null || true
        return 0
    else
        log_fail "Data directory is not writable"
        docker volume rm arpwatch-test-data 2>/dev/null || true
        return 1
    fi
}

# Test: Read-only filesystem compatibility
test_readonly_filesystem() {
    log_test "Testing read-only filesystem compatibility"

    # Run with read-only filesystem and tmpfs for writable areas
    if docker run --rm \
        --read-only \
        --tmpfs /tmp:uid=102,gid=102,mode=1777 \
        --tmpfs /var/tmp:uid=102,gid=102,mode=1777 \
        --tmpfs /run:uid=102,gid=102,mode=755 \
        -v "arpwatch-test-ro:/var/lib/arpwatch:rw" \
        "$IMAGE" \
        /bin/bash -c "test -w /tmp && test -w /var/lib/arpwatch" 2>/dev/null; then

        log_pass "Read-only filesystem compatibility works"

        # Cleanup
        docker volume rm arpwatch-test-ro 2>/dev/null || true
        return 0
    else
        log_fail "Read-only filesystem compatibility failed"
        docker volume rm arpwatch-test-ro 2>/dev/null || true
        return 1
    fi
}

# Test: Docker Compose configuration
test_docker_compose() {
    log_test "Testing docker-compose configuration"

    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        log_fail "docker-compose.yml not found"
        return 1
    fi

    # Validate docker-compose file
    if docker compose -f "$PROJECT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
        log_pass "docker-compose.yml is valid"
        return 0
    else
        log_fail "docker-compose.yml validation failed"
        return 1
    fi
}

# Test: Health check functionality
test_health_check() {
    log_test "Testing health check"

    # Get health check command from image
    local healthcheck
    healthcheck=$(docker image inspect "$IMAGE" --format='{{.Config.Healthcheck.Test}}')

    if [[ -n "$healthcheck" ]]; then
        log_pass "Health check is configured: $healthcheck"
        return 0
    else
        log_fail "Health check not configured"
        return 1
    fi
}

# Test: Network capabilities
test_network_capabilities() {
    log_test "Testing required network capabilities"

    # Test that container can be run with NET_RAW and NET_ADMIN caps
    if docker run --rm \
        --cap-drop=ALL \
        --cap-add=NET_RAW \
        --cap-add=NET_ADMIN \
        "$IMAGE" \
        /bin/bash -c "exit 0" 2>/dev/null; then

        log_pass "Network capabilities work correctly"
        return 0
    else
        log_fail "Network capabilities test failed"
        return 1
    fi
}

# Test: User permissions
test_user_permissions() {
    log_test "Testing user cannot write to read-only locations"

    # Test that user cannot write to /etc
    if docker run --rm "$IMAGE" \
        /bin/bash -c "touch /etc/test 2>/dev/null"; then
        log_fail "User can write to /etc (should not be allowed)"
        return 1
    else
        log_pass "User correctly cannot write to /etc"
        return 0
    fi
}

# Test: Working directory
test_working_directory() {
    log_test "Testing working directory"

    local pwd
    pwd=$(docker run --rm "$IMAGE" pwd)

    if [[ "$pwd" == "/var/lib/arpwatch" ]]; then
        log_pass "Working directory is correct: $pwd"
        return 0
    else
        log_fail "Working directory is incorrect: $pwd (expected: /var/lib/arpwatch)"
        return 1
    fi
}

# Test: Required packages are installed
test_required_packages() {
    log_test "Testing required packages"

    local packages=("arpwatch" "ip")
    local all_installed=true

    for pkg in "${packages[@]}"; do
        if ! docker run --rm "$IMAGE" which "$pkg" &>/dev/null; then
            log_fail "Required package not found: $pkg"
            all_installed=false
        fi
    done

    if [[ "$all_installed" == "true" ]]; then
        log_pass "All required packages are installed"
        return 0
    else
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "======================================"
    echo "Integration Test Summary"
    echo "======================================"
    echo "Image: $IMAGE"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "======================================"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All integration tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Arpwatch Integration Tests"
    log_info "Image: $IMAGE"
    log_info "Version: $VERSION"
    echo ""

    # Run all tests
    test_environment_variables || true
    test_entrypoint_validation || true
    test_data_persistence || true
    test_readonly_filesystem || true
    test_docker_compose || true
    test_health_check || true
    test_network_capabilities || true
    test_user_permissions || true
    test_working_directory || true
    test_required_packages || true

    # Print summary
    print_summary
}

# Run tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
