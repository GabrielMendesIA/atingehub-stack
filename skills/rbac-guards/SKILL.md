---
name: rbac-guards
description: "How to apply RBAC authorization guards by role and business unit. Use when the user asks about permissions, guards, role checks, access control, or protecting routes/endpoints by role or unit."
---

# RBAC Guards

This system uses Role-Based Access Control (RBAC) scoped by both **role** and **business unit (unidade)**. Every protected endpoint or service action must declare its required role(s) and unit scope.

## Role Hierarchy

```
SUPER_ADMIN       → Full access, all units
  └── ADMIN       → Full access within their unit(s)
       └── MANAGER    → Operational read/write within their unit
            └── OPERATOR   → Create/update dispatches, view quotes
                 └── VIEWER    → Read-only
```

## Applying Guards

### NestJS (Decorator Pattern)

```typescript
// Require a specific role
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.MANAGER, Role.ADMIN, Role.SUPER_ADMIN)
@Get('dispatches')
async listDispatches(@CurrentUser() user: AuthUser) { ... }

// Require a specific role AND same unit
@UseGuards(JwtAuthGuard, RolesGuard, UnitGuard)
@Roles(Role.OPERATOR)
@SameUnit()  // User's unit must match the resource's unit
@Post('dispatches')
async createDispatch(@CurrentUser() user: AuthUser, @Body() dto: CreateDispatchDto) { ... }
```

### Guard Order (always in this order)

1. `JwtAuthGuard` — validates the token and loads `AuthUser`
2. `RolesGuard` — checks `user.role` against `@Roles(...)` 
3. `UnitGuard` — checks `user.unitId` against the resource's unit (when `@SameUnit()` is applied)

**Never** apply `UnitGuard` before `RolesGuard`.

## `AuthUser` Shape

```typescript
interface AuthUser {
  id: string;
  role: Role;
  unitId: string;          // Primary unit
  allowedUnitIds: string[]; // All units the user can access (for ADMIN/SUPER_ADMIN)
}
```

## Unit Scope Rules

| Role | Unit Access |
|------|-------------|
| `SUPER_ADMIN` | All units — skip unit check |
| `ADMIN` | Their `allowedUnitIds` |
| `MANAGER` / `OPERATOR` / `VIEWER` | Only their `unitId` |

```typescript
// UnitGuard implementation logic (reference)
function canAccessUnit(user: AuthUser, resourceUnitId: string): boolean {
  if (user.role === Role.SUPER_ADMIN) return true;
  if (user.role === Role.ADMIN) return user.allowedUnitIds.includes(resourceUnitId);
  return user.unitId === resourceUnitId;
}
```

## Service-Level Checks

Guards at the controller level are not enough when service methods are called internally. Add explicit checks in services for cross-unit operations:

```typescript
async getDispatch(id: string, requestingUser: AuthUser): Promise<Dispatch> {
  const dispatch = await this.repo.findById(id);
  if (!dispatch) throw new NotFoundException();
  
  // Enforce unit scope at service level too
  if (!canAccessUnit(requestingUser, dispatch.unitId)) {
    throw new ForbiddenException('Cannot access dispatch from another unit');
  }
  
  return dispatch;
}
```

## Anti-Patterns

- Do NOT rely solely on controller guards — add service-level checks for sensitive reads
- Do NOT expose `allowedUnitIds` to the client — derive from JWT claims server-side only
- Do NOT use `SUPER_ADMIN` role for application logic — it's an emergency/ops role only
- Do NOT skip `UnitGuard` on mutation endpoints (POST, PATCH, DELETE)
- Do NOT check `user.role === 'admin'` as a string — always use the `Role` enum

## Adding a New Protected Endpoint

Checklist:
- [ ] Minimum role defined and applied via `@Roles(...)`
- [ ] Unit scope enforced via `@SameUnit()` or explicit service check
- [ ] Audit log entry created (see `audit-trail` skill)
- [ ] Unit test for each role that should be denied access
