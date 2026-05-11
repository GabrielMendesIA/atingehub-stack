---
name: n8n-scope
description: "Defines where n8n fits and where it does NOT fit in the system. Use this before proposing any automation, workflow, or integration to ensure Claude does not suggest n8n where application code belongs, or vice versa."
---

# n8n Scope

n8n is the **workflow automation layer** — it handles orchestration between external systems. It is NOT a replacement for application logic, business rules, or data processing.

## n8n IS the right place for

| Use Case | Example |
|----------|---------|
| External notifications | Sending WhatsApp/SMS/email when a dispatch status changes |
| CRM sync | Pushing order data to HubSpot, Salesforce, etc. |
| Slack/Teams alerts | Notifying ops teams of failed dispatches |
| Scheduling reports | Daily/weekly reports triggered by cron |
| Third-party webhooks | Receiving and routing events from partners to internal services |
| Low-code integrations | Connecting tools that don't need custom business logic |
| Retry pipelines for non-critical events | E.g., retry a notification 3x before giving up |

## n8n is NOT the right place for

| Scenario | Why | Where It Should Live |
|----------|-----|----------------------|
| Quote calculation / scoring | Business logic — must be tested and versioned | Application service (quote-flow) |
| Dispatch creation / idempotency | Safety-critical — needs idempotency guards | Application service (idempotency) |
| RBAC / authorization | Security-critical | Application layer (rbac-guards) |
| Database writes for core entities | No audit trail, no transactions | Application service + Postgres |
| Partner API calls (Lalamove, iFood) | Must go through the adapter layer | partner-adapter-service |
| Any logic with retry + idempotency requirements | n8n retries are not idempotent by default | Application service |
| Real-time user-facing operations | n8n latency is not suitable for synchronous APIs | Application service |

## Decision Rule

Ask: "If this workflow fails silently, would a client notice or would money be lost?"

- **Yes** → Application code, not n8n
- **No** → n8n is likely appropriate

## Integration Pattern

When n8n does interact with the system, it must go through the **public API** — never directly to the database.

```
n8n Workflow
    │
    ▼
[POST /internal/webhooks/n8n]  ← authenticated with service token
    │
    ▼
Application Service  ← enforces all business rules, idempotency, audit
    │
    ▼
Database / Partner Adapter
```

n8n must NEVER:
- Connect directly to the Postgres database
- Call partner APIs (Lalamove, iFood) directly
- Bypass authentication or RBAC

## Trigger Sources for n8n

n8n workflows should be triggered by:
1. **Webhooks from the application** — the app pushes events to n8n
2. **Polling the application API** — n8n polls on a schedule
3. **External partner webhooks** — routed through n8n before hitting the app

NOT by database polling or direct DB triggers.

## Anti-Patterns Claude Must Not Suggest

- "Use an n8n workflow to calculate the best partner" — scoring is application logic
- "Create an n8n workflow to handle dispatch creation" — dispatch is safety-critical
- "Connect n8n directly to the Postgres database" — always via API
- "Use n8n to manage retry logic for payments" — use application-level retry with idempotency
