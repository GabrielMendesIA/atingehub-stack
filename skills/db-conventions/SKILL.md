---
name: db-conventions
description: "Postgres schema conventions for this project: UUIDs, timestamptz, soft delete, naming rules, and migration patterns. Use when writing migrations, creating tables, or designing schema changes."
---

# Database Conventions (Postgres)

These conventions must be followed in all schema migrations and queries. Claude must not generate schema that violates these rules.

## Primary Keys

- All tables use **UUID v4** as primary key — never serial/integer
- Default: `DEFAULT gen_random_uuid()` (no extension needed in Postgres 13+)

```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```

## Timestamps

- All timestamps use **`TIMESTAMPTZ`** (timezone-aware) — never `TIMESTAMP` or `DATE` for datetime fields
- Every table must have both:

```sql
created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
```

- `updated_at` must be maintained by a trigger (not application code):

```sql
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON <table_name>
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

## Soft Delete

- **No hard deletes** on core entities — use soft delete
- Pattern: `deleted_at TIMESTAMPTZ` column (null = active, timestamp = deleted)

```sql
deleted_at  TIMESTAMPTZ  -- null means active
```

- All queries on soft-deletable tables must filter: `WHERE deleted_at IS NULL`
- Create a partial index to keep this efficient:

```sql
CREATE INDEX ON dispatches (id) WHERE deleted_at IS NULL;
```

- When using an ORM, configure the global soft-delete filter (e.g., Prisma middleware or TypeORM `@DeleteDateColumn`)

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Tables | snake_case, plural | `dispatch_orders`, `partner_adapters` |
| Columns | snake_case | `partner_id`, `created_at` |
| Foreign keys | `{table_singular}_id` | `dispatch_id`, `user_id` |
| Indexes | `idx_{table}_{columns}` | `idx_dispatches_unit_id` |
| Unique constraints | `uq_{table}_{columns}` | `uq_dispatches_idempotency_key` |
| Check constraints | `chk_{table}_{column}` | `chk_dispatches_status` |
| Enums | UPPER_SNAKE_CASE values | `'PENDING'`, `'IN_TRANSIT'` |

## Money / Currency

- All monetary values stored as **integers in cents** — never `DECIMAL` or `FLOAT` for money
- Column naming: `{field}_amount_cents` (e.g., `price_amount_cents`)
- Currency stored separately as ISO 4217 text: `currency TEXT NOT NULL DEFAULT 'BRL'`

```sql
price_amount_cents  INTEGER NOT NULL,
currency            TEXT NOT NULL DEFAULT 'BRL'
```

## Enums

- Use Postgres native enums for status fields with a fixed set of values:

```sql
CREATE TYPE dispatch_status AS ENUM (
  'PENDING', 'ASSIGNED', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED', 'FAILED'
);
```

- Adding values to an enum requires a migration: `ALTER TYPE dispatch_status ADD VALUE 'NEW_STATUS';`

## Foreign Keys

- Always declare foreign keys explicitly
- Use `ON DELETE RESTRICT` by default — never `ON DELETE CASCADE` without explicit review
- Exception: pure junction/relationship tables may use `CASCADE`

## Migration Rules

- Migrations are **irreversible by default** — write both `up` and `down` only when rollback is safe
- Never drop columns in the same migration that adds a replacement — do it in a separate migration after the code is deployed
- Adding `NOT NULL` columns: always provide a `DEFAULT` or backfill in a separate step
- Never rename columns in production without a multi-step migration (add → backfill → switch → drop old)

## Indexes

Create indexes for:
- All foreign key columns
- Columns used in WHERE clauses of frequent queries
- `(unit_id, created_at DESC)` composite for paginated unit-scoped queries
- Partial indexes for soft-deleted tables (see above)

```sql
-- Required on every table with unit_id + created_at pattern
CREATE INDEX ON dispatches (unit_id, created_at DESC) WHERE deleted_at IS NULL;
```

## Anti-Patterns

- `TIMESTAMP` without timezone — always use `TIMESTAMPTZ`
- `SERIAL` or `INTEGER` primary keys — always UUID
- `FLOAT` or `DECIMAL` for money — always cents as INTEGER
- Hard deletes on core entities — always soft delete
- Application-managed `updated_at` — always use a trigger
- `ON DELETE CASCADE` on business-critical foreign keys
