# Backlog — startup-pack

## Producto
- [x] Auth flow completo (magic link + OAuth Google) — `blueprints/auth/` + auth.context.sql (SUP-10)
- [x] Onboarding multi-step para nuevos orgs — `blueprints/onboarding/onboarding.sql` (SUP-11)
- [x] Dashboard principal por org — `blueprints/dashboard/dashboard.sql` (SUP-20)
- [x] Gestión de miembros (invite, roles, remove) — `blueprints/users/member_management.sql` (SUP-13)
- [x] Billing portal (Stripe Customer Portal) — `blueprints/billing/billing.portal.sql` (SUP-21)
- [x] Notificaciones in-app + email — `blueprints/notifications/notifications.sql` (SUP-16)

## Infraestructura
- [x] CI/CD pipeline (GitHub Actions) — `ci.yml` + `notify.yml`
- [x] Migraciones DB con versioning — `runner.sh` + 24 sql versionadas
- [x] Seed data para desarrollo local — `blueprints/seed/seed.sql` (SUP-7)
- [x] Health check endpoint `/health` — `blueprints/health-base/health.sql` (SUP-6)
- [x] Rate limiting por org — `blueprints/rate-limit/` + cleanup (SUP-8)
- [x] Logs estructurados (JSON) — `blueprints/audit/audit.sql` (SUP-9)
- [x] Integration tests en CI (PostgreSQL real) — CI job `integration-test`
- [x] pg_cron scheduler — `0018_pg_cron.sql` (SUP-14)
- [x] Docker local dev environment — `docker-compose.yml` + `.env.example` (SUP-15)
- [x] Rollback strategy para migrations (down scripts) — `core/migrations/sql/down/` (SUP-19)
- [x] Particionado de audit_log por mes — `0024_audit_partitioning.sql` (SUP-23)

## Integraciones
- [x] Stripe webhooks handler — `blueprints/billing/stripe.webhooks.sql` (SUP-12)
- [x] Slack notifications outbound — `blueprints/notifications/slack.sql` (SUP-22)
- [ ] Linear sync bidireccional

## Ideas futuras
- [x] API pública con API keys por org — `blueprints/api-keys/api_keys.sql` (SUP-17)
- [ ] White-label support
- [ ] Analytics de uso por plan
