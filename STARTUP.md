# Sentinel — How to Start Everything

## One Command (recommended)

```bash
./start.sh
```

This script:
- Starts SigNoz WITHOUT resetting data (dashboards, alerts, traces preserved)
- Asks for your Groq API key if not set
- Starts Worker on :8001
- Starts Sentinel on :8002
- Sends warm-up traffic
- Shows all URLs

---

## What NOT to do

❌ `docker compose down -v` — this deletes ALL data including dashboards
❌ `foundryctl cast` again — this resets everything

✅ Use `start.sh` instead — it uses `docker compose up -d` which preserves data

---

## Your Login

- URL: http://localhost:8080
- Email: admin@sentinel.dev
- Password: Sentinel2026!

---

## All URLs

| Service | URL |
|---|---|
| SigNoz UI | http://localhost:8080 |
| Worker Agent | http://localhost:8001 |
| Sentinel Agent | http://localhost:8002 |
| MCP Server | http://localhost:8000 |

---

## If SigNoz data is lost

Your dashboards and alerts are stored in the Docker volume
`signoz-metastore-postgres-0-data`. As long as you don't run
`docker compose down -v`, they are safe.

If you do lose them, you need to recreate:
1. 2 alert rules (HighErrorRateWorker, HighLatencyWorker)
2. 1 notification channel (sentinel-webhook → host.docker.internal:8002/webhook)
3. 1 dashboard (Sentinel Operations) with 4 panels

---

## Demo sequence

```bash
# 1. Inject failure
curl -X POST localhost:8001/control \
  -H "Content-Type: application/json" \
  -d '{"type": "inject_flaky"}'

# 2. Send traffic (errors will appear in SigNoz)
for i in {1..15}; do
  curl -s "localhost:8001/ask?q=test" > /dev/null
  sleep 0.5
done

# 3. Trigger Sentinel manually (no need to wait for alert)
curl -X POST localhost:8002/webhook \
  -H "Content-Type: application/json" \
  -d '{"alertname": "HighErrorRateWorker", "severity": "critical"}'

# 4. System heals automatically

# 5. Reset for next demo run
curl -X POST localhost:8001/control \
  -H "Content-Type: application/json" \
  -d '{"type": "reset"}'
```

---

## GitHub

Repo: https://github.com/Debjyoti2004/sentinel-ai
