#!/usr/bin/env bash
# Arpwatch Docker Image Build Script
# Security-hardened build script with validation and multi-platform support
# NO eval() usage - security best practice

set -euo pipefail

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build Arpwatch Docker image with security hardening and multi-platform support.

OPTIONS:
    --platform PLATFORM    Platform(s) to build (default: auto-detect native)
                          Examples: linux/amd64, linux/arm64, linux/amd64,linux/arm64
    --push                Push image to registry after build
    --no-cache            Build without using cache
    --dry-run             Show build command without executing
    --scan                Run security scan after build
    --sign                Sign image with cosign after build
    --help                Display this help message

EXAMPLES:
    # Build for native platform (fast, no emulation)
    $(basename "$0")

    # Build for specific platform
    $(basename "$0") --platform linux/amd64

    # Build multi-platform and push
    $(basename "$0") --platform linux/amd64,linux/arm64 --push

    # Build with security scan
    $(basename "$0") --scan

    # Dry run (show command without executing)
    $(basename "$0") --dry-run

ENVIRONMENT:
    DEBUG=true            Enable debug output

VERSION:
    The script reads version information from versions.env

EOF
}

# Validate Debian version format
validate_debian_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[a-z]+$ ]]; then
        log_error "Invalid Debian version: $version (expected format: trixie, bookworm, etc.)"
        return 1
    fi
    return 0
}

# Validate version format (semantic versioning)
validate_version() {
    local version="$1"
    # Allow formats like: 2.1a15, 2.1, etc.
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+[a-z]?[0-9]*$ ]]; then
        log_error "Invalid version format: $version (expected: x.y or x.yaz format)"
        return 1
    fi
    return 0
}

# Load and validate versions.env
load_versions() {
    local versions_file="${SCRIPT_DIR}/versions.env"

    if [[ ! -f "$versions_file" ]]; then
        log_error "versions.env not found at: $versions_file"
        exit 1
    fi

    log_info "Loading versions from: $versions_file"

    # Source the file to load variables
    # shellcheck source=/dev/null
    source "$versions_file"

    # Validate required variables
    if [[ -z "${VERSION:-}" ]]; then
        log_error "VERSION not set in versions.env"
        exit 1
    fi

    if [[ -z "${DEBIAN_VERSION:-}" ]]; then
        log_error "DEBIAN_VERSION not set in versions.env"
        exit 1
    fi

    # Validate formats
    validate_version "$VERSION" || exit 1
    validate_debian_version "$DEBIAN_VERSION" || exit 1

    log_info "Arpwatch version: $VERSION"
    log_info "Debian version: $DEBIAN_VERSION"

    # Export for use in build
    export VERSION
    export DEBIAN_VERSION
}

# Auto-detect native platform
detect_platform() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64)
            echo "linux/amd64"
            ;;
        aarch64|arm64)
            echo "linux/arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# Parse command-line arguments
parse_args() {
    PLATFORM=""
    PUSH=false
    NO_CACHE=false
    DRY_RUN=false
    SCAN=false
    SIGN=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --push)
                PUSH=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --scan)
                SCAN=true
                shift
                ;;
            --sign)
                SIGN=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Default to native platform if not specified
    if [[ -z "$PLATFORM" ]]; then
        PLATFORM="$(detect_platform)"
        log_info "Auto-detected platform: $PLATFORM"
    fi

    # Export for use in build functions
    export PLATFORM PUSH NO_CACHE DRY_RUN SCAN SIGN
}

# Create or ensure buildx builder exists
ensure_builder() {
    local builder_name="arpwatch-builder"

    if ! docker buildx inspect "$builder_name" >/dev/null 2>&1; then
        log_info "Creating buildx builder: $builder_name"
        docker buildx create --name "$builder_name" --driver docker-container --bootstrap
    else
        log_debug "Builder $builder_name already exists"
    fi

    echo "$builder_name"
}

# Build Docker image
build_image() {
    local builder_name
    builder_name="$(ensure_builder)"

    # Generate build metadata
    local build_date
    build_date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local vcs_ref
    vcs_ref="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

    # Extract major.minor version
    local major_minor
    major_minor="$(echo "$VERSION" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')"

    # Image configuration
    local image_repo="cmooreio/arpwatch"

    # Build command as array (NO eval for security)
    local -a build_cmd=(
        "docker" "buildx" "build"
        "--builder" "$builder_name"
        "--platform" "$PLATFORM"
        "--build-arg" "VERSION=$VERSION"
        "--build-arg" "DEBIAN_VERSION=$DEBIAN_VERSION"
        "--build-arg" "BUILD_DATE=$build_date"
        "--build-arg" "VCS_REF=$vcs_ref"
        "--sbom=true"
        "--provenance=true"
        "-t" "${image_repo}:latest"
        "-t" "${image_repo}:${VERSION}"
        "-t" "${image_repo}:${major_minor}"
    )

    # Add optional flags
    if [[ "$NO_CACHE" == "true" ]]; then
        build_cmd+=("--no-cache")
    fi

    if [[ "$PUSH" == "true" ]]; then
        build_cmd+=("--push")
    else
        build_cmd+=("--load")
    fi

    # Add context (current directory)
    build_cmd+=(".")

    # Display build information
    log_info "Build Configuration:"
    log_info "  Platform(s):  $PLATFORM"
    log_info "  Version:      $VERSION"
    log_info "  Debian:       $DEBIAN_VERSION"
    log_info "  Build Date:   $build_date"
    log_info "  VCS Ref:      $vcs_ref"
    log_info "  Tags:"
    log_info "    - ${image_repo}:latest"
    log_info "    - ${image_repo}:${VERSION}"
    log_info "    - ${image_repo}:${major_minor}"
    log_info "  SBOM:         enabled"
    log_info "  Provenance:   enabled"

    if [[ "$PUSH" == "true" ]]; then
        log_warn "Push enabled - image will be published to Docker Hub"
        read -rp "Continue? [y/N] " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Build cancelled"
            exit 0
        fi
    fi

    # Execute or display command
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Command that would be executed:"
        echo "${build_cmd[*]}"
        return 0
    fi

    log_info "Starting build..."

    # Execute build command
    "${build_cmd[@]}"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_info "Build completed successfully ✓"
    else
        log_error "Build failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Scan image for vulnerabilities
scan_image() {
    local image="${1:-cmooreio/arpwatch:latest}"

    log_info "Scanning image for vulnerabilities: $image"

    if command -v trivy &> /dev/null; then
        log_info "Using trivy for security scan..."
        trivy image --severity HIGH,CRITICAL "$image"
    elif command -v grype &> /dev/null; then
        log_info "Using grype for security scan..."
        grype "$image"
    else
        log_warn "No security scanner found (trivy or grype)"
        log_warn "Install with: brew install trivy"
        return 1
    fi
}

# Sign image with cosign
sign_image() {
    local image="${1:-cmooreio/arpwatch:latest}"

    if ! command -v cosign &> /dev/null; then
        log_error "cosign not found. Install with: brew install cosign"
        return 1
    fi

    log_info "Signing image: $image"
    cosign sign "$image"
}

# Main execution
main() {
    log_info "Arpwatch Docker Build Script"
    log_info "=============================="

    # Load versions
    load_versions

    # Parse arguments
    parse_args "$@"

    # Build image
    build_image

    # Optional: scan image
    if [[ "$SCAN" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        scan_image
    fi

    # Optional: sign image
    if [[ "$SIGN" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        sign_image
    fi

    log_info "All operations completed successfully ✓"
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
