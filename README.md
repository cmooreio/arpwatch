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
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0" \
  -v arpwatch-data:/var/lib/arpwatch \
  cmooreio/arpwatch:latest
```

### Using Docker Compose

```yaml
services:
  arpwatch:
    image: cmooreio/arpwatch:latest
    container_name: arpwatch
    network_mode: host
    security_opt:
      - no-new-privileges:true
    cap_add:
      - NET_RAW
      - NET_ADMIN
    environment:
      ARPWATCH_INTERFACES: "eth0"
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
| `ARPWATCH_INTERFACES` | Yes | - | Network interface to monitor (e.g., `eth0`). Only one interface per container. For multiple interfaces, run multiple containers. |
| `ARPWATCH_NETWORK` | No | - | Network filter in CIDR notation (e.g., `192.168.1.0/24`) |
| `ARPWATCH_OPTS` | No | - | Additional arpwatch command-line options (added after `-N -u arpwatch`) |
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

#### Single Interface with Network Filtering

```bash
docker run -d \
  --net=host \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0" \
  -e ARPWATCH_NETWORK="192.168.0.0/16" \
  -v arpwatch-data:/var/lib/arpwatch \
  cmooreio/arpwatch:latest
```

**Note**: Arpwatch supports one interface per instance. For multiple interfaces, run separate containers:

```bash
# Container for eth0
docker run -d --name arpwatch-eth0 --net=host \
  --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth0" \
  -v arpwatch-eth0:/var/lib/arpwatch \
  cmooreio/arpwatch:latest

# Container for eth1
docker run -d --name arpwatch-eth1 --net=host \
  --cap-add=NET_RAW --cap-add=NET_ADMIN \
  -e ARPWATCH_INTERFACES="eth1" \
  -v arpwatch-eth1:/var/lib/arpwatch \
  cmooreio/arpwatch:latest
```

#### Production Deployment with Security Hardening

```bash
docker run -d \
  --name arpwatch \
  --net=host \
  --cap-add=NET_RAW \
  --cap-add=NET_ADMIN \
  --security-opt=no-new-privileges:true \
  -v arpwatch-data:/var/lib/arpwatch:rw \
  -v arpwatch-logs:/var/log/arpwatch:rw \
  -e ARPWATCH_INTERFACES="eth0" \
  cmooreio/arpwatch:latest
```

## Security Features

This image implements multiple security best practices:

| Feature | Implementation |
|---------|----------------|
| **Privilege Dropping** | Container starts as root, arpwatch drops privileges to arpwatch user (UID 102) via `-u` flag after opening network sockets |
| **Minimal Capabilities** | Only requires NET_RAW and NET_ADMIN capabilities |
| **No Privilege Escalation** | `no-new-privileges:true` security option prevents further privilege escalation |
| **Single Interface** | One container per interface reduces attack surface |
| **Minimal Base** | Built on debian:trixie-slim for smaller attack surface |
| **Resource Limits** | CPU and memory limits configured in docker-compose |
| **Health Check** | Built-in monitoring verifies arpwatch process is running |
| **SBOM & Provenance** | Software Bill of Materials and build attestations included |

### Security Model

Arpwatch requires root privileges to open raw network sockets for packet capture. This image follows the recommended security pattern:

1. **Container starts as root** - Required to open raw sockets and bind to network interfaces
2. **Arpwatch drops privileges** - After initialization, arpwatch switches to the non-privileged `arpwatch` user (UID 102)
3. **Packet processing as non-root** - All packet capture and processing runs as the arpwatch user

This approach provides the necessary privileges for initialization while minimizing the attack surface during normal operation.

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

Each container monitors one interface and stores its data in `/var/lib/arpwatch/<interface>.dat`. For example:
- Container monitoring `eth0` creates `/var/lib/arpwatch/eth0.dat`
- Container monitoring `eth1` creates `/var/lib/arpwatch/eth1.dat`

When running multiple containers, use separate volumes for each interface to avoid conflicts.

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
