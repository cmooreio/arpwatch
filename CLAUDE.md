# CLAUDE.md

Instructions for Claude Code when working with this arpwatch Docker image project.

## Quick Reference

**Build**: `make build` (native platform, fast) or `make build-multi` (all platforms, slow)
**Test**: `make test` or `docker compose up -d`
**Versions**: All in `versions.env`
**Base**: Debian Trixie Slim
**Registry**: cmooreio/arpwatch
**User**: arpwatch (UID 102, GID 102)
**Design**: Logs-only (no email functionality)

## Key Commands

```bash
make build       # Build native (linux/arm64 or linux/amd64)
make build-multi # Build multi-platform (amd64 + arm64, slow)
make test        # Run all tests (smoke + integration + security)
make scan        # Security scan
make version     # Show versions and detected platform
```

## Build Architecture

**Optimized Dockerfile** with minimal layers:
1. Install arpwatch and minimal dependencies
2. Create arpwatch user (UID 102, GID 102)
3. Create required directories with proper permissions
4. Add entrypoint script for configuration
5. Set up health check and non-root user

**Security**:
- Non-root user (102:102)
- Read-only filesystem compatible
- No setuid/setgid binaries
- Minimal package installation
- Health check configured

## Important Files

- **Dockerfile**: Multi-stage build, Debian Trixie Slim base
- **docker-entrypoint.sh**: Configuration handler and startup script
- **Makefile**: Auto-detects architecture, provides targets
- **build.sh**: Build script (used by Makefile)
- **versions.env**: Single source of truth for versions
- **docker-compose.yml**: Hardened production deployment

## Configuration

### Environment Variables

Arpwatch configuration is done entirely through environment variables:

- **ARPWATCH_INTERFACES** (required): Comma-separated list of interfaces to monitor
  - Example: `"eth0"` or `"eth0,eth1,wlan0"`
- **ARPWATCH_NETWORK** (optional): Network filter in CIDR notation
  - Example: `"192.168.1.0/24"` or `"10.0.0.0/8"`
- **ARPWATCH_OPTS** (optional): Additional arpwatch options
  - Default: `"-u arpwatch -p"`
- **ARPWATCH_DATA_DIR** (optional): Data directory path
  - Default: `"/var/lib/arpwatch"`

**Note**: This image is designed for logs-only operation and does not include email notification functionality.

### Example Usage

```bash
# Single interface
docker run -d \
  --net=host \
  --cap-drop=ALL \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0" \
  cmooreio/arpwatch:latest

# Multiple interfaces with network filtering
docker run -d \
  --net=host \
  --cap-drop=ALL \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0,eth1" \
  -e ARPWATCH_NETWORK="192.168.0.0/16" \
  cmooreio/arpwatch:latest
```

## Critical Rules

### Security
- **User**: arpwatch runs as UID 102, GID 102
- **Capabilities**: Requires NET_RAW and NET_ADMIN
- **Network Mode**: Must use host network mode to access interfaces
- **tmpfs**: Must use `uid=102,gid=102` in docker-compose.yml
- **Read-only FS**: Fully compatible with read-only root filesystem

### Dockerfile Changes
- Keep minimal layers
- Test read-only filesystem: `docker run --read-only --tmpfs /tmp:uid=102,gid=102 ...`
- Always test with `make test` after changes

### Build Performance
- **Native** (`make build`): 5-10 min, no emulation
- **Multi-platform** (`make build-multi`): 15-25 min with QEMU
- Use native for development, multi-platform for releases only

### Pushing Images

- **Atomic Multi-Tag Push**: `docker buildx build --push` with multiple `-t` flags pushes all tags atomically
- **Multiple tags pushed**: `latest`, `X.Y.Z` (version), and `X.Y` (major.minor)
- **Attestations**: Images include SBOM (`--sbom=true`) and provenance (`--provenance=true`) data
- **Verification**: Check with `docker buildx imagetools inspect cmooreio/arpwatch:<tag> --format '{{.Manifest.Digest}}'`
- All tags will have identical digests and attestations after push
- **Important**: Do not use `imagetools create` to re-tag after build, as it may interfere with attestations

### Common Tasks

- **Test changes**: `make build && make test`
- **Check platforms**: `make version`
- **Push to registry**: `make push` (builds multi-platform and syncs all tags)
- **Security scan**: `make scan`
- **Generate SBOM**: `make sbom`

## Testing

The project has a comprehensive three-tier test suite:

### Smoke Tests (`tests/smoke_test.sh`)
- Binary exists and is executable
- Version check works
- Non-root user validation
- Directory permissions
- Entrypoint script validation

### Integration Tests (`tests/integration_test.sh`)
- Environment variable configuration
- Data persistence
- Read-only filesystem compatibility
- docker-compose validation
- Network capabilities
- Required packages

### Security Tests (`tests/security_test.sh`)
- Running as non-root user
- USER directive configured
- No setuid/setgid binaries
- File permissions
- User shell restrictions
- OCI labels present
- No secrets in layers
- Image size validation
- Health check configured

Run all tests: `make test`

## Configuration Files

### .editorconfig
Ensures consistent coding style across different editors:
- Unix-style newlines (lf)
- UTF-8 charset
- Shell scripts: 4-space indent
- Dockerfile/YAML/JSON: 2-space indent
- Makefile: tab indent

### .pre-commit-config.yaml
Pre-commit hooks for code quality:
- trailing-whitespace, end-of-file-fixer
- shellcheck (shell script linting)
- hadolint (Dockerfile linting)
- commitizen (commit message formatting)
- detect-secrets (secret detection)
- yamllint, markdownlint

### renovate.json
Dependency automation configuration:
- Scheduled updates (Monday before 5am)
- Security priority for updates
- Labels for different update types
- Dependency dashboard enabled

## Build Script Features (build.sh)

The build.sh script is a secure build script with:

**Security Features**:
- No eval usage (security best practice)
- Interactive push confirmation
- Dry-run mode
- Input validation

**Build Configuration**:
- Multi-tag support (latest, version, major.minor)
- SBOM attestation with `--sbom=true`
- Provenance attestation with `--provenance=true`
- Platform auto-detection
- Vulnerability scanning integration
- Image signing with cosign

## Makefile Features

The Makefile provides comprehensive build automation with:

**Target Groups**:
1. **General**: help, all, check-deps
2. **Development**: validate, lint
3. **Building**: build, build-nc, build-single, build-multi, dry-run
4. **Testing**: test, smoke-test, integration-test, security-test
5. **Security**: scan, scan-all, sbom, sign, verify, verify-key
6. **Publishing**: push, push-signed
7. **Maintenance**: clean, clean-all, update-versions
8. **Documentation**: docs, version
9. **CI/CD**: ci, release, release-signed

**Platform Detection**:
- Auto-detects native architecture (arm64/amd64)
- Uses native platform by default for fast builds
- Multi-platform only for releases

## Docker Compose Features

The docker-compose.yml provides hardened production deployment:

**Security Hardening**:
- `read_only: true` - Read-only root filesystem
- `security_opt: no-new-privileges:true`
- `cap_drop: ALL` - Drops all capabilities
- `cap_add: NET_RAW, NET_ADMIN` - Only required capabilities
- `network_mode: host` - Access to network interfaces
- tmpfs mounts with correct UID/GID (102:102)
- Resource limits (CPU: 1, Memory: 256M)

**Required Configuration**:
```yaml
environment:
  ARPWATCH_INTERFACES: "eth0"  # REQUIRED
  # Optional:
  # ARPWATCH_NETWORK: "192.168.1.0/24"
```

## Image Registry

- **Current**: cmooreio/arpwatch
- **Tags**: latest, X.Y.Z, X.Y
- **Platforms**: linux/amd64, linux/arm64

## Arpwatch-Specific Notes

### Interface Monitoring
- Arpwatch monitors ARP traffic on specified network interfaces
- Requires host network mode (`--net=host`)
- Requires NET_RAW and NET_ADMIN capabilities for packet capture
- Each interface gets its own data file: `/var/lib/arpwatch/{interface}.dat`

### Logs-Only Design
- This image is designed for logs-only operation
- No email notification functionality included
- All ARP activity is logged to `/var/log/arpwatch`
- Monitor through Docker logs, log aggregation services, or external tools

### Data Persistence
- ARP database stored in `/var/lib/arpwatch`
- Mount as volume for persistence across container restarts
- Logs stored in `/var/log/arpwatch`

### Network Filtering
- Use ARPWATCH_NETWORK to filter by subnet
- Supports CIDR notation (e.g., `192.168.1.0/24`)
- Useful for multi-subnet environments

## Troubleshooting

### Container won't start / Arpwatch exits immediately
- Check ARPWATCH_INTERFACES is set
- Verify interfaces exist with `ip link show`
- Ensure NET_RAW and NET_ADMIN capabilities are added
- Check host network mode is enabled
- **Docker Desktop**: Arpwatch requires low-level network access that may not work on Docker Desktop (macOS/Windows). Deploy on native Linux for production.

### No ARP data captured
- Verify interfaces are up: `ip link show`
- Check container has required capabilities
- Verify network mode is set to host
- Review logs: `docker logs <container>`
- Ensure running on native Linux (not Docker Desktop)

### Permission errors
- Verify tmpfs mounts have `uid=102,gid=102`
- Check volume ownership: `ls -la /var/lib/arpwatch`
- Ensure read-only FS has proper tmpfs mounts

## Development Workflow

1. Make changes to Dockerfile or scripts
2. Run `make validate` to check configuration
3. Run `make lint` to check code quality
4. Build with `make build` (native, fast)
5. Test with `make test` (all test suites)
6. Scan for security issues: `make scan`
7. For release: `make build-multi` then `make push`

## Common Development Tasks

```bash
# Quick development cycle
make build test

# Full validation before commit
make validate lint build test scan

# Release workflow
make release          # Build multi-platform, test, scan
make push             # Interactive push to registry

# Clean up
make clean            # Remove images
make clean-all        # Remove images and build artifacts
```
