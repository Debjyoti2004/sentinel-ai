#!/bin/bash
# =============================================================
# Sentinel Project — Smart Start Script
# Usage: ./start.sh
# =============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "🕶️  SENTINEL — STARTING UP"
echo "==========================="

# ── 1. Check Docker ───────────────────────────────────────────
echo -e "\n${BLUE}Checking Docker...${NC}"
if ! docker ps &>/dev/null; then
  echo -e "${RED}❌ Docker not running. Start Docker Desktop first.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Docker running${NC}"

# ── 2. Start SigNoz (preserve existing data) ─────────────────
echo -e "\n${BLUE}Starting SigNoz...${NC}"

# Check if already running
if docker ps | grep -q "signoz-signoz-0"; then
  echo -e "${GREEN}✅ SigNoz already running${NC}"
else
  # Use existing compose file to preserve volumes/data
  COMPOSE_FILE="$ROOT/pours/deployment/compose.yaml"
  if [ -f "$COMPOSE_FILE" ]; then
    echo "   Starting existing deployment (preserving dashboards + data)..."
    docker compose -f "$COMPOSE_FILE" up -d
  else
    echo "   No existing deployment found, running foundryctl cast..."
    cd "$ROOT"
    foundryctl cast -f casting.yaml
  fi
  echo "   Waiting for SigNoz to be ready..."
  sleep 8
fi

# ── 3. Check GROQ_API_KEY ─────────────────────────────────────
echo -e "\n${BLUE}Checking API key...${NC}"
if [ -z "$GROQ_API_KEY" ]; then
  echo -e "${YELLOW}⚠️  GROQ_API_KEY not set.${NC}"
  echo -n "   Enter your Groq API key (hidden): "
  read -s GROQ_KEY
  echo ""
  export GROQ_API_KEY="$GROQ_KEY"
  echo -e "${GREEN}✅ Key set${NC}"
else
  echo -e "${GREEN}✅ GROQ_API_KEY already set${NC}"
fi

# ── 4. Start Worker ───────────────────────────────────────────
echo -e "\n${BLUE}Starting Worker Agent on :8001...${NC}"

# Kill if already running
lsof -ti:8001 | xargs kill -9 2>/dev/null || true
sleep 1

cd "$ROOT/worker"
export OTEL_SERVICE_NAME=worker-agent
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc

python3.11 -m uvicorn app:app --host 0.0.0.0 --port 8001 &
WORKER_PID=$!
sleep 2

if curl -s http://localhost:8001/health > /dev/null 2>&1; then
  echo -e "${GREEN}✅ Worker running (PID: $WORKER_PID)${NC}"
else
  echo -e "${RED}❌ Worker failed to start${NC}"
  exit 1
fi

# ── 5. Start Sentinel ─────────────────────────────────────────
echo -e "\n${BLUE}Starting Sentinel Agent on :8002...${NC}"

# Kill if already running
lsof -ti:8002 | xargs kill -9 2>/dev/null || true
sleep 1

cd "$ROOT/sentinel"
export OTEL_SERVICE_NAME=sentinel-agent
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export WORKER_URL=http://localhost:8001

python3.11 -m uvicorn app:app --host 0.0.0.0 --port 8002 &
SENTINEL_PID=$!
sleep 2

if curl -s http://localhost:8002/health > /dev/null 2>&1; then
  echo -e "${GREEN}✅ Sentinel running (PID: $SENTINEL_PID)${NC}"
else
  echo -e "${RED}❌ Sentinel failed to start${NC}"
  exit 1
fi

# ── 6. Send warm-up traffic ───────────────────────────────────
echo -e "\n${BLUE}Sending warm-up traffic...${NC}"
for i in {1..5}; do
  curl -s "http://localhost:8001/ask?q=warmup" > /dev/null
  sleep 0.5
done
echo -e "${GREEN}✅ Traces flowing${NC}"

# ── 7. Summary ───────────────────────────────────────────────
echo ""
echo "==========================="
echo -e "${GREEN}🎉 EVERYTHING RUNNING${NC}"
echo "==========================="
echo ""
echo "  SigNoz UI:      http://localhost:8080"
echo "  Worker Agent:   http://localhost:8001"
echo "  Sentinel Agent: http://localhost:8002"
echo "  MCP Server:     http://localhost:8000"
echo ""
echo "  Login: admin@sentinel.dev / Sentinel2026!"
echo ""
echo "  Test:  curl 'localhost:8001/ask?q=What+is+SigNoz'"
echo "  Demo:  ./demo.sh"
echo ""
echo "Press Ctrl+C to stop all agents"
echo ""

# ── Graceful shutdown ─────────────────────────────────────────
cleanup() {
  echo ""
  echo "Stopping agents (SigNoz keeps running)..."
  kill $WORKER_PID $SENTINEL_PID 2>/dev/null
  echo "Done. SigNoz still running — your dashboards are safe."
}
trap cleanup EXIT INT TERM
wait
