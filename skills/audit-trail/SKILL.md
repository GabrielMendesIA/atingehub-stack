---
name: audit-trail
description: "Pattern for recording audit logs on every critical action. Use when writing code that creates, modifies, or cancels dispatches, changes permissions, modifies financial data, or any other sensitive operation."
---

# Audit Trail

Every critical action in the system must leave an immutable audit record. The audit log is append-only — records are never updated or deleted.

## What Must Be Audited

| Category | Examples |
|----------|---------|
| Dispatch lifecycle | create, assign, cancel, complete, fail |
| Quote events | quote requested, partner selected, quote expired |
| Financial | price override, refund, billing adjustment |
| Auth/Access | login, logout, failed auth, token revoke |
| RBAC changes | role assignment, unit assignment, permission grant/revoke |
| Partner management | adapter enabled/disabled, config changed |
| Admin actions | any SUPER_ADMIN or ADMIN mutation |

## Audit Record Schema

```sql
CREATE TABLE audit_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Who
  actor_id    UUID REFERENCES users(id),
  actor_role  TEXT NOT NULL,
  actor_unit_id UUID REFERENCES units(id),
  
  -- What
  action      TEXT NOT NULL,          -- e.g., 'dispatch.create', 'dispatch.cancel'
  entity_type TEXT NOT NULL,          -- e.g., 'dispatch', 'user', 'partner'
  entity_id   UUID NOT NULL,
  
  -- Context
  unit_id     UUID REFERENCES units(id),  -- unit context of the action
  request_id  TEXT,                        -- correlates with HTTP request logs
  ip_address  INET,
  
  -- Payload
  before      JSONB,                  -- state before the action (null for creates)
  after       JSONB,                  -- state after the action (null for deletes)
  metadata    JSONB                   -- additional context (reason, partner, etc.)
);

-- Indexes for common queries
CREATE INDEX ON audit_logs (entity_type, entity_id);
CREATE INDEX ON audit_logs (actor_id);
CREATE INDEX ON audit_logs (created_at DESC);
CREATE INDEX ON audit_logs (unit_id, created_at DESC);
```

## Service Pattern

```typescript
// AuditService — inject and call within the same transaction when possible
@Injectable()
export class AuditService {
  async record(entry: AuditEntry): Promise<void> {
    await this.db.auditLogs.create({
      data: {
        actorId:    entry.actor.id,
        actorRole:  entry.actor.role,
        actorUnitId: entry.actor.unitId,
        action:     entry.action,
        entityType: entry.entityType,
        entityId:   entry.entityId,
        unitId:     entry.unitId,
        requestId:  entry.requestId,
        ipAddress:  entry.ipAddress,
        before:     entry.before ?? null,
        after:      entry.after ?? null,
        metadata:   entry.metadata ?? null,
      }
    });
  }
}

// Usage inside a service method
async cancelDispatch(id: string, reason: string, actor: AuthUser): Promise<void> {
  const dispatch = await this.repo.findById(id);
  const before = { ...dispatch };

  await this.repo.update(id, { status: 'CANCELLED', cancelReason: reason });

  await this.auditService.record({
    actor,
    action: 'dispatch.cancel',
    entityType: 'dispatch',
    entityId: id,
    unitId: dispatch.unitId,
    before,
    after: { status: 'CANCELLED', cancelReason: reason },
    metadata: { reason },
  });
}
```

## Action Naming Convention

Format: `{entity}.{verb}`

| Action | Meaning |
|--------|---------|
| `dispatch.create` | New dispatch created |
| `dispatch.cancel` | Dispatch cancelled |
| `dispatch.assign` | Courier assigned |
| `dispatch.complete` | Delivery confirmed |
| `quote.request` | Quote flow initiated |
| `quote.select` | Partner selected from quote |
| `user.role_change` | User role modified |
| `partner.disable` | Partner adapter disabled |

## Rules

- Audit records are **always written** — even if the main operation fails, log the attempt
- Write audit records **within the same database transaction** as the main operation when possible
- The `before` field must capture state BEFORE the mutation, not after
- Never store PII (passwords, tokens, full card numbers) in audit fields
- The audit table must NOT have foreign key constraints with `ON DELETE CASCADE` — audit records survive entity deletion

## Anti-Patterns

- Do NOT batch audit records or write them asynchronously when the operation is financial/dispatch-critical
- Do NOT skip auditing because "it's an internal action" — internal admin actions need MORE audit coverage
- Do NOT use application logs (console.log, logger) as a substitute for structured audit records
- Do NOT allow audit records to be deleted via application code — only via DBA with documented approval
