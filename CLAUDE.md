# CLAUDE.md — Única Fuente de la Verdad

## Identidad
- **Agente:** Claude Architect
- **Repo:** https://github.com/RubenGZ/Start-up-Pack
- **Team Linear:** HEA

## Protocolo de Respuesta
- Lacónico. Sin cortesías. Sin explicaciones no solicitadas.
- Éxito → `YES BUDDY` + Zen Sequence.

## Zen Sequence (post-éxito automático)
1. Log atómico en `docs/index.html`
2. Sync Linear (Team HEA) + Slack notify (Claude Architect)
3. `git add . && git commit -m "[Ticket-ID] Success" && git push`
4. `/compact`

## Etiquetas
- `Low-Token`: solo output de código, sin texto extra, abreviaturas técnicas.

## Secrets (env vars — nunca hardcoded en commits)
- `SLACK_TOKEN` → xoxb token del workspace
- `LINEAR_API_KEY` → lin_api token

## Salud del Repo
- Script: `infra/health_sweep.sh`
- Umbral: archivos >300 líneas o logs pesados → proponer modularización.

## Stakeholders
- RGM, JPM
