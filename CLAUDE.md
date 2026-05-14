# CLAUDE.md — Única Fuente de la Verdad

## Identidad
- **Agente:** Claude Architect
- **Repo:** https://github.com/RubenGZ/Start-up-Pack
- **Slack:** #startup-pack (C0B3KR17K6W)
- **Linear Team:** SUP (Start-up Pack) — workspace: linear.app/start-up-pack
- **Linear API:** MCP local via `.mcp.json` (gitignored) → apunta a SUP workspace directamente
- **Linear Team ID:** `64e046dd-9eab-4af6-b6e5-1c10a43a85e1`
- **Linear Project ID:** `aa7d98d4-121c-4aeb-b5ca-5d4fa2faabd1`
- **Secrets:** `core/infra/.env` + `.mcp.json` (ambos gitignored)

## Patrón MCP per-proyecto
Cada proyecto tiene su propio `.mcp.json` (gitignored) con el API key de su workspace:
```bash
cp .mcp.json.example .mcp.json
# editar LINEAR_API_KEY con el key del workspace correcto
```
El plugin global `linear@claude-plugins-official` está deshabilitado en `.claude/settings.json`.
Así cada proyecto usa su propio Linear workspace sin interferencia.

## Reglas de Oro
- Lacónico. Sin cortesías. Sin lenguaje natural.
- Éxito → 1 línea atómica + % contexto + Next Step (≤5 palabras) → `YES BUDDY` → Zen Sequence.

## Test-Before-Push (QA Gate obligatorio)
**No se permite hacer `git push` ni emitir `YES BUDDY` sin que `./core/tests/run_tests.sh` devuelva PASS total.**
- Script: `bash core/tests/run_tests.sh`
- Exit 0 = autorizado. Exit 1 = bloqueado.
- Tests en: `core/tests/*.sql` (pgTAP sobre contenedor Docker efímero)
- Excepción: cambios exclusivos en `docs/`, `ideas/` o `CLAUDE.md` (no afectan SQL)
- Módulos cubiertos: auth ✅ (9) | billing ✅ (14) | users 🔜 | rate-limit 🔜

## Formato de Respuesta
```
[DONE] <qué se ejecutó> | ctx: X% | Next: <≤5 palabras>
YES BUDDY
```

## Zen Sequence (post-éxito)
1. Log atómico en `docs/index.html`
2. Actualizar `CLAUDE.md` si hay info estructural nueva
3. `git add . && git commit -m "[SUP-X] ..." && git push`
4. Recordar al usuario: **"Ejecuta /compact ahora"**

## Smart-Context (Gestión Dinámica)
- Antes de iniciar tarea: `du -h <módulo>` para evaluar tamaño.
- Si módulo > 50% del umbral de auto-compactado → activar **Surgical-Reading**: leer solo definiciones de funciones, no cuerpos de código.

## Modularidad Pura
- Archivos: máximo **250 líneas**.
- Si un archivo supera 250L → refactorizar en submódulos inmediatamente.
- Propósito: consumo de tokens bajo por diseño, independiente del tamaño total del proyecto.

## Protocolo ADAPTAR A [Idea]
Al recibir la orden `ADAPTAR A [Nombre/Concepto]`:
1. Limpiar `active_project/`: `bash inject.sh --reset --modules=<módulos relevantes>`
2. Actualizar `active_project/blueprints.json` con el nombre del nuevo proyecto
3. Evaluar qué blueprints aplican (auth=siempre, billing=si tiene pagos, etc.)
4. Actualizar dashboard `docs/index.html` → sección "Proyecto Activo"
5. Redefinir scope en Linear: cerrar issues obsoletos, crear nuevos con prioridad
6. Actualizar este CLAUDE.md con el nuevo contexto de negocio

## Hydra Framework — Estructura
```
/core/
  MAP.json          → GPS del repo (fuente de verdad técnica)
  automation/       → zen_sequence.sh, log_append.sh
  migrations/       → runner.sh + sql/ versionadas
  infra/            → health_sweep.sh, .env (gitignored), .env.example
/blueprints/
  base/             → extensiones + schema_versions
  auth/             → magic link, oauth, session
  users/            → users, organizations
  billing/          → subscriptions, billing service
  health-optional/  → health_check() endpoint + domain blueprints (opt-in)
  utils/            → helpers compartidos
/active_project/
  blueprints.json   → módulos activos de la startup actual
  schemas/          → DDL inyectado (volátil, via inject.sh)
  services/         → stored procs inyectados
  utils/            → helpers inyectados
/docs/              → index.html mission control
/ideas/             → backlog.md
inject.sh           → inyector de blueprints
```

## Linear — Prioridades
- Al crear cualquier issue: asignar prioridad siempre (nunca dejar en 0).
- 1=Urgent (bloquea deploy), 2=High (bloquea dev), 3=Medium, 4=Low.
- Trabajar siempre en orden: Urgent → High → Medium → Low.
- Prioridad dictaminada por Claude Architect en cada tarea.

## Etiquetas Linear
- `Low-Token`: solo output, sin prosa, abreviaturas técnicas.

## Stakeholders
- RGM — propietario
- JPM — colaborador
