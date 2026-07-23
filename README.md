# 🕶️ Sentinel — Self-Healing AI Agent Observability

> An AI agent fully observed by SigNoz, healed by a second agent that reads its telemetry via MCP.

## What it does

```
WORKER AGENT          →   SigNoz (Foundry)   →   SENTINEL AGENT
answers questions          watches everything       reads traces via MCP
sometimes breaks           fires alerts             diagnoses + heals
```

When something breaks:
1. SigNoz detects it (high latency / high errors)
2. Alert fires → Sentinel receives webhook
3. Sentinel reads real traces from SigNoz MCP
4. Sentinel diagnoses the problem
5. Sentinel heals Worker automatically (no human needed)

## Project Structure

```
sentinel-project/
├── casting.yaml          ← Foundry deployment config (run this to deploy SigNoz)
├── casting.yaml.lock     ← Auto-generated lock file (commit this)
├── README.md             ← You are here
├── docs/
│   ├── architecture.md   ← How everything connects
│   ├── telemetry.md      ← What traces/spans we capture
│   └── demo.md           ← How to run the demo
├── scripts/
│   ├── setup.sh          ← One-command setup on any machine
│   ├── run.sh            ← Start worker + sentinel
│   └── demo.sh           ← Inject failures for demo
├── worker/
│   ├── app.py            ← The AI agent being observed
│   └── requirements.txt
└── sentinel/
    ├── app.py            ← The SRE copilot that heals
    └── requirements.txt
```

## Quickstart (or just run setup.sh)

```bash
# 1. Deploy SigNoz
foundryctl cast -f casting.yaml

# 2. Open SigNoz UI
open http://localhost:8080

# 3. Run both agents
./scripts/run.sh

# 4. Run demo (inject failures)
./scripts/demo.sh
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

## Demo Failure Switches

```bash
SLOW_TOOL=1    # Worker randomly delays 3s → triggers HighLatency alert
FLAKY_API=1    # 30% of Worker requests fail → triggers HighErrorRate alert
```

## AI Tools Used

- Claude (Anthropic) — LLM inside Worker Agent and Sentinel Agent
- Claude Code — development assistant during build

## Prerequisites

- Docker Desktop 20.10+ (running)
- Python 3.10+
- Anthropic API key
- foundryctl (see scripts/setup.sh)
