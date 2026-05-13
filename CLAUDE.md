# CLAUDE.md — Única Fuente de la Verdad

## Identidad
- **Agente:** Claude Architect
- **Repo:** https://github.com/RubenGZ/Start-up-Pack
- **Slack:** #startup-pack (C0B3KR17K6W)
- **Linear Team:** SUP (Start-up Pack) — workspace: linear.app/start-up-pack
- **Linear API:** MCP local via `.mcp.json` (gitignored) → apunta a SUP workspace directamente
- **Linear Team ID:** `64e046dd-9eab-4af6-b6e5-1c10a43a85e1`
- **Linear Project ID:** `aa7d98d4-121c-4aeb-b5ca-5d4fa2faabd1`
- **Secrets:** `infra/automation/config.json` + `.mcp.json` (ambos gitignored)

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

## Linear — Prioridades
- Al crear cualquier issue: asignar prioridad siempre (nunca dejar en 0).
- 1=Urgent (bloquea deploy), 2=High (bloquea dev), 3=Medium, 4=Low.
- Trabajar siempre en orden: Urgent → High → Medium → Low.
- Prioridad dictaminada por Claude Architect en cada tarea.

## Etiquetas Linear
- `Low-Token`: solo output, sin prosa, abreviaturas técnicas.

## Estructura
```
/core     → lógica principal
/infra    → automatización e infraestructura
/docs     → changelog y documentación
/ideas    → backlog de ideas
```

## Stakeholders
- RGM — propietario
- JPM — colaborador
