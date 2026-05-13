# startup-pack

Infraestructura modular para SaaS B2B — PostgreSQL · GitHub Actions · Linear · Slack.

---

## Agente

**Claude Architect** — modo Zen-Efficiency  
Respuestas atómicas. Sin cortesías. `YES BUDDY` tras cada tarea.

---

## Setup para nuevos colaboradores

### 1. Requisitos
- Node.js ≥ 18 (para `npx @linear/mcp`)
- PostgreSQL ≥ 14
- `curl`, `jq`, `bash`

### 2. Clonar y configurar secrets

```bash
git clone https://github.com/RubenGZ/Start-up-Pack.git
cd Start-up-Pack

# Secrets locales (nunca se commitean)
cp infra/automation/config.json.example infra/automation/config.json
# → editar: slack_token, linear_api_key

# MCP por proyecto (Linear apunta al workspace correcto)
cp .mcp.json.example .mcp.json
# → editar: LINEAR_API_KEY con el key de tu workspace Linear
```

### 3. MCP per-proyecto — Linear

Cada proyecto tiene su propio `.mcp.json` (gitignored) que conecta Claude Code
al workspace Linear correcto. El plugin global `linear@claude-plugins-official`
está deshabilitado en `.claude/settings.json` para evitar interferencias.

```jsonc
// .mcp.json (gitignored — crea el tuyo desde .mcp.json.example)
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

> Reinicia Claude Code tras crear `.mcp.json` para que tome efecto.

### 4. Correr migraciones

```bash
export DATABASE_URL="postgres://user:pass@localhost:5432/startuppack"
bash infra/migrations/runner.sh          # aplica pendientes
bash infra/migrations/runner.sh --dry-run # preview sin ejecutar
```

### 5. Verificar salud del repo

```bash
bash infra/health_sweep.sh .   # detecta archivos >250L y logs >1MB
```

---

## Estructura

```
/core
  /schemas    → DDL ordenado (000–004)
  /services   → auth, oauth, billing
  /utils      → helpers compartidos
/infra
  /migrations → runner.sh + sql/ versionadas (0001–0008)
  /automation → zen_sequence.sh, log_append.sh
/docs         → index.html (mission control dashboard)
/ideas        → backlog.md
.mcp.json     → MCP local por proyecto (gitignored)
.mcp.json.example → plantilla para nuevos colaboradores
```

---

## Linear — workflow y prioridades

**Team:** SUP · **Workspace:** linear.app/start-up-pack

| Prioridad | Significado | Acción |
|-----------|-------------|--------|
| 🔴 Urgent | Bloquea deploy / funcionalidad core | Inmediato |
| 🟠 High | Bloquea flujo de desarrollo | Sprint actual |
| 🟡 Medium | Mejora importante, no bloqueante | Próximo sprint |
| ⚪ Low | Nice to have | Backlog |

**Regla:** Claude Architect asigna prioridad en cada issue creado.
Se trabaja siempre en orden descendente de urgencia.

**Issues activos:**

| Issue | Título | Prioridad | Estado |
|-------|--------|-----------|--------|
| SUP-6 | Health check endpoint /health | 🔴 Urgent | Todo |
| SUP-7 | Seed data desarrollo local | 🟠 High | Backlog |
| SUP-8 | Rate limiting por org | 🟡 Medium | Backlog |
| SUP-9 | Audit log estructurado | 🟡 Medium | Backlog |

---

## Flujo de trabajo

```
Instrucción → Ejecución → [DONE] ... | ctx: X% | Next: ...
                                      ↓
                              YES BUDDY → /compact
```

**Zen Sequence** (post-tarea automático):
1. Log atómico en `docs/index.html`
2. Update `CLAUDE.md` si hay cambio estructural
3. `git push`
4. Recordatorio `/compact`

---

## CI/CD

| Job | Qué valida |
|-----|-----------|
| health-sweep | Archivos >250L, logs >1MB |
| lint-sql | SQL files < 250L |
| validate-structure | Archivos requeridos presentes |
| validate-migrations | Secuencia ordenada, no vacíos |
| slack-notify | Push a main → #startup-pack |

---

## Stakeholders

| Persona | Rol |
|---------|-----|
| RGM | Propietario |
| JPM | Colaborador |
