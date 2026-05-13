# active_project/

Carpeta volátil. Contiene los blueprints inyectados para la startup activa.

**NO editar manualmente.** Usar `inject.sh` para poblar.

```bash
# Inyectar módulos por defecto (auth, users, billing, utils)
bash inject.sh

# Inyectar módulos específicos
bash inject.sh --modules=auth,users,health-base

# Reset completo + reinyectar
bash inject.sh --reset --modules=auth,users,billing,utils
```

## Estructura tras inyección

```
active_project/
  schemas/    → DDL de los blueprints activados
  services/   → stored procedures inyectados
  utils/      → helpers compartidos
  blueprints.json → registro de módulos activos + timestamp
```

## Protocolo ADAPTAR A [Idea]

Al recibir `ADAPTAR A [Nombre Startup]`:
1. `bash inject.sh --reset --modules=<módulos relevantes>`
2. Actualizar `active_project/blueprints.json` con nombre del proyecto
3. Actualizar dashboard `docs/index.html` con nuevo proyecto activo
4. Redefinir scope en Linear
