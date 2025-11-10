.PHONY: help all check-deps validate lint build build-nc build-single build-multi dry-run test smoke-test integration-test security-test scan scan-all sbom sign verify verify-key push push-signed clean clean-all update-versions docs version ci release release-signed

# Load version configuration
include versions.env

# Auto-detect architecture
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
    NATIVE_ARCH := amd64
else ifeq ($(UNAME_M),aarch64)
    NATIVE_ARCH := arm64
else ifeq ($(UNAME_M),arm64)
    NATIVE_ARCH := arm64
else
    $(error Unsupported architecture: $(UNAME_M))
endif

# Docker image configuration
IMAGE_REPO := cmooreio/arpwatch
IMAGE_TAG := $(VERSION)
IMAGE_NAME := $(IMAGE_REPO):$(IMAGE_TAG)
IMAGE_LATEST := $(IMAGE_REPO):latest

# Extract major.minor from version
MAJOR_MINOR := $(shell echo $(VERSION) | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
IMAGE_MAJOR_MINOR := $(IMAGE_REPO):$(MAJOR_MINOR)

# Platform configuration
NATIVE_PLATFORM := linux/$(NATIVE_ARCH)
MULTI_PLATFORMS := linux/amd64,linux/arm64

# Build arguments
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

BUILD_ARGS := --build-arg VERSION=$(VERSION) \
              --build-arg DEBIAN_VERSION=$(DEBIAN_VERSION) \
              --build-arg BUILD_DATE=$(BUILD_DATE) \
              --build-arg VCS_REF=$(VCS_REF)

# Docker buildx configuration
BUILDER_NAME := arpwatch-builder
BUILDX_ARGS := --builder $(BUILDER_NAME) \
               $(BUILD_ARGS) \
               --sbom=true \
               --provenance=true

# Scan tool preference
SCAN_TOOL := $(shell command -v trivy 2>/dev/null || command -v grype 2>/dev/null || echo "")

# ============================================================================
# General Targets
# ============================================================================

help: ## Display this help message
	@echo "Arpwatch Docker Image Build System"
	@echo ""
	@echo "Current Configuration:"
	@echo "  Version:          $(VERSION)"
	@echo "  Debian Version:   $(DEBIAN_VERSION)"
	@echo "  Image:            $(IMAGE_NAME)"
	@echo "  Native Platform:  $(NATIVE_PLATFORM)"
	@echo "  Multi Platforms:  $(MULTI_PLATFORMS)"
	@echo "  Build Date:       $(BUILD_DATE)"
	@echo "  VCS Ref:          $(VCS_REF)"
	@echo ""
	@echo "Quick Start:"
	@echo "  make build        # Build for native platform (fast)"
	@echo "  make test         # Run all tests"
	@echo "  make scan         # Security scan"
	@echo "  make push         # Build multi-platform and push to registry"
	@echo ""
	@echo "\033[1mAvailable Targets:\033[0m"
	@echo ""
	@awk '/^# General Targets/,/^# Development Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mGeneral:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Development Targets/,/^# Building Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mDevelopment:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Building Targets/,/^# Testing Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mBuilding:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Testing Targets/,/^# Security Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mTesting:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Security Targets/,/^# Publishing Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mSecurity:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Publishing Targets/,/^# Maintenance Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mPublishing:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Maintenance Targets/,/^# Documentation Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mMaintenance:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# Documentation Targets/,/^# CI\/CD Targets/ { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mDocumentation:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@awk '/^# CI\/CD Targets/,0 { \
		if ($$0 ~ /^[a-zA-Z_-]+:.*?## /) { \
			split($$0, a, ":.*?## "); \
			if (section == 0) { printf "\n\033[33mCI/CD:\033[0m\n"; section = 1; } \
			printf "  \033[36m%-20s\033[0m %s\n", a[1], a[2]; \
		} \
	}' Makefile
	@echo ""

all: validate lint build test scan ## Run complete build pipeline (validate, lint, build, test, scan)

check-deps: ## Check required dependencies
	@echo "Checking dependencies..."
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is required but not installed"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: git is required but not installed"; exit 1; }
	@docker buildx version >/dev/null 2>&1 || { echo "Error: docker buildx is required"; exit 1; }
	@echo "All required dependencies are installed"

# ============================================================================
# Development Targets
# ============================================================================

validate: ## Validate versions.env and configuration
	@echo "Validating configuration..."
	@test -n "$(VERSION)" || { echo "Error: VERSION not set in versions.env"; exit 1; }
	@test -n "$(DEBIAN_VERSION)" || { echo "Error: DEBIAN_VERSION not set in versions.env"; exit 1; }
	@echo "✓ Configuration valid"

lint: ## Lint Dockerfile and shell scripts
	@echo "Linting Dockerfile..."
	@command -v hadolint >/dev/null 2>&1 && hadolint Dockerfile || echo "hadolint not installed, skipping"
	@echo "Linting shell scripts..."
	@command -v shellcheck >/dev/null 2>&1 && find . -name "*.sh" -exec shellcheck {} + || echo "shellcheck not installed, skipping"

# ============================================================================
# Building Targets
# ============================================================================

build: check-deps validate ## Build Docker image for native platform (default, fast)
	@echo "Building for native platform: $(NATIVE_PLATFORM)"
	@./build.sh --platform $(NATIVE_PLATFORM)

build-nc: check-deps validate ## Build without cache (native platform)
	@echo "Building without cache for: $(NATIVE_PLATFORM)"
	@./build.sh --platform $(NATIVE_PLATFORM) --no-cache

build-single: check-deps validate ## Build for single platform (auto-detected)
	@echo "Building single platform image: $(NATIVE_PLATFORM)"
	@./build.sh --platform $(NATIVE_PLATFORM)

build-multi: check-deps validate ## Build for multiple platforms (amd64 + arm64, slow with QEMU)
	@echo "Building multi-platform image: $(MULTI_PLATFORMS)"
	@echo "WARNING: This will take significantly longer due to QEMU emulation"
	@./build.sh --platform $(MULTI_PLATFORMS)

dry-run: check-deps validate ## Show build command without executing
	@echo "Dry run mode - showing command that would be executed:"
	@./build.sh --platform $(NATIVE_PLATFORM) --dry-run

# ============================================================================
# Testing Targets
# ============================================================================

test: smoke-test integration-test security-test ## Run all tests (smoke + integration + security)

smoke-test: ## Run smoke tests (basic functionality)
	@echo "Running smoke tests..."
	@cd tests && ./smoke_test.sh

integration-test: ## Run integration tests
	@echo "Running integration tests..."
	@cd tests && ./integration_test.sh

security-test: ## Run security tests
	@echo "Running security tests..."
	@cd tests && ./security_test.sh

# ============================================================================
# Security Targets
# ============================================================================

scan: ## Security scan with available tool (trivy or grype)
	@if [ -z "$(SCAN_TOOL)" ]; then \
		echo "No security scanner found. Install trivy or grype:"; \
		echo "  brew install trivy"; \
		echo "  brew install grype"; \
		exit 1; \
	fi
	@echo "Scanning $(IMAGE_LATEST) with $(notdir $(SCAN_TOOL))..."
	@if [ "$(notdir $(SCAN_TOOL))" = "trivy" ]; then \
		trivy image --severity HIGH,CRITICAL $(IMAGE_LATEST); \
	else \
		grype $(IMAGE_LATEST); \
	fi

scan-all: ## Deep security scan with all severity levels
	@if [ -z "$(SCAN_TOOL)" ]; then \
		echo "No security scanner found"; \
		exit 1; \
	fi
	@echo "Deep scanning $(IMAGE_LATEST)..."
	@if [ "$(notdir $(SCAN_TOOL))" = "trivy" ]; then \
		trivy image --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL $(IMAGE_LATEST); \
	else \
		grype $(IMAGE_LATEST); \
	fi

sbom: ## Generate Software Bill of Materials
	@echo "Generating SBOM for $(IMAGE_LATEST)..."
	@if command -v syft >/dev/null 2>&1; then \
		syft $(IMAGE_LATEST) -o json > sbom-$(VERSION).json; \
		echo "SBOM saved to sbom-$(VERSION).json"; \
	else \
		echo "syft not installed. Install with: brew install syft"; \
		exit 1; \
	fi

sign: ## Sign image with cosign
	@echo "Signing image $(IMAGE_LATEST)..."
	@if command -v cosign >/dev/null 2>&1; then \
		cosign sign $(IMAGE_LATEST); \
	else \
		echo "cosign not installed. Install with: brew install cosign"; \
		exit 1; \
	fi

verify: ## Verify image signature
	@echo "Verifying image signature..."
	@if command -v cosign >/dev/null 2>&1; then \
		cosign verify $(IMAGE_LATEST); \
	else \
		echo "cosign not installed"; \
		exit 1; \
	fi

verify-key: ## Verify image signature with public key
	@echo "Verifying with public key..."
	@if command -v cosign >/dev/null 2>&1; then \
		cosign verify --key cosign.pub $(IMAGE_LATEST); \
	else \
		echo "cosign not installed"; \
		exit 1; \
	fi

# ============================================================================
# Publishing Targets
# ============================================================================

push: check-deps validate ## Build multi-platform and push to registry
	@echo "This will build and push $(IMAGE_REPO) to Docker Hub"
	@echo "Tags: latest, $(VERSION), $(MAJOR_MINOR)"
	@echo "Platforms: $(MULTI_PLATFORMS)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		./build.sh --platform $(MULTI_PLATFORMS) --push; \
	else \
		echo "Push cancelled"; \
	fi

push-signed: push sign ## Push and sign image

# ============================================================================
# Maintenance Targets
# ============================================================================

clean: ## Remove local images
	@echo "Removing local images..."
	@docker rmi $(IMAGE_LATEST) $(IMAGE_NAME) $(IMAGE_MAJOR_MINOR) 2>/dev/null || true
	@echo "Cleanup complete"

clean-all: clean ## Remove all build artifacts and builder
	@echo "Removing build artifacts..."
	@rm -f sbom-*.json
	@docker buildx rm $(BUILDER_NAME) 2>/dev/null || true
	@echo "Deep cleanup complete"

update-versions: ## Update BUILD_DATE and VCS_REF in versions.env
	@echo "Updating versions.env with current build info..."
	@sed -i.bak "s/^BUILD_DATE=.*/BUILD_DATE=$(BUILD_DATE)/" versions.env
	@sed -i.bak "s/^VCS_REF=.*/VCS_REF=$(VCS_REF)/" versions.env
	@rm -f versions.env.bak
	@echo "✓ Updated BUILD_DATE=$(BUILD_DATE)"
	@echo "✓ Updated VCS_REF=$(VCS_REF)"

# ============================================================================
# Documentation Targets
# ============================================================================

docs: ## Generate documentation
	@echo "Documentation:"
	@echo "  README.md       - User documentation"
	@echo "  CLAUDE.md       - Claude Code instructions"
	@echo "  Makefile        - This file (run 'make help')"

version: ## Show version information
	@echo "Arpwatch Docker Image Version Information"
	@echo "=========================================="
	@echo "Arpwatch Version:  $(VERSION)"
	@echo "Debian Version:    $(DEBIAN_VERSION)"
	@echo "Image Repository:  $(IMAGE_REPO)"
	@echo "Image Tags:"
	@echo "  - latest:        $(IMAGE_LATEST)"
	@echo "  - version:       $(IMAGE_NAME)"
	@echo "  - major.minor:   $(IMAGE_MAJOR_MINOR)"
	@echo ""
	@echo "Build Information:"
	@echo "  Build Date:      $(BUILD_DATE)"
	@echo "  VCS Revision:    $(VCS_REF)"
	@echo "  Native Arch:     $(NATIVE_ARCH)"
	@echo "  Native Platform: $(NATIVE_PLATFORM)"
	@echo ""
	@echo "Platform Support:"
	@echo "  Single:          $(NATIVE_PLATFORM)"
	@echo "  Multi:           $(MULTI_PLATFORMS)"

# ============================================================================
# CI/CD Targets
# ============================================================================

ci: validate lint build test scan ## CI pipeline (validate, lint, build, test, scan)
	@echo "CI pipeline complete ✓"

release: validate lint build-multi test scan ## Build release (multi-platform, tested, scanned)
	@echo "Release build complete. Ready to push."
	@echo "Run 'make push' to publish to registry."

release-signed: release push-signed ## Full release with signing
	@echo "Signed release complete ✓"
