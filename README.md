# Hydra Framework — Start-up Pack

Infraestructura modular lista para SaaS B2B.  
Stack: **PostgreSQL puro** · GitHub Actions CI · Linear · Docker · Slack.

> **12 blueprints · 20 migrations · 0 líneas de boilerplate para el founder**

---

## Arquitectura en 3 capas

```
/core/              → Motor inmutable (migrations, infra, automation)
/blueprints/        → Módulos SQL reutilizables (12 disponibles)
/active_project/    → Startup actual inyectada (volátil — reset con inject.sh)
```

### Blueprints disponibles

| Módulo | Qué incluye |
|--------|-------------|
| `base` | Extensiones UUID/CITEXT/pgcrypto, `set_updated_at()`, `schema_versions` |
| `auth` | Magic link, OAuth Google, sessions, contexto de sesión para auditoría |
| `users` | `users`, `organizations`, `organization_members`, member management RBAC |
| `billing` | `subscriptions`, `invoices`, `billing_events`, Stripe webhooks processor |
| `health-base` | `health_check()` → `{status:"ok", version, timestamp}` |
| `seed` | Datos demo reproducibles (UUIDs fijos, idempotente) |
| `rate-limit` | Sliding window por org + endpoint + plan, con cleanup automático |
| `audit` | Trigger universal JSONB → `audit_log`, lee contexto de sesión |
| `onboarding` | Progress tracking multi-step, `invite_member()`, `accept_invite()` |
| `notifications` | In-app + email queue, `dequeue_notifications()` con SKIP LOCKED |
| `api-keys` | `hk_live_*` prefix+hash, create/validate/revoke + usage log |
| `utils` | Helpers compartidos (`set_updated_at`, etc.) |

---

## Setup rápido

### 1. Requisitos

```bash
# Obligatorio
PostgreSQL ≥ 14 (local) o Docker Desktop

# Opcionales
jq       # para inject.sh
psql     # cliente CLI
```

### 2. Clonar

```bash
git clone https://github.com/RubenGZ/Start-up-Pack.git
cd Start-up-Pack
```

### 3. Configurar credenciales (NUNCA en el repo)

```bash
# Copiar plantillas — los archivos .env y .mcp.json están en .gitignore
cp .env.example .env
cp .mcp.json.example .mcp.json
```

Editar `.env`:
```bash
# .env — credenciales locales, NUNCA committear
DATABASE_URL=postgres://hydra:tu_password@localhost:5432/hydra_dev
POSTGRES_PASSWORD=tu_password_seguro

# Stripe (solo si usas billing) — obtener en dashboard.stripe.com
STRIPE_SECRET_KEY=<pegar_tu_stripe_secret_key_aqui>
STRIPE_WEBHOOK_SECRET=<pegar_tu_webhook_secret_aqui>

# JWT — mínimo 32 caracteres aleatorios
JWT_SECRET=<generar_con: openssl rand -hex 32>
```

Editar `.mcp.json`:
```jsonc
// .mcp.json — API key de Linear para tu workspace (gitignored)
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@linear/mcp@latest"],
      "env": {
        "LINEAR_API_KEY": "lin_api_TU_KEY_AQUI"
      }
    }
  }
}
```

> Reinicia Claude Code tras crear `.mcp.json`.

### 4. Levantar con Docker (recomendado)

```bash
docker compose up -d          # PostgreSQL 16 + pg_cron
# Las migrations se aplican automáticamente via servicio 'migrate'

# pgAdmin (opcional)
docker compose --profile tools up -d
# Abrir: http://localhost:5050
```

### 5. O levantar sin Docker

```bash
# Instalar PostgreSQL 14+ y crear la DB
createdb hydra_dev

# Aplicar todas las migrations
export DATABASE_URL="postgres://usuario:password@localhost:5432/hydra_dev"
bash core/migrations/runner.sh

# Preview sin ejecutar
bash core/migrations/runner.sh --dry-run
```

---

## ADAPTAR A [NombreStartup]

Para inyectar el framework en un nuevo proyecto:

```bash
# Inyección completa (todos los módulos)
bash inject.sh --reset --project=MiStartup

# Inyección selectiva sin OAuth
bash inject.sh --reset \
  --modules=auth,users,billing,health-base \
  --project=MiStartup \
  --no-oauth

# Módulos disponibles:
# base, auth, users, billing, health-base, seed,
# rate-limit, audit, onboarding, notifications, api-keys, utils
#
# Flags opcionales:
# --no-oauth    Excluye oauth.service.sql del módulo auth
# --project=X   Nombre del proyecto (actualiza blueprints.json)
# --reset       Limpia active_project/ antes de inyectar
```

Después de inyectar:
```bash
bash core/migrations/runner.sh   # aplica el schema a la DB
```

---

## Credenciales por entorno

**Regla de oro: ninguna credencial real vive en este repo.**

| Entorno | Dónde configurar `DATABASE_URL` |
|---------|--------------------------------|
| **Local dev** | `.env` (gitignored) → `cp .env.example .env` |
| **CI/GitHub Actions** | `ci.yml` usa dummy credentials para postgres efímero — no necesita secrets reales |
| **Staging** | Variables de entorno en tu plataforma (Railway / Render / Fly.io) |
| **Producción** | Variables de entorno en tu plataforma — NUNCA en el repo |

**Plataformas de hosting — dónde poner el DATABASE_URL real:**

```
Railway  → Project → Variables → Add DATABASE_URL
Render   → Environment → Environment Variables → Add DATABASE_URL
Fly.io   → fly secrets set DATABASE_URL="postgres://..."
Supabase → Settings → Database → Connection string
Heroku   → Settings → Config Vars → Add DATABASE_URL
```

**Para Stripe webhooks en producción:**
```
STRIPE_WEBHOOK_SECRET → Variable de entorno en tu hosting
STRIPE_SECRET_KEY     → Variable de entorno en tu hosting
```

---

## CI/CD — 5 jobs

| Job | Qué valida |
|-----|-----------|
| `health-sweep` | Regla 250L — ningún archivo supera el límite |
| `lint-sql` | Todos los `.sql` < 250 líneas |
| `validate-structure` | Archivos clave presentes en el repo |
| `validate-migrations` | Secuencia numérica estricta, ninguna vacía |
| `integration-test` | PostgreSQL 16 real, 20 migrations aplicadas, 3 smoke tests |

> El job `integration-test` usa credenciales dummy (`hydra/hydra`) para un postgres efímero en GitHub Actions. No expone ninguna credencial real.

---

## Herramientas de desarrollo

```bash
# Health check del repo (regla 250L)
bash core/infra/health_sweep.sh .

# Dry-run de migrations (preview sin ejecutar)
bash core/migrations/runner.sh --dry-run

# Inyección de módulos específicos
bash inject.sh --modules=auth,users --project=MiApp

# Limpieza local con Docker
docker compose down -v   # elimina contenedores + volúmenes
docker compose up -d     # vuelve a levantar limpio
```

---

## Estructura completa

```
/blueprints/
  base/              → extensiones + schema_versions
  auth/              → magic link, oauth, session, auth context
  users/             → users, organizations, member management
  billing/           → subscriptions, invoices, stripe webhooks
  health-base/       → health_check()
  seed/              → datos demo reproducibles
  rate-limit/        → sliding window + cleanup
  audit/             → audit_log + trigger universal
  onboarding/        → progress tracking + invitaciones
  notifications/     → in-app + email queue + dequeue worker
  api-keys/          → prefix+hash, create/validate/revoke
  utils/             → helpers compartidos

/core/
  MAP.json           → GPS del repo (fuente de verdad técnica)
  migrations/
    runner.sh        → ejecutor de migrations (usa REPO_ROOT absoluto)
    sql/             → 0001_init.sql … 0020_api_keys.sql
  infra/
    health_sweep.sh  → verifica regla 250L
    Dockerfile.db    → postgres:16 + pg_cron
    pg_cron_init.sql → CREATE EXTENSION pg_cron (Docker init)
    .env.example     → plantilla de variables (ver raíz también)
  automation/
    zen_sequence.sh  → log + commit + push
    log_append.sh    → escribe en docs/index.html

/active_project/     → startup inyectada (volátil)
  blueprints.json    → módulos activos + nombre del proyecto
  schemas/           → DDL inyectado
  services/          → stored procs inyectados

/docs/
  index.html         → Mission control dashboard

inject.sh            → inyector de blueprints
docker-compose.yml   → stack local (db + migrate + pgadmin)
.env.example         → plantilla de variables de entorno
.gitignore           → .env, .mcp.json, secrets (nunca en repo)
```

---

## Linear — workflow

**Team:** SUP · **Workspace:** linear.app/start-up-pack

| Prioridad | Significado |
|-----------|-------------|
| 1 Urgent | Bloquea deploy / funcionalidad core |
| 2 High | Bloquea flujo de desarrollo |
| 3 Medium | Mejora importante, no bloqueante |
| 4 Low | Nice to have |

Protocolo: **crear issue en Linear ANTES de implementar** → implementar → marcar Done tras push.

---

## Stakeholders

| Persona | Rol |
|---------|-----|
| RGM | Propietario |
| JPM | Colaborador |
