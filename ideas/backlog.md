# Backlog — startup-pack

## Producto
- [x] Auth flow completo (magic link + OAuth Google) — `blueprints/auth/` + auth.context.sql (SUP-10)
- [x] Onboarding multi-step para nuevos orgs — `blueprints/onboarding/onboarding.sql` (SUP-11)
- [ ] Dashboard principal por org
- [x] Gestión de miembros (invite, roles, remove) — `blueprints/users/member_management.sql` (SUP-13)
- [ ] Billing portal (Stripe Customer Portal)
- [ ] Notificaciones in-app + email

## Infraestructura
- [x] CI/CD pipeline (GitHub Actions) — `ci.yml` + `notify.yml`
- [x] Migraciones DB con versioning — `runner.sh` + 18 sql versionadas
- [x] Seed data para desarrollo local — `blueprints/seed/seed.sql` (SUP-7)
- [x] Health check endpoint `/health` — `blueprints/health-base/health.sql` (SUP-6)
- [x] Rate limiting por org — `blueprints/rate-limit/` + cleanup (SUP-8)
- [x] Logs estructurados (JSON) — `blueprints/audit/audit.sql` (SUP-9)
- [x] Integration tests en CI (PostgreSQL real) — CI job `integration-test`
- [x] pg_cron scheduler — `0018_pg_cron.sql` (SUP-14)
- [x] Docker local dev environment — `docker-compose.yml` + `.env.example` (SUP-15)
- [ ] Rollback strategy para migrations (down scripts)
- [ ] Particionado de audit_log por mes (cuando volumen > 1M rows)

## Integraciones
- [x] Stripe webhooks handler — `blueprints/billing/stripe.webhooks.sql` (SUP-12)
- [ ] Slack notifications outbound
- [ ] Linear sync bidireccional

## Ideas futuras
- [ ] API pública con API keys por org
- [ ] White-label support
- [ ] Analytics de uso por plan
