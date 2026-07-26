## Quickstart

```bash
# 1. Clone the repo
git clone https://github.com/Debjyoti2004/sentinel-ai
cd sentinel-ai

# 2. Set your Groq API key
export GROQ_API_KEY="your_key_here"

# 3. Start everything
./start.sh
```

That's it. SigNoz, Worker, and Sentinel all start automatically.

## Demo Commands

Run these in order to see the full self-healing loop:

```bash
# Step 1 — Send a clean request and check traces
curl -s "localhost:8001/ask?q=What+is+observability"


# Step 2 — Inject failure
curl -X POST localhost:8001/control \
  -H "Content-Type: application/json" \
  -d '{"type": "inject_flaky"}'

# Step 3 — Send traffic (watch error rate climb in dashboard)
for i in {1..15}; do
  curl -s "localhost:8001/ask?q=test" > /dev/null
  sleep 0.5
done


# Step 4 — Trigger Sentinel healing
curl -X POST localhost:8002/webhook \
  -H "Content-Type: application/json" \
  -d '{"alertname": "HighErrorRateWorker", "severity": "critical"}'

# Step 5 — Watch healing trace
# Go to: localhost:8080/traces-explorer
# Click POST /webhook from sentinel-agent (9 spans)
# See: sentinel.investigate → sentinel.decide → sentinel.heal

# Step 6 — Watch error rate drop to zero

```

## Other Control Commands

```bash
# Inject slow tool (triggers HighLatency alert)
curl -X POST localhost:8001/control \
  -H "Content-Type: application/json" \
  -d '{"type": "inject_slow"}'

# Switch model
curl -X POST localhost:8001/control \
  -H "Content-Type: application/json" \
  -d '{"type": "switch_model", "model": "llama-3.1-8b-instant"}'

# Reset everything back to normal
curl -X POST localhost:8001/control \
  -H "Content-Type: application/json" \
  -d '{"type": "reset"}'

# Check current worker state
curl -s localhost:8001/health
```

## SigNoz Features Used

| Feature | How we use it |
|---|---|
| Traces | Every LLM call, tool call, agent step captured as spans |
| Metrics | Request rate, latency, error rate, token counts |
| Logs | Structured logs tied to trace IDs |
| Dashboards | 4 panels: tokens, latency, errors, healing actions |
| Alerts | Fire when p99 > 2s or error rate > 10% |
| MCP Server | Sentinel reads live telemetry through it |
| Query Builder | All dashboards built with it |
| Foundry | Single casting.yaml deploys everything |

## Ports

| Port | Service |
|---|---|
| 8080 | SigNoz UI |
| 8000 | SigNoz MCP Server |
| 4317 | OTel Collector (gRPC) |
| 4318 | OTel Collector (HTTP) |
| 8001 | Worker Agent |
| 8002 | Sentinel Agent |

## Prerequisites

- Docker Desktop 20.10+ (running)
- Python 3.11+
- Groq API key (free at console.groq.com)
- foundryctl installed

## AI Tools Used

- Groq (llama-3.1-8b-instant) — LLM inside both Worker and Sentinel agents

Declared per hackathon rules.