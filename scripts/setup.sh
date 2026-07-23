#!/bin/bash
# =============================================================
# Sentinel Project — Setup Script
# Run this on any new machine to get everything working
# Usage: ./scripts/setup.sh
# =============================================================

set -e  # stop on any error

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() { echo -e "\n${BLUE}==>${NC} $1"; }
print_ok()   { echo -e "${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_err()  { echo -e "${RED}❌ $1${NC}"; }

echo ""
echo "🕶️  SENTINEL PROJECT — SETUP"
echo "=============================="

# ── 1. Check Docker ──────────────────────────────────────────
print_step "Checking Docker..."
if ! command -v docker &> /dev/null; then
  print_err "Docker not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop"
  exit 1
fi
if ! docker ps &> /dev/null; then
  print_err "Docker is installed but not running. Start Docker Desktop first."
  exit 1
fi
print_ok "Docker is running"

# ── 2. Check Python ──────────────────────────────────────────
print_step "Checking Python..."
if ! command -v python3 &> /dev/null; then
  print_err "Python 3 not found. Install from https://python.org"
  exit 1
fi
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
print_ok "Python $PYTHON_VERSION found"

# ── 3. Install foundryctl ────────────────────────────────────
print_step "Installing foundryctl..."
if command -v foundryctl &> /dev/null; then
  print_ok "foundryctl already installed: $(foundryctl version 2>/dev/null || echo 'installed')"
else
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  # Normalize arch
  if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; fi
  if [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; fi

  DOWNLOAD_URL="https://github.com/SigNoz/foundry/releases/latest/download/foundry_${OS}_${ARCH}.tar.gz"

  echo "   Downloading foundryctl for ${OS}/${ARCH}..."
  curl -L "$DOWNLOAD_URL" -o /tmp/foundry.tar.gz

  tar -xzf /tmp/foundry.tar.gz -C /tmp/
  sudo mv /tmp/foundry_${OS}_${ARCH}/bin/foundryctl /usr/local/bin/
  rm -rf /tmp/foundry.tar.gz /tmp/foundry_${OS}_${ARCH}

  print_ok "foundryctl installed"
fi

# ── 4. Check Anthropic API Key ───────────────────────────────
print_step "Checking ANTHROPIC_API_KEY..."
if [ -z "$ANTHROPIC_API_KEY" ]; then
  print_warn "ANTHROPIC_API_KEY not set."
  echo "   Add this to your ~/.zshrc or ~/.bashrc:"
  echo "   export ANTHROPIC_API_KEY=your_key_here"
  echo "   Then run: source ~/.zshrc"
  echo ""
  read -p "   Enter your Anthropic API key now (or press Enter to skip): " API_KEY
  if [ -n "$API_KEY" ]; then
    export ANTHROPIC_API_KEY="$API_KEY"
    echo "export ANTHROPIC_API_KEY=$API_KEY" >> ~/.zshrc
    print_ok "API key saved to ~/.zshrc"
  else
    print_warn "Skipping. Set it before running the agents."
  fi
else
  print_ok "ANTHROPIC_API_KEY is set"
fi

# ── 5. Install Python deps for Worker ────────────────────────
print_step "Installing Worker Agent dependencies..."
cd "$(dirname "$0")/../worker"
pip install -r requirements.txt -q
opentelemetry-bootstrap -a install -q
print_ok "Worker dependencies installed"

# ── 6. Install Python deps for Sentinel ──────────────────────
print_step "Installing Sentinel Agent dependencies..."
cd "../sentinel"
pip install -r requirements.txt -q
opentelemetry-bootstrap -a install -q
print_ok "Sentinel dependencies installed"

# ── 7. Deploy SigNoz via Foundry ─────────────────────────────
cd ".."
print_step "Deploying SigNoz via Foundry..."
echo "   Running: foundryctl cast -f casting.yaml"
echo "   This downloads Docker images — takes 2-5 min first time..."
foundryctl cast -f casting.yaml
print_ok "SigNoz deployed"

# ── 8. Wait for SigNoz to be ready ───────────────────────────
print_step "Waiting for SigNoz UI to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:8080 > /dev/null 2>&1; then
    print_ok "SigNoz UI is ready at http://localhost:8080"
    break
  fi
  echo "   Waiting... ($i/30)"
  sleep 3
done

echo ""
echo "=============================="
echo -e "${GREEN}🎉 SETUP COMPLETE!${NC}"
echo "=============================="
echo ""
echo "Next steps:"
echo "  1. Open SigNoz:     http://localhost:8080"
echo "  2. Start agents:    ./scripts/run.sh"
echo "  3. Run demo:        ./scripts/demo.sh"
echo ""
