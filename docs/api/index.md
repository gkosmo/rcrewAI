---
layout: api
title: API Reference
description: Complete API documentation for RCrewAI
---

# API Reference

Complete documentation for all RCrewAI classes and methods.

## Core Classes

### [RCrewAI::Crew]({{ site.baseurl }}/api/crew)
The main orchestrator that manages agents and tasks.

### [RCrewAI::Agent]({{ site.baseurl }}/api/agent)
Individual AI agents with specific roles and capabilities.

### [RCrewAI::Task]({{ site.baseurl }}/api/task)
Tasks that agents execute to achieve goals.

## Production Controls (0.8 – 0.10)

- **`RCrewAI::Checkpoint`** — save and resume runs. See [Checkpointing]({{ site.baseurl }}/tutorials/checkpointing)
- **`before_request` / `after_response`, `RCrewAI::Events`** — hooks and tracing. See [Interceptors and Events]({{ site.baseurl }}/tutorials/interceptors-and-events)
- **`parallel_tools`, `consensus_max_concurrency`, `max_concurrency`** — fan-out limits. See [Concurrency]({{ site.baseurl }}/tutorials/concurrency)
- **`RCrewAI::CancelToken`, `RCrewAI::StreamCancelled`** — real-time Anthropic calls. See [Live Streaming]({{ site.baseurl }}/tutorials/live-streaming)

## Capabilities (0.4 – 0.7)

These subsystems are covered in depth by the tutorials (with runnable examples):

- **`RCrewAI::Flow`** — event-driven workflows. See [Flows]({{ site.baseurl }}/tutorials/flows)
- **`RCrewAI::Knowledge::Base`** and sources/embedders — RAG. See [Knowledge]({{ site.baseurl }}/tutorials/knowledge)
- **`RCrewAI::Memory`** (+ `SqliteStore`, memory types) — cognitive memory. See [Memory]({{ site.baseurl }}/tutorials/memory)
- **Consensual process** — multi-agent voting. See [Consensual Process]({{ site.baseurl }}/tutorials/consensual-process)
- **Advanced agent/task options** — per-agent LLM, reasoning, rate limiting, context window, multimodal, structured output, guardrails, hooks. See [Advanced Options]({{ site.baseurl }}/tutorials/agent-options)

## Tools

See the [Tools System]({{ site.baseurl }}/api/tools) reference for the full API.
Built-in tools include `WebSearch`, `FileReader`, `FileWriter`, `SqlDatabase`,
`EmailSender`, `PdfProcessor`, and `CodeExecutor` — plus native function calling
and MCP servers.

## Configuration

### [RCrewAI::Configuration]({{ site.baseurl }}/api/configuration)
Configure LLM providers, models, and other settings.