---
name: quote-flow
description: "Documents the parallel quote logic, normalization, and score calculation used to select the best delivery partner. Use when the user asks about quote flow, parallel quotes, partner scoring, or quote normalization."
---

# Quote Flow

The quote flow is the process of requesting prices from multiple delivery partners in parallel, normalizing the responses, and scoring them to recommend the best option to the client.

## Flow Overview

```
Client Request
      │
      ▼
 QuoteService
      │
      ├──▶ Adapter A (Lalamove)  ─┐
      ├──▶ Adapter B (iFood)     ─┼──▶ Normalize ──▶ Score ──▶ Sort ──▶ Response
      └──▶ Adapter C (...)       ─┘
```

## 1. Parallel Execution

All partner quotes are fetched concurrently using `Promise.allSettled` — NEVER `Promise.all`, because one partner failing must not block others.

```typescript
const results = await Promise.allSettled(
  activeAdapters.map(adapter => adapter.getQuote(request))
);

const successful = results
  .filter((r): r is PromiseFulfilledResult<QuoteResponse> => r.status === 'fulfilled')
  .map(r => r.value);
```

- Set a **timeout per partner** (default: 5s) — use `Promise.race` with a timeout promise
- Log and increment metrics for every failed/timed-out partner
- If ALL partners fail, throw `NoQuoteAvailableError`

## 2. Normalization

Before scoring, all quotes must be normalized to the internal `NormalizedQuote` model:

```typescript
interface NormalizedQuote {
  partnerId: string;
  partnerName: string;
  priceAmountCents: number;      // Always in cents, BRL
  estimatedMinutes: number;      // Pickup ETA in minutes
  distanceMeters: number;
  currency: 'BRL';
  rawResponse: unknown;          // Original partner response, for audit
}
```

Rules:
- All prices must be converted to **cents** (integer) — never store floats for money
- ETA must be in **minutes** (integer)
- Distance must be in **meters** (integer)

## 3. Score Calculation

Each quote receives a score (0–100). Higher = better for the client.

```typescript
function calculateScore(quote: NormalizedQuote, config: ScoreConfig): number {
  const priceScore   = normalizeStat(quote.priceAmountCents, config.priceRange)  * config.priceWeight;
  const etaScore     = normalizeStat(quote.estimatedMinutes, config.etaRange)    * config.etaWeight;
  const distScore    = normalizeStat(quote.distanceMeters,   config.distRange)   * config.distanceWeight;
  return priceScore + etaScore + distScore;
}
```

Default weights (adjust via config, not hardcode):
| Factor | Default Weight |
|--------|---------------|
| Price  | 50%           |
| ETA    | 35%           |
| Distance | 15%         |

- Weights must sum to 100%
- Weights are configurable per business unit / client tier
- `normalizeStat` inverts the scale for cost/time (lower is better → higher score)

## 4. Response Structure

```typescript
interface QuoteFlowResponse {
  quotes: ScoredQuote[];        // Sorted by score desc
  recommended: ScoredQuote;    // First item (highest score)
  requestId: string;            // For idempotency and audit
  quotedAt: string;             // ISO 8601 timestamp
  expiresAt: string;            // Quotes expire after N minutes
}
```

## Anti-Patterns

- Do NOT use `Promise.all` — one failure kills all quotes
- Do NOT store prices as floats — always cents (integer)
- Do NOT hardcode weights — make them configurable
- Do NOT skip the timeout — a slow partner will block the response
- Do NOT modify `rawResponse` — it must be stored as-is for audit
