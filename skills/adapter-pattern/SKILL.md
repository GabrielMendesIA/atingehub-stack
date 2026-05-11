---
name: adapter-pattern
description: "Guide for creating a new partner adapter (Lalamove, iFood, etc.) following the partner-adapter-service interface. Use when the user asks to integrate a new delivery partner, create a new adapter, or implement the partner interface."
---

# Partner Adapter Pattern

This skill guides the creation of new delivery partner adapters following the `partner-adapter-service` interface contract. Every partner integration MUST follow this pattern — no one-off implementations.

## Interface Contract

Every adapter must implement the `IPartnerAdapter` interface:

```typescript
interface IPartnerAdapter {
  // Unique identifier for the partner (e.g., 'lalamove', 'ifood')
  readonly partnerId: string;

  // Returns a quote for the given shipment request
  getQuote(request: QuoteRequest): Promise<QuoteResponse>;

  // Creates a dispatch/order with the partner
  createDispatch(request: DispatchRequest): Promise<DispatchResponse>;

  // Cancels an existing dispatch
  cancelDispatch(dispatchId: string, reason: string): Promise<void>;

  // Tracks the current status of a dispatch
  trackDispatch(dispatchId: string): Promise<TrackingResponse>;

  // Webhook handler for partner-initiated status updates (optional)
  handleWebhook?(payload: unknown, signature: string): Promise<WebhookEvent>;
}
```

> Note: Update the interface above to match the actual `partner-adapter-service` contract in your codebase.

## File Structure

When adding a new partner (e.g., `newpartner`):

```
src/
  adapters/
    newpartner/
      index.ts              # Re-exports
      newpartner.adapter.ts # Main adapter class
      newpartner.client.ts  # HTTP client / SDK wrapper
      newpartner.mapper.ts  # Maps partner DTOs to/from internal models
      newpartner.config.ts  # Partner-specific config (env vars, endpoints)
      newpartner.types.ts   # Partner-specific types/DTOs
    __tests__/
      newpartner.adapter.spec.ts
```

## Implementation Checklist

1. **Create the adapter class** implementing `IPartnerAdapter`
2. **Create an HTTP client** — never call `fetch`/`axios` directly in the adapter class; isolate HTTP in a client class
3. **Create a mapper** — all transformation between partner DTOs and internal models goes here, nowhere else
4. **Register the adapter** in the adapter registry/factory (check `partner-adapter-service` for the registration point)
5. **Add environment variables** to `.env.example` and the config service
6. **Write unit tests** mocking the HTTP client, not the adapter itself
7. **Handle errors** — map partner error codes to internal `PartnerError` types

## Mapper Rules

- The mapper is a pure function layer — no side effects, no async
- Always normalize phone numbers, addresses, and currencies to internal formats
- Partner IDs must be stored alongside internal IDs (never replace them)

## Error Handling

```typescript
// Map partner errors to internal error types
try {
  const response = await this.client.createOrder(payload);
  return this.mapper.toDispatchResponse(response);
} catch (error) {
  if (isPartnerRateLimitError(error)) throw new PartnerRateLimitError(this.partnerId);
  if (isPartnerNotFoundError(error)) throw new PartnerResourceNotFoundError(this.partnerId);
  throw new PartnerUnexpectedError(this.partnerId, error);
}
```

## Anti-Patterns to Avoid

- Do NOT call partner APIs directly from services — always go through the adapter
- Do NOT hardcode partner-specific logic outside the adapter directory
- Do NOT share state between adapter instances
- Do NOT ignore webhook signature validation
