"""
worker/app.py

The AI agent being observed. Takes a question, calls a tool,
calls the LLM, returns an answer. Uses Groq (free, fast).
Every step is traced in SigNoz.
"""

from fastapi import FastAPI, HTTPException
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import logging
import random
import time
import os
from groq import Groq

resource = Resource(attributes={"service.name": "worker-agent"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)

tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

_groq = Groq()

_state = {
    "model":      os.environ.get("DEFAULT_MODEL", "llama-3.1-8b-instant"),
    "slow_tool":  False,
    "flaky_api":  False,
}


@app.get("/ask")
def ask(q: str):
    if not q or not q.strip():
        raise HTTPException(status_code=400, detail="q cannot be empty")

    with tracer.start_as_current_span("agent.request") as span:
        span.set_attribute("agent.question", q[:200])
        span.set_attribute("agent.model",    _state["model"])
        logger.info("question: %s", q[:80])

        context = _run_tool(q)
        answer  = _run_llm(q, context)
        return {"answer": answer, "model": _state["model"]}


def _run_tool(query: str) -> str:
    with tracer.start_as_current_span("agent.tool.search") as span:
        span.set_attribute("tool.name",  "search")
        span.set_attribute("tool.query", query[:150])

        if _state["slow_tool"]:
            delay = random.uniform(2.5, 4.0)
            logger.warning("slow tool active, sleeping %.1fs", delay)
            time.sleep(delay)

        result = (
            f"Search results for '{query}': "
            "SigNoz is an open-source OpenTelemetry-native observability platform."
        )
        span.set_attribute("tool.result_chars", len(result))
        return result


def _run_llm(question: str, context: str) -> str:
    with tracer.start_as_current_span("agent.llm.call") as span:
        model = _state["model"]

        span.set_attribute("gen_ai.system",         "groq")
        span.set_attribute("gen_ai.request.model",  model)
        span.set_attribute("gen_ai.operation.name", "chat")

        if _state["flaky_api"] and random.random() < 0.4:
            logger.error("flaky_api active - simulating timeout")
            span.set_status(trace.StatusCode.ERROR, "LLM timeout (injected)")
            span.set_attribute("error.type", "injected_timeout")
            raise HTTPException(status_code=500, detail="LLM API timeout")

        try:
            resp = _groq.chat.completions.create(
                model=model,
                max_tokens=200,
                messages=[{
                    "role": "user",
                    "content": f"Context:\n{context}\n\nQuestion: {question}\n\nAnswer briefly.",
                }],
            )

            input_tokens  = resp.usage.prompt_tokens
            output_tokens = resp.usage.completion_tokens

            span.set_attribute("gen_ai.usage.input_tokens",    input_tokens)
            span.set_attribute("gen_ai.usage.output_tokens",   output_tokens)
            span.set_attribute("gen_ai.response.model",        model)
            span.set_attribute("gen_ai.response.finish_reason",resp.choices[0].finish_reason)

            logger.info("llm ok: %d in / %d out tokens", input_tokens, output_tokens)
            return resp.choices[0].message.content

        except HTTPException:
            raise
        except Exception as exc:
            span.set_status(trace.StatusCode.ERROR, str(exc))
            logger.error("llm error: %s", exc)
            raise HTTPException(status_code=500, detail=str(exc))


@app.post("/control")
def control(action: dict):
    with tracer.start_as_current_span("agent.control") as span:
        action_type = action.get("type", "")
        span.set_attribute("control.action", action_type)

        if action_type == "switch_model":
            old = _state["model"]
            _state["model"] = action.get("model") or old
            span.set_attribute("control.model.from", old)
            span.set_attribute("control.model.to",   _state["model"])
            logger.info("model switched: %s -> %s", old, _state["model"])

        elif action_type == "inject_slow":
            _state["slow_tool"] = True
            logger.warning("slow_tool injected")

        elif action_type == "inject_flaky":
            _state["flaky_api"] = True
            logger.warning("flaky_api injected")

        elif action_type == "reset":
            _state["slow_tool"] = False
            _state["flaky_api"] = False
            _state["model"]     = "llama-3.1-8b-instant"
            logger.info("worker reset to defaults")

        return {"ok": True, "state": dict(_state)}


@app.get("/health")
def health():
    return {
        "status":    "ok",
        "model":     _state["model"],
        "slow_tool": _state["slow_tool"],
        "flaky_api": _state["flaky_api"],
    }
