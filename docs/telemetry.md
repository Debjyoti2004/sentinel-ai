# Telemetry Reference

## What We Capture

### Worker Agent Spans

| Span Name | What it represents | Key Attributes |
|---|---|---|
| `agent.request` | Full request lifecycle | `agent.question`, `agent.model` |
| `agent.tool.search` | Tool call (mock search) | `tool.name`, `tool.query` |
| `agent.llm.call` | LLM API call | `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `gen_ai.response.finish_reason` |
| `agent.control` | Healing action received | `control.action`, `control.model.old`, `control.model.new` |

### Sentinel Agent Spans

| Span Name | What it represents | Key Attributes |
|---|---|---|
| `sentinel.alert.received` | Alert webhook received | `alert.name`, `alert.severity` |
| `sentinel.investigate` | LLM diagnosis | `sentinel.diagnosis`, `gen_ai.*` |
| `sentinel.decide` | Action decision | `sentinel.action.type`, `sentinel.action.reason` |
| `sentinel.action.apply` | Healing applied to Worker | `sentinel.heal.success` |
| `sentinel.report` | Incident report written | — |

## GenAI Semantic Conventions

We follow the OpenTelemetry GenAI semantic conventions standard.
This makes token counts and model info readable by SigNoz natively.

```python
span.set_attribute("gen_ai.system", "anthropic")
span.set_attribute("gen_ai.request.model", "claude-haiku-4-5")
span.set_attribute("gen_ai.usage.input_tokens", 1200)
span.set_attribute("gen_ai.usage.output_tokens", 350)
span.set_attribute("gen_ai.response.finish_reason", "stop")
```

## What a Single Trace Looks Like

```
agent.request  [total: 1.2s]
├── agent.tool.search  [0.1s]
│       tool.name = "search"
│       tool.query = "What is SigNoz"
└── agent.llm.call  [1.1s]
        gen_ai.system = "anthropic"
        gen_ai.request.model = "claude-haiku-4-5"
        gen_ai.usage.input_tokens = 850
        gen_ai.usage.output_tokens = 180
        gen_ai.response.finish_reason = "stop"
```

## Dashboards We Build in SigNoz

| Dashboard Panel | Query Builder Config |
|---|---|
| Request rate | Traces → count → group by service.name |
| p99 latency | Traces → p99 duration → filter: service=worker-agent |
| Error rate % | Traces → error rate → filter: service=worker-agent |
| Token usage | Traces → sum gen_ai.usage.input_tokens → group by gen_ai.request.model |
