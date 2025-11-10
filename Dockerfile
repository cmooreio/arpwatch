FROM cmooreio/dhi-debian-base:trixie

# Build arguments
ARG VERSION=2.1a15
ARG DEBIAN_VERSION=trixie
ARG BUILD_DATE
ARG VCS_REF

# Environment variables for arpwatch configuration
# These can be overridden at runtime via docker run -e or docker-compose
# Note: ARPWATCH_INTERFACES must be set at runtime (no default)
# This image is designed for logs-only (no email functionality)
ENV ARPWATCH_OPTS="" \
    ARPWATCH_NETWORK="" \
    ARPWATCH_DATA_DIR="/var/lib/arpwatch" \
    ARPWATCH_SKIP_PRIVILEGE_DROP="false"

# OCI Labels
LABEL org.opencontainers.image.title="arpwatch" \
      org.opencontainers.image.description="Security-hardened arpwatch network monitoring running on Debian Trixie" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.authors="cmooreio" \
      org.opencontainers.image.url="https://github.com/cmooreio/arpwatch" \
      org.opencontainers.image.source="https://github.com/cmooreio/arpwatch" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="cmooreio" \
      io.cmooreio.arpwatch.version="${VERSION}" \
      io.cmooreio.arpwatch.debian.version="${DEBIAN_VERSION}"

# Single RUN statement to minimize layers
RUN set -eux; \
    # Update and upgrade packages
    apt-get update && \
    apt-get upgrade -y && \
    # Install arpwatch and required dependencies
    apt-get install -y --no-install-recommends \
        arpwatch \
        ca-certificates \
        iproute2 \
        procps \
        libcap2-bin \
    && \
    # Debian package creates arpwatch user (UID 100), modify to UID 102 for consistency
    # First remove the user created by the package
    userdel -r arpwatch || true && \
    groupdel arpwatch || true && \
    # Create arpwatch user and group with UID/GID 102
    groupadd -r -g 102 arpwatch && \
    useradd -r -u 102 -g arpwatch -s /sbin/nologin -d /var/lib/arpwatch -c "Arpwatch User" arpwatch && \
    # Create required directories with proper permissions
    # Directories owned by arpwatch user for both modes:
    # - Default: Container runs as root, arpwatch drops to arpwatch user via -u flag
    # - Kubernetes: Container runs as arpwatch user from start (ARPWATCH_SKIP_PRIVILEGE_DROP=true)
    mkdir -p /var/lib/arpwatch /var/log/arpwatch && \
    chown -R arpwatch:arpwatch /var/lib/arpwatch /var/log/arpwatch && \
    chmod 755 /var/lib/arpwatch /var/log/arpwatch && \
    # Set file capabilities on arpwatch binary for Kubernetes mode
    # This allows arpwatch to open raw sockets when running as non-root (UID 102)
    # Required for ARPWATCH_SKIP_PRIVILEGE_DROP=true mode
    setcap cap_net_raw,cap_net_admin=+ep /usr/sbin/arpwatch && \
    # Clean up apt cache to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    # Verify arpwatch installation
    arpwatch -v || true

# Create entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    chown root:root /usr/local/bin/docker-entrypoint.sh

# Note: Container runs as root because arpwatch needs root to open raw sockets
# Arpwatch will drop privileges to arpwatch user via -u flag in entrypoint
# This is the recommended approach for arpwatch in containers

# Working directory
WORKDIR /var/lib/arpwatch

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -u arpwatch arpwatch || exit 1

# Entrypoint and command
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["arpwatch"]
