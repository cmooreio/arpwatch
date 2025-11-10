#!/bin/bash
set -e

# Enable command tracing for debugging
set -x

# Arpwatch Docker Entrypoint Script
# Handles configuration and startup of arpwatch service

# Default values (ARPWATCH_INTERFACES has no default - must be set by user)
# Note: We don't use -u flag since container already runs as arpwatch user
ARPWATCH_INTERFACES="${ARPWATCH_INTERFACES:-}"
ARPWATCH_OPTS="${ARPWATCH_OPTS:-}"
ARPWATCH_DATA_DIR="${ARPWATCH_DATA_DIR:-/var/lib/arpwatch}"

# Color output for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Signal handling
trap 'log_info "Received SIGTERM, shutting down..."; exit 0' TERM
trap 'log_info "Received SIGINT, shutting down..."; exit 0' INT

# Build arpwatch command arguments
build_arpwatch_args() {
    local -a args=()

    # Add interface argument
    # Note: arpwatch only supports one interface per instance
    # For multiple interfaces, run multiple containers
    local iface
    iface=$(echo "$ARPWATCH_INTERFACES" | xargs)  # Trim whitespace

    if [[ -n "$iface" ]]; then
        # Warn if multiple interfaces specified
        if [[ "$iface" == *","* ]]; then
            log_warn "Multiple interfaces specified: $iface" >&2
            log_warn "Arpwatch only supports one interface per instance" >&2
            log_warn "Using first interface only. Run separate containers for each interface." >&2
            iface=$(echo "$iface" | cut -d',' -f1 | xargs)
        fi

        args+=("-i" "$iface")
        log_info "Monitoring interface: $iface" >&2

        # Create data file for this interface if it doesn't exist
        local datafile="${ARPWATCH_DATA_DIR}/${iface}.dat"
        if [[ ! -f "$datafile" ]]; then
            touch "$datafile" 2>/dev/null || log_warn "Cannot create $datafile" >&2
        fi

        # Explicitly specify data file
        args+=("-f" "$datafile")
    fi

    # Add network filter if specified
    if [[ -n "$ARPWATCH_NETWORK" ]]; then
        args+=("-n" "$ARPWATCH_NETWORK")
        log_info "Network filter: $ARPWATCH_NETWORK" >&2
    fi

    # Add additional options
    if [[ -n "$ARPWATCH_OPTS" ]]; then
        # Parse ARPWATCH_OPTS and add to args
        read -ra OPTS <<< "$ARPWATCH_OPTS"
        args+=("${OPTS[@]}")
    fi

    # Run in foreground without daemonizing
    # -N prevents daemonization (required for containers)
    args+=("-N")

    # Drop privileges to arpwatch user after opening network interface
    # This is required because we run as root to open raw sockets
    args+=("-u" "arpwatch")

    echo "${args[@]}"
}

# Main execution
main() {
    # If arguments are passed (and it's not "arpwatch"), execute them directly (for testing/debugging)
    if [[ $# -gt 0 && "$1" != "arpwatch" ]]; then
        exec "$@"
    fi

    log_info "Starting arpwatch container..."
    log_info "Version: ${VERSION:-unknown}"
    log_info "Data directory: $ARPWATCH_DATA_DIR"

    # Validate interfaces are provided
    if [[ -z "$ARPWATCH_INTERFACES" ]]; then
        log_error "No interfaces specified. Set ARPWATCH_INTERFACES environment variable."
        log_error "Example: ARPWATCH_INTERFACES=eth0,eth1"
        exit 1
    fi

    # Check if running as root (required for opening raw sockets)
    if [[ "$(id -u)" != "0" ]]; then
        log_error "Container must run as root to open raw sockets"
        log_error "Arpwatch will drop privileges to arpwatch user via -u flag"
        exit 1
    fi

    # Build command arguments
    local -a arpwatch_args
    IFS=' ' read -ra arpwatch_args <<< "$(build_arpwatch_args)"

    # Log the full command
    log_info "Executing: arpwatch ${arpwatch_args[*]}"

    # Create temporary file to capture stderr
    STDERR_LOG=$(mktemp)

    # Execute arpwatch in background with merged stdout/stderr
    # Capture stderr separately for error reporting while also allowing output to show
    # shellcheck disable=SC2068
    arpwatch ${arpwatch_args[@]} 2>&1 | tee -a "$STDERR_LOG" &
    ARPWATCH_PID=$!

    # Wait a moment for arpwatch to initialize
    sleep 2

    # Check if arpwatch process is running
    if ! pgrep -u arpwatch arpwatch >/dev/null 2>&1; then
        log_error "Arpwatch failed to start"
        log_error ""

        # Display captured stderr if available
        if [ -s "$STDERR_LOG" ]; then
            log_error "Arpwatch output:"
            while IFS= read -r line; do
                log_error "  $line"
            done < "$STDERR_LOG"
            log_error ""
        fi

        log_error "Common causes:"
        log_error "  - Invalid interface name (check: ip link show)"
        log_error "  - Missing required capabilities (NET_RAW, NET_ADMIN)"
        log_error "  - Network mode not set to 'host'"
        log_error "  - Permission issues with data directory"
        log_error "  - Running on Docker Desktop (limited packet capture support)"

        rm -f "$STDERR_LOG"
        exit 1
    fi

    # Clean up stderr log
    rm -f "$STDERR_LOG"

    log_info "Arpwatch started successfully"

    # Keep container alive by waiting for arpwatch
    # Note: arpwatch may fork, so we wait for any arpwatch process
    while pgrep -u arpwatch arpwatch >/dev/null 2>&1; do
        sleep 10
    done

    log_warn "Arpwatch process exited"
    exit 1
}

# Run main function if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
