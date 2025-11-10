# arpwatch

[![Docker Hub](https://img.shields.io/docker/v/cmooreio/arpwatch?sort=semver)](https://hub.docker.com/r/cmooreio/arpwatch)
[![Docker Image Size](https://img.shields.io/docker/image-size/cmooreio/arpwatch/latest)](https://hub.docker.com/r/cmooreio/arpwatch)
[![Docker Pulls](https://img.shields.io/docker/pulls/cmooreio/arpwatch)](https://hub.docker.com/r/cmooreio/arpwatch)
[![License](https://img.shields.io/github/license/cmooreio/arpwatch)](LICENSE)

Security-hardened arpwatch network monitoring tool running on Debian Trixie.

## Features

- **Security Hardened**: Non-root user, read-only filesystem compatible, minimal attack surface
- **Configurable**: Full configuration via environment variables
- **Multi-Platform**: Supports linux/amd64 and linux/arm64
- **Production Ready**: Comprehensive testing, health checks, and resource limits
- **Supply Chain Security**: SBOM and provenance attestations included

## Quick Start

### Using Docker Run

```bash
docker run -d \
  --name arpwatch \
  --net=host \
  --cap-drop=ALL \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0" \
  -v arpwatch-data:/var/lib/arpwatch \
  cmooreio/arpwatch:latest
```

### Using Docker Compose

```yaml
version: '3.8'

services:
  arpwatch:
    image: cmooreio/arpwatch:latest
    container_name: arpwatch
    network_mode: host
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_RAW
      - NET_ADMIN
    environment:
      ARPWATCH_INTERFACES: "eth0"
    tmpfs:
      - /tmp:uid=102,gid=102,mode=1777
      - /var/tmp:uid=102,gid=102,mode=1777
      - /run:uid=102,gid=102,mode=755
    volumes:
      - arpwatch-data:/var/lib/arpwatch:rw
      - arpwatch-logs:/var/log/arpwatch:rw
    restart: unless-stopped

volumes:
  arpwatch-data:
  arpwatch-logs:
```

Then run:

```bash
docker compose up -d
```

## Configuration

Arpwatch is configured entirely through environment variables:

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ARPWATCH_INTERFACES` | Yes | - | Comma-separated list of interfaces to monitor (e.g., `eth0` or `eth0,eth1,wlan0`) |
| `ARPWATCH_NETWORK` | No | - | Network filter in CIDR notation (e.g., `192.168.1.0/24`) |
| `ARPWATCH_OPTS` | No | `-u arpwatch -p` | Additional arpwatch command-line options |
| `ARPWATCH_DATA_DIR` | No | `/var/lib/arpwatch` | Data directory path |

### Examples

#### Single Interface

```bash
docker run -d \
  --net=host \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0" \
  cmooreio/arpwatch:latest
```

#### Multiple Interfaces with Network Filtering

```bash
docker run -d \
  --net=host \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0,eth1,wlan0" \
  -e ARPWATCH_NETWORK="192.168.0.0/16" \
  cmooreio/arpwatch:latest
```

#### Production Deployment with Security Hardening

```bash
docker run -d \
  --name arpwatch \
  --net=host \
  --read-only \
  --cap-drop=ALL \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  --security-opt=no-new-privileges:true \
  --tmpfs /tmp:uid=102,gid=102,mode=1777 \
  --tmpfs /var/tmp:uid=102,gid=102,mode=1777 \
  --tmpfs /run:uid=102,gid=102,mode=755 \
  -v arpwatch-data:/var/lib/arpwatch:rw \
  -v arpwatch-logs:/var/log/arpwatch:rw \
  -e ARPWATCH_INTERFACES="eth0" \
  cmooreio/arpwatch:latest
```

## Security Features

This image implements multiple security best practices:

| Feature | Implementation |
|---------|----------------|
| **Non-Root User** | Runs as arpwatch user (UID 102, GID 102) |
| **Read-Only Filesystem** | Fully compatible with `--read-only` flag |
| **Capability Reduction** | Only requires NET_RAW and NET_ADMIN |
| **No Privilege Escalation** | `no-new-privileges:true` security option |
| **Minimal Base** | Built on debian:trixie-slim |
| **Resource Limits** | CPU and memory limits configured |
| **Health Check** | Built-in health monitoring |
| **SBOM & Provenance** | Software Bill of Materials and build attestations |

## Version Information

- **Arpwatch Version**: 2.1a15
- **Base Image**: Debian Trixie Slim
- **Platforms**: linux/amd64, linux/arm64

## Requirements

- **Platform**: Linux host with direct hardware access (native Linux, not Docker Desktop)
- **Network Mode**: Must use host network mode (`--net=host`) to access network interfaces
- **Capabilities**: Requires NET_RAW and NET_ADMIN for packet capture
- **Interfaces**: At least one network interface must be specified via ARPWATCH_INTERFACES

### Docker Desktop Limitations

**Important**: This image requires direct access to network interfaces for packet capture. **Docker Desktop (macOS/Windows) has limited support** for low-level network operations and arpwatch may not function correctly.

For production use, deploy on:
- Native Linux hosts
- Linux VMs with direct network access
- Kubernetes clusters on Linux nodes

## Data Persistence

Arpwatch stores its ARP database in `/var/lib/arpwatch`. To persist data across container restarts:

```bash
-v arpwatch-data:/var/lib/arpwatch:rw
```

Each monitored interface gets its own data file:
- `/var/lib/arpwatch/eth0.dat`
- `/var/lib/arpwatch/eth1.dat`
- etc.

## Logs

Logs are written to `/var/log/arpwatch`. To persist logs:

```bash
-v arpwatch-logs:/var/log/arpwatch:rw
```

## Health Check

The image includes a built-in health check that verifies the arpwatch process is running:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -u arpwatch arpwatch || exit 1
```

## Troubleshooting

### Container exits immediately

**Problem**: Container starts and immediately exits.

**Solution**: Ensure ARPWATCH_INTERFACES is set:
```bash
docker logs <container-name>
# Should show: "No interfaces specified. Set ARPWATCH_INTERFACES environment variable."
```

### No ARP data being captured

**Problem**: Arpwatch runs but captures no ARP traffic.

**Solutions**:
1. Verify interfaces exist and are up:
   ```bash
   docker exec <container> ip link show
   ```

2. Ensure host network mode is enabled:
   ```bash
   docker inspect <container> | grep NetworkMode
   # Should show: "NetworkMode": "host"
   ```

3. Check capabilities are added:
   ```bash
   docker inspect <container> | grep -A 5 CapAdd
   # Should show: NET_RAW and NET_ADMIN
   ```

### Permission denied errors

**Problem**: Permission errors in logs.

**Solutions**:
1. Ensure tmpfs mounts have correct ownership:
   ```bash
   --tmpfs /tmp:uid=102,gid=102,mode=1777
   ```

2. Check volume permissions:
   ```bash
   docker exec <container> ls -la /var/lib/arpwatch
   # Should show: arpwatch:arpwatch
   ```

### Logs-only design

**Note**: This image is designed for logs-only operation and does not include email notification functionality. All ARP activity is logged to `/var/log/arpwatch` and can be monitored through:
1. Docker logs: `docker logs <container>`
2. Log aggregation services (ELK, Splunk, etc.)
3. External monitoring tools that parse log files

## For Developers

### Prerequisites

- Docker with buildx support
- Git
- GNU Make
- (Optional) trivy or grype for security scanning
- (Optional) cosign for image signing

### Quick Start

```bash
# Clone repository
git clone https://github.com/cmooreio/arpwatch.git
cd arpwatch

# Build image
make build

# Run tests
make test

# Security scan
make scan
```

### Development Workflow

```bash
# Validate configuration
make validate

# Lint Dockerfile and scripts
make lint

# Build for native platform (fast)
make build

# Run all tests
make test

# Security scan
make scan

# Build multi-platform for release
make build-multi

# Push to registry
make push
```

### Testing

The project includes comprehensive tests:

```bash
make test              # Run all tests
make smoke-test        # Basic functionality
make integration-test  # Integration tests
make security-test     # Security validation
```

### Build Targets

| Target | Description |
|--------|-------------|
| `make help` | Show all available targets |
| `make build` | Build for native platform |
| `make build-multi` | Build for all platforms |
| `make test` | Run all test suites |
| `make scan` | Security vulnerability scan |
| `make push` | Build and push to registry |
| `make clean` | Remove local images |

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details

## Support

- **Issues**: [GitHub Issues](https://github.com/cmooreio/arpwatch/issues)
- **Docker Hub**: [cmooreio/arpwatch](https://hub.docker.com/r/cmooreio/arpwatch)

## Acknowledgments

- Arpwatch project: [arpwatch](https://ee.lbl.gov/)
- Debian project for the base image

---

**Note**: This is an unofficial Docker image for arpwatch. It is not affiliated with or endorsed by the original arpwatch project.
