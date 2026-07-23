# Architecture

## System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     YOUR MACHINE                            │
│                                                             │
│  ┌──────────────┐    OTel/gRPC     ┌───────────────────┐   │
│  │ WORKER AGENT │ ───:4317──────► │    SigNoz Stack   │   │
│  │  FastAPI     │                  │                   │   │
│  │  :8001       │ ◄── /control ──  │  ClickHouse DB    │   │
│  │              │   (heal action)  │  OTel Collector   │   │
│  │ LLM calls    │                  │  UI :8080         │   │
│  │ Tool calls   │                  │  MCP Server :8000 │   │
│  └──────────────┘                  └────────┬──────────┘   │
│         │                                   │              │
│         │ traces visible                    │ alert        │
│         │ in SigNoz UI                      │ webhook      │
│         │                                   │              │
│         ▼                                   ▼              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SENTINEL AGENT :8002                    │  │
│  │                                                      │  │
│  │  1. Receives alert webhook from SigNoz               │  │
│  │  2. Investigates via LLM diagnosis                   │  │
│  │  3. Applies healing action to Worker /control        │  │
│  │  4. Sentinel spans also flow to SigNoz               │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## The Healing Loop

```
Worker breaks (slow / errors)
         │
         ▼
SigNoz detects via metrics
         │
         ▼
Alert rule fires (p99 > 2s OR error rate > 10%)
         │
         ▼
SigNoz sends webhook to Sentinel :8002/webhook
         │
         ▼
Sentinel investigates (LLM diagnosis)
         │
         ▼
Sentinel picks healing action from playbook
         │
         ▼
Sentinel calls Worker :8001/control
         │
         ▼
Worker applies healing (model switch / reset)
         │
         ▼
Error rate / latency drops in SigNoz
         │
         ▼
Alert resolves automatically
```

## What Makes This Different

Most hackathon entries: instrument an agent → make dashboards → done.

Sentinel closes the loop:
- The agent is observed (Worker → SigNoz)
- The observer triggers a healer (SigNoz alerts → Sentinel)
- The healer is also observed (Sentinel → SigNoz)
- Agent observing agent. Both in SigNoz.
