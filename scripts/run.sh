#!/bin/bash
# load env
set -a
source "$(dirname "$0")/../.env"
set +a

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Starting Worker on :8001..."
cd "$ROOT/worker"
python3.11 -m uvicorn app:app --port 8001 &
WORKER_PID=$!

sleep 2

echo "Starting Sentinel on :8002..."
cd "$ROOT/sentinel"
python3.11 -m uvicorn app:app --port 8002 &
SENTINEL_PID=$!

echo ""
echo "✅ Both running"
echo "Worker:   http://localhost:8001"
echo "Sentinel: http://localhost:8002"
echo "SigNoz:   http://localhost:8080"
echo ""
echo "Ctrl+C to stop"

cleanup() { kill $WORKER_PID $SENTINEL_PID 2>/dev/null; }
trap cleanup EXIT INT TERM
wait
