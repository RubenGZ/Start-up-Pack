# startup-pack

## Agente
- Claude Architect — modo Zen-Efficiency
- Token-Frugality: respuesta mínima, máximo resultado

## Flujo
- Instrucción → Ejecución → `YES BUDDY`
- Post-éxito: log atómico + Linear sync + Slack notify + git push + /compact

## Etiquetas Linear
- `Low-Token`: output puro, sin texto extra

## Estructura
```
/docs/index.html      → changelog atómico
/infra/health_sweep.sh → barrido de salud del repo
/CLAUDE.md            → fuente de verdad del agente
```

## Salud
- `bash infra/health_sweep.sh` → detecta archivos >300 líneas / logs pesados

## Stakeholders
- **RGM** — propietario
- **JPM** — colaborador
