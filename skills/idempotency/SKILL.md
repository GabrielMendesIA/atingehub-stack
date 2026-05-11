---
name: idempotency
description: "Idempotency rules for dispatch operations. Use when writing dispatch creation, retry logic, or any code that could trigger duplicate deliveries. Claude must consult this before generating dispatch-related code."
---

# Idempotency Rules for Dispatch

Dispatch operations are financially and operationally critical. A duplicate dispatch means two couriers showing up, double billing, and a terrible client experience. Every dispatch mutation MUST be idempotent.

## Core Rule

**Any operation that creates or modifies a dispatch must be guarded by an idempotency key checked BEFORE calling the partner adapter.**

## Idempotency Key Format

```
dispatch:{orderId}:{attemptHash}
```

Where `attemptHash` is a short hash of the immutable dispatch parameters (origin, destination, partnerId). This ensures retrying with different params generates a new key (intentional change) vs retrying the same params (idempotent).

```typescript
function buildIdempotencyKey(params: DispatchParams): string {
  const hash = sha256(`${params.orderId}:${params.partnerId}:${params.originId}:${params.destinationId}`).slice(0, 8);
  return `dispatch:${params.orderId}:${hash}`;
}
```

## Guard Implementation

```typescript
async function createDispatch(params: DispatchParams): Promise<Dispatch> {
  const key = buildIdempotencyKey(params);

  // 1. Check for existing result
  const cached = await idempotencyStore.get(key);
  if (cached) {
    logger.info({ key }, 'Returning cached dispatch result (idempotent)');
    return cached;
  }

  // 2. Acquire lock to prevent concurrent duplicate requests
  const lock = await distributedLock.acquire(key, { ttlMs: 30_000 });
  if (!lock) throw new ConcurrentDispatchError(key);

  try {
    // 3. Re-check after acquiring lock (double-checked locking)
    const cachedAfterLock = await idempotencyStore.get(key);
    if (cachedAfterLock) return cachedAfterLock;

    // 4. Execute the actual dispatch
    const result = await partnerAdapter.createDispatch(params);

    // 5. Store result BEFORE returning
    await idempotencyStore.set(key, result, { ttlSeconds: 86_400 }); // 24h TTL

    return result;
  } finally {
    await lock.release();
  }
}
```

## Storage Requirements

- Use Redis (or equivalent) as the idempotency store — NOT the primary database
- TTL: **24 hours** minimum for dispatch operations
- The stored value must be the **full response**, not just a flag

## Retry Rules

| Scenario | Behavior |
|----------|----------|
| Same params, within TTL | Return cached result, do NOT call partner |
| Same params, after TTL | Treat as new dispatch (log warning) |
| Different params, same orderId | New idempotency key → allowed |
| Network timeout before store | Lock prevents duplicate; caller retries safely |

## Anti-Patterns — Claude Must NOT Generate

- `await adapter.createDispatch(params)` without a prior idempotency check
- Retry loops on dispatch creation without idempotency keys
- Using the database as the idempotency store (too slow for lock contention)
- Keys based on timestamps or random values (breaks idempotency)
- Storing only `true`/`false` — store the full response

## Webhook Deduplication

Partner webhooks can also deliver duplicate events. Apply the same pattern:

```typescript
const webhookKey = `webhook:{partnerId}:{eventId}`;
if (await idempotencyStore.exists(webhookKey)) return; // Already processed
await idempotencyStore.set(webhookKey, true, { ttlSeconds: 3600 });
// ... process event
```
