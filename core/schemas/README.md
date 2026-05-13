# /core/schemas

Schemas PostgreSQL modulares. Cada archivo <250L.

## Orden de ejecución
```
000_init.sql          → extensiones + trigger updated_at
001_users.sql         → tabla users
002_organizations.sql → multi-tenancy + members
003_subscriptions.sql → billing (Stripe-ready)
```

## Convenciones
- PKs: UUID v4
- Timestamps: TIMESTAMPTZ
- Emails: CITEXT (case-insensitive)
- Soft deletes: `is_active` flag
