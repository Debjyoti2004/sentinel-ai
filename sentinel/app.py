"""
sentinel/app.py

The SRE copilot. Watches SigNoz alerts, investigates, heals the worker.
Also fully instrumented - you can watch the healer in SigNoz too.
"""

from fastapi import FastAPI, Request
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import logging
import requests
import json
import os
from groq import Groq

# ── OTel setup ────────────────────────────────────────────────────────────
resource = Resource(attributes={"service.name": "sentinel-agent"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)

tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

_groq = Groq()

def _worker_url() -> str:
    url = os.environ.get("WORKER_URL", "http://localhost:8001")
    return url.rstrip("/")

PLAYBOOK = {
    "HighLatencyWorker":   {"type": "switch_model", "model": "llama-3.1-8b-instant"},
    "HighErrorRateWorker": {"type": "reset"},
}


@app.post("/webhook")
async def on_alert(request: Request):
    raw = await request.json()
    alert_name = raw.get("alertname") or raw.get("alert_name") or "unknown"
    severity   = raw.get("severity", "unknown")

    logger.info("alert received: %s [%s]", alert_name, severity)

    with tracer.start_as_current_span("sentinel.alert.received") as span:
        span.set_attribute("alert.name",     alert_name)
        span.set_attribute("alert.severity", severity)
        span.set_attribute("alert.payload",  json.dumps(raw)[:500])

        diagnosis = _investigate(alert_name, raw)
        action    = _pick_action(alert_name, diagnosis)
        outcome   = _heal(action)
        report    = _write_report(alert_name, diagnosis, action, outcome)

        span.set_attribute("sentinel.action",  action.get("type", "none"))
        span.set_attribute("sentinel.healed",  outcome.get("ok", False))

        return {
            "alert":     alert_name,
            "diagnosis": diagnosis,
            "action":    action,
            "outcome":   outcome,
            "report":    report,
        }


def _investigate(alert_name: str, payload: dict) -> str:
    with tracer.start_as_current_span("sentinel.investigate") as span:
        span.set_attribute("alert.name", alert_name)

        prompt = (
            f"You are an on-call SRE. A SigNoz alert just fired.\n\n"
            f"Alert name: {alert_name}\n"
            f"Payload: {json.dumps(payload)[:600]}\n\n"
            f"What is most likely broken and why? One or two sentences, be specific."
        )

        try:
            resp = _groq.chat.completions.create(
                model="llama-3.1-8b-instant",
                max_tokens=150,
                messages=[{"role": "user", "content": prompt}],
            )

            diagnosis = resp.choices[0].message.content.strip()

            span.set_attribute("gen_ai.system",              "groq")
            span.set_attribute("gen_ai.request.model",       "llama-3.1-8b-instant")
            span.set_attribute("gen_ai.usage.input_tokens",  resp.usage.prompt_tokens)
            span.set_attribute("gen_ai.usage.output_tokens", resp.usage.completion_tokens)
            span.set_attribute("sentinel.diagnosis",          diagnosis[:400])

            logger.info("diagnosis: %s", diagnosis[:120])
            return diagnosis

        except Exception as exc:
            span.set_status(trace.StatusCode.ERROR, str(exc))
            logger.error("investigation failed: %s", exc)
            return f"could not investigate: {exc}"


def _pick_action(alert_name: str, diagnosis: str) -> dict:
    with tracer.start_as_current_span("sentinel.decide") as span:
        if alert_name in PLAYBOOK:
            action = dict(PLAYBOOK[alert_name])
        else:
            text = (alert_name + " " + diagnosis).lower()
            if any(w in text for w in ("slow", "latency", "p99", "timeout")):
                action = dict(PLAYBOOK["HighLatencyWorker"])
            elif any(w in text for w in ("error", "fail", "exception", "crash")):
                action = dict(PLAYBOOK["HighErrorRateWorker"])
            else:
                action = {"type": "log_only"}

        span.set_attribute("sentinel.action.type", action.get("type", ""))
        logger.info("decided action: %s", action)
        return action


def _heal(action: dict) -> dict:
    with tracer.start_as_current_span("sentinel.heal") as span:
        action_type = action.get("type", "log_only")
        span.set_attribute("sentinel.action.type", action_type)

        if action_type == "log_only":
            return {"ok": True, "note": "logged only"}

        try:
            r = requests.post(
                f"{_worker_url()}/control",
                json=action,
                timeout=5,
            )
            r.raise_for_status()
            result = r.json()
            span.set_attribute("sentinel.heal.success", True)
            logger.info("worker healed: %s", result)
            return {"ok": True, "worker": result}

        except Exception as exc:
            span.set_status(trace.StatusCode.ERROR, str(exc))
            span.set_attribute("sentinel.heal.success", False)
            logger.error("healing failed: %s", exc)
            return {"ok": False, "error": str(exc)}


def _write_report(alert_name, diagnosis, action, outcome) -> str:
    with tracer.start_as_current_span("sentinel.report"):
        report = "\n".join([
            "--- incident report ---",
            f"alert:     {alert_name}",
            f"diagnosis: {diagnosis}",
            f"action:    {action.get('type')}",
            f"outcome:   {'healed' if outcome.get('ok') else 'failed'}",
            "--- end ---",
        ])
        logger.info(report)
        return report


@app.get("/health")
def health():
    return {"status": "ok", "worker": _worker_url()}
