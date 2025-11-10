#!/bin/bash
set -e

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

    # Add interface-specific arguments
    IFS=',' read -ra INTERFACES <<< "$ARPWATCH_INTERFACES"
    for iface in "${INTERFACES[@]}"; do
        iface=$(echo "$iface" | xargs)  # Trim whitespace
        if [[ -n "$iface" ]]; then
            args+=("-i" "$iface")
            log_info "Monitoring interface: $iface" >&2

            # Create data file for this interface if it doesn't exist
            local datafile="${ARPWATCH_DATA_DIR}/${iface}.dat"
            if [[ ! -f "$datafile" ]]; then
                touch "$datafile" 2>/dev/null || log_warn "Cannot create $datafile" >&2
            fi
        fi
    done

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

    # Run in foreground with debug output
    # -d enables debug mode, -N prevents daemonization
    args+=("-d" "-N")

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

    # Check if running as arpwatch user
    if [[ "$(id -u)" != "102" ]]; then
        log_warn "Not running as arpwatch user (UID 102)"
    fi

    # Build command arguments
    local -a arpwatch_args
    IFS=' ' read -ra arpwatch_args <<< "$(build_arpwatch_args)"

    # Log the full command
    log_info "Executing: arpwatch ${arpwatch_args[*]}"

    # Execute arpwatch with proper error handling
    # shellcheck disable=SC2068
    arpwatch ${arpwatch_args[@]} &
    ARPWATCH_PID=$!

    # Wait for arpwatch to initialize
    sleep 1

    # Check if arpwatch is still running
    if ! kill -0 $ARPWATCH_PID 2>/dev/null; then
        log_error "Arpwatch failed to start or exited immediately"
        log_error "This may be due to:"
        log_error "  - Invalid interface name"
        log_error "  - Missing required capabilities (NET_RAW, NET_ADMIN)"
        log_error "  - Network mode not set to 'host'"
        log_error "  - Running on Docker Desktop (limited packet capture support)"
        exit 1
    fi

    log_info "Arpwatch started successfully (PID: $ARPWATCH_PID)"

    # Wait for arpwatch process to exit
    wait $ARPWATCH_PID
    EXIT_CODE=$?
    log_warn "Arpwatch exited with code: $EXIT_CODE"
    exit $EXIT_CODE
}

# Run main function if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
