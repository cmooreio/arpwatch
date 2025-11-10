#!/usr/bin/env bash
# Arpwatch Docker Image - Security Tests
# Comprehensive security hardening validation tests

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

# Test: Running as non-root user
test_non_root_user() {
    log_test "Verifying container runs as non-root user"

    local uid
    uid=$(docker run --rm "$IMAGE" id -u)

    if [[ "$uid" != "0" ]]; then
        log_pass "Container runs as non-root user (UID: $uid)"
        return 0
    else
        log_fail "Container runs as root (UID: $uid)"
        return 1
    fi
}

# Test: USER directive set in Dockerfile
test_user_directive() {
    log_test "Checking USER directive in image config"

    local user
    user=$(docker image inspect "$IMAGE" --format='{{.Config.User}}')

    if [[ -n "$user" ]] && [[ "$user" != "root" ]] && [[ "$user" != "0" ]]; then
        log_pass "USER directive is set: $user"
        return 0
    else
        log_fail "USER directive not set or set to root"
        return 1
    fi
}

# Test: No setuid/setgid binaries
test_no_setuid_binaries() {
    log_test "Checking for dangerous setuid/setgid binaries"

    local setuid_binaries
    setuid_binaries=$(docker run --rm "$IMAGE" \
        find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null || true)

    if [[ -z "$setuid_binaries" ]]; then
        log_pass "No setuid/setgid binaries found"
        return 0
    else
        log_fail "Found setuid/setgid binaries:"
        echo "$setuid_binaries"
        return 1
    fi
}

# Test: File permissions on sensitive directories
test_file_permissions() {
    log_test "Checking file permissions on sensitive directories"

    local data_dir_perms
    data_dir_perms=$(docker run --rm "$IMAGE" stat -c '%a' /var/lib/arpwatch)

    if [[ "$data_dir_perms" == "755" ]]; then
        log_pass "Data directory has correct permissions: $data_dir_perms"
        return 0
    else
        log_fail "Data directory has incorrect permissions: $data_dir_perms (expected: 755)"
        return 1
    fi
}

# Test: User shell restrictions
test_user_shell_restriction() {
    log_test "Verifying user cannot get interactive shell"

    local shell
    shell=$(docker run --rm "$IMAGE" getent passwd arpwatch | cut -d: -f7)

    if [[ "$shell" == "/sbin/nologin" ]] || [[ "$shell" == "/usr/sbin/nologin" ]]; then
        log_pass "User has restricted shell: $shell"
        return 0
    else
        log_fail "User has interactive shell: $shell"
        return 1
    fi
}

# Test: OCI labels present
test_oci_labels() {
    log_test "Checking for required OCI labels"

    local required_labels=(
        "org.opencontainers.image.title"
        "org.opencontainers.image.version"
        "org.opencontainers.image.created"
        "org.opencontainers.image.source"
    )

    local labels
    labels=$(docker image inspect "$IMAGE" --format='{{json .Config.Labels}}')

    local all_present=true
    for label in "${required_labels[@]}"; do
        if ! echo "$labels" | grep -q "$label"; then
            log_fail "Missing OCI label: $label"
            all_present=false
        fi
    done

    if [[ "$all_present" == "true" ]]; then
        log_pass "All required OCI labels present"
        return 0
    else
        return 1
    fi
}

# Test: No secrets in image layers
test_no_secrets_in_layers() {
    log_test "Checking for potential secrets in image layers"

    local history
    history=$(docker history --no-trunc "$IMAGE" 2>/dev/null || echo "")

    local suspicious_patterns=("password" "secret" "token" "api_key" "private_key")
    local found_secrets=false

    for pattern in "${suspicious_patterns[@]}"; do
        if echo "$history" | grep -qi "$pattern"; then
            log_fail "Found suspicious pattern in history: $pattern"
            found_secrets=true
        fi
    done

    if [[ "$found_secrets" == "false" ]]; then
        log_pass "No obvious secrets found in image layers"
        return 0
    else
        return 1
    fi
}

# Test: Minimal package installation
test_minimal_packages() {
    log_test "Checking for unnecessary packages"

    # List of packages that should NOT be installed in production
    local unwanted_packages=("gcc" "make" "build-essential")
    local found_unwanted=false

    for pkg in "${unwanted_packages[@]}"; do
        if docker run --rm "$IMAGE" dpkg -l "$pkg" &>/dev/null; then
            log_fail "Unwanted package found: $pkg"
            found_unwanted=true
        fi
    done

    if [[ "$found_unwanted" == "false" ]]; then
        log_pass "No unnecessary build tools found"
        return 0
    else
        return 1
    fi
}

# Test: No package manager cache
test_no_package_cache() {
    log_test "Checking that package manager cache is cleaned"

    local apt_lists
    apt_lists=$(docker run --rm "$IMAGE" find /var/lib/apt/lists -type f 2>/dev/null | wc -l)

    if [[ "$apt_lists" -eq 0 ]]; then
        log_pass "Package manager cache is cleaned"
        return 0
    else
        log_fail "Package manager cache not cleaned ($apt_lists files found)"
        return 1
    fi
}

# Test: Image size is reasonable
test_image_size() {
    log_test "Checking image size is reasonable"

    local size_bytes
    size_bytes=$(docker image inspect "$IMAGE" --format='{{.Size}}')
    local size_mb=$((size_bytes / 1024 / 1024))

    # Arpwatch image should be under 200MB
    if [[ $size_mb -lt 200 ]]; then
        log_pass "Image size is reasonable: ${size_mb}MB"
        return 0
    else
        log_fail "Image size is too large: ${size_mb}MB (expected < 200MB)"
        return 1
    fi
}

# Test: Read-only root filesystem compatibility
test_readonly_root_fs() {
    log_test "Testing read-only root filesystem compatibility"

    if docker run --rm \
        --read-only \
        --tmpfs /tmp:uid=102,gid=102 \
        --tmpfs /var/tmp:uid=102,gid=102 \
        --tmpfs /run:uid=102,gid=102 \
        -v "arpwatch-sec-test:/var/lib/arpwatch:rw" \
        "$IMAGE" \
        /bin/bash -c "exit 0" 2>/dev/null; then

        log_pass "Read-only root filesystem compatible"
        docker volume rm arpwatch-sec-test 2>/dev/null || true
        return 0
    else
        log_fail "Not compatible with read-only root filesystem"
        docker volume rm arpwatch-sec-test 2>/dev/null || true
        return 1
    fi
}

# Test: No world-writable files
test_no_world_writable() {
    log_test "Checking for world-writable files"

    local world_writable
    world_writable=$(docker run --rm "$IMAGE" \
        find / -type f -perm -002 ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null || true)

    if [[ -z "$world_writable" ]]; then
        log_pass "No world-writable files found"
        return 0
    else
        log_fail "Found world-writable files:"
        echo "$world_writable"
        return 1
    fi
}

# Test: Healthcheck configured
test_healthcheck_configured() {
    log_test "Verifying health check is configured"

    local healthcheck
    healthcheck=$(docker image inspect "$IMAGE" --format='{{.Config.Healthcheck}}')

    if [[ "$healthcheck" != "<nil>" ]] && [[ -n "$healthcheck" ]]; then
        log_pass "Health check is configured"
        return 0
    else
        log_fail "Health check not configured"
        return 1
    fi
}

# Test: Environment variables don't contain secrets
test_env_no_secrets() {
    log_test "Checking environment variables for secrets"

    local env_vars
    env_vars=$(docker run --rm "$IMAGE" env)

    local secret_patterns=("PASSWORD" "SECRET" "TOKEN" "KEY" "CREDENTIAL")
    local found_secrets=false

    for pattern in "${secret_patterns[@]}"; do
        if echo "$env_vars" | grep -E "^${pattern}=" | grep -v "=${pattern}" >/dev/null; then
            log_fail "Found potential secret in environment: $pattern"
            found_secrets=true
        fi
    done

    if [[ "$found_secrets" == "false" ]]; then
        log_pass "No secrets found in environment variables"
        return 0
    else
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "======================================"
    echo "Security Test Summary"
    echo "======================================"
    echo "Image: $IMAGE"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "======================================"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All security tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some security tests failed!${NC}"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Arpwatch Security Tests"
    log_info "Image: $IMAGE"
    log_info "Version: $VERSION"
    echo ""

    # Run all tests
    test_non_root_user || true
    test_user_directive || true
    test_no_setuid_binaries || true
    test_file_permissions || true
    test_user_shell_restriction || true
    test_oci_labels || true
    test_no_secrets_in_layers || true
    test_minimal_packages || true
    test_no_package_cache || true
    test_image_size || true
    test_readonly_root_fs || true
    test_no_world_writable || true
    test_healthcheck_configured || true
    test_env_no_secrets || true

    # Print summary
    print_summary
}

# Run tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
