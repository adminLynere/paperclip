# paperclip

> Self-host de [Paperclip](https://hub.docker.com/r/tuyenvd/paperclip) + **Codex CLI** para la
> organización agentic de Lynere. Casa del workflow que construye y publica la imagen a GHCR.

Repo privado de `adminLynere`. Parte del ecosistema agentic — ver [`infra`](https://github.com/adminLynere/infra) para el diagrama de interconexión.

## Qué es

Paperclip es el **cerebro/organización** agentic (trabajadores, departamentos, tickets,
heartbeats, budgets, memoria). Se ejecuta self-host en Railway:
`https://paperclip-production-cf42.up.railway.app`.

La imagen base `tuyenvd/paperclip` **no trae el CLI de Codex**, que los agentes necesitan para
ejecutar trabajo. Este repo añade encima:

- **Node 22 + `@openai/codex`** (+ `git`, `ripgrep` que usa `codex exec`).
- Una **config de Codex horneada** que apunta el harness a **OpenRouter** (abajo).

## Backend de modelo: OpenRouter

El harness sigue siendo Codex CLI, pero su **backend de modelo es OpenRouter** (un proveedor
OpenAI-compatible), no la cuenta de ChatGPT. La config se hornea en la imagen
(`$CODEX_HOME/config.toml`):

```toml
model = "openai/gpt-5.4-mini"      # mismo modelo que el Codex local de lynere; override con build-arg
model_provider = "openrouter"

[model_providers.openrouter]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"
env_key = "OPENROUTER_API_KEY"     # Codex lee la key en runtime de esta env var
wire_api = "chat"                  # OpenRouter habla Chat Completions, no la Responses API
```

- **La API key NO se hornea.** Es secreto de runtime: setea `OPENROUTER_API_KEY` como variable del
  servicio `paperclip` en Railway (key de [openrouter.ai/keys](https://openrouter.ai/keys)).
- **Cambiar de modelo** (Claude, Gemini, modelos baratos…): rebuild con
  `--build-arg CODEX_MODEL=<slug>` (verifica el slug en [openrouter.ai/models](https://openrouter.ai/models)).
  OpenRouter da facturación unificada y fallback entre modelos.
- `CODEX_HOME=/opt/codex` (ruta primaria, **nunca** montada como volumen → ningún volumen de Railway
  puede ocultar la config; hay una copia de respaldo en `/root/.codex`).

### Por qué esto sustituye al antiguo "fix del 401"

La versión anterior autenticaba Codex con `codex login --device-auth` → `/root/.codex/auth.json`
(root, `0600`, en un volumen). Como un proceso **no-root** no podía leer ese archivo, devolvía
**401 "missing bearer"**, y por eso el contenedor corría con `USER root` y el volumen persistía la
credencial. Con OpenRouter la credencial es una **API key por env var**, así que **desaparecen**
`auth.json`, el flujo `device-auth`, el volumen de credenciales y el motivo del `USER root`
(se mantiene `root` solo porque la imagen base lo espera).

## Imagen GHCR

`ghcr.io/adminlynere/paperclip-codex` — construida por
`.github/workflows/build-paperclip-image.yml`:

- **PR / push a `main`** → **build only** (valida el Dockerfile). CI verde sin secretos.
- **push a `main`** con variable de repo `PUBLISH_IMAGE = true`, o **`workflow_dispatch`**
  (`publish=true`) → build + **push** (`:latest` y `:sha-<sha>`).

La imagen es **privada**: el pull requiere un PAT con scope `read:packages`.

### Habilitar el push (una vez)

El paquete `paperclip-codex` se creó desde el monorepo `lynere` y está **vinculado a él**, así que
el `GITHUB_TOKEN` de *este* repo no puede escribirlo (push → `403 Forbidden`). Para habilitar la
publicación desde este repo:

1. **Conceder acceso al paquete**: GitHub → org **Packages** → `paperclip-codex` → *Package
   settings* → **Manage Actions access** → *Add repository* → `adminLynere/paperclip` → Role **Write**.
2. **Activar el push automático** (opcional): repo *Settings → Secrets and variables → Actions →
   Variables* → `PUBLISH_IMAGE = true`. (O usar `workflow_dispatch` con `publish=true` puntualmente.)

## Deploy en Railway

Dos modos (servicio `paperclip`, ID `931a5318-7340-4525-a83c-862e161fbc5f`, env `dev`):

1. **Build en Railway desde este repo** (config-as-code):
   - Source = `adminLynere/paperclip`, Config Path = `railway.toml`, Root Dir = `/`.
   - Railway construye el `Dockerfile` en cada push.
2. **Deploy por PULL de la imagen GHCR** (más rápido, evita rebuild en Railway):
   - Apuntar el servicio a `ghcr.io/adminlynere/paperclip-codex:latest`.
   - Dar a Railway un **PAT `read:packages`** (Variables / registry credentials) porque la
     imagen es privada.

En ambos casos:

- Setear la variable **`OPENROUTER_API_KEY`** en el servicio.
- **Desmontar el antiguo `paperclip-volume`** de `/root/.codex` (su único propósito era persistir
  `auth.json`, que ya no existe). La config de Codex va horneada en la imagen. Si persistes datos
  propios de Paperclip, usa un mountPath distinto, no `/opt/codex` ni `/root/.codex`.
- **App Sleeping OFF** (`sleepApplication = false`) — los heartbeats de los agentes no deben pausarse.

## Verificar que los agentes pueden ejecutar Codex

```bash
# El CLI está instalado y la config apunta a OpenRouter:
railway run --service paperclip -- codex --version
railway run --service paperclip -- cat /opt/codex/config.toml

# Smoke directo del backend (sustituye <model> por el slug horneado):
railway run --service paperclip -- sh -lc \
  'curl -s https://openrouter.ai/api/v1/chat/completions \
     -H "Authorization: Bearer $OPENROUTER_API_KEY" \
     -H "Content-Type: application/json" \
     -d "{\"model\":\"openai/gpt-5.4-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}"'

# End-to-end vía Paperclip (CEO key en PAPERCLIP_API_KEY):
curl -s https://paperclip-production-cf42.up.railway.app/api/agents/me \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY"
# disparar un heartbeat/invoke del CEO (self-only):
curl -s -X POST .../api/agents/4927e29e/heartbeat/invoke \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY"
```

## Flujo de ramas (gobernanza)

`feature/* → development → main` (misma convención que `lynere`). PRs **contra `development`**
(la CI valida el build); el push de la imagen a GHCR ocurre solo desde `main`. **Merge a `main` =
aprobación humana** (L4). El plan free de la org no permite branch protection en privados → la regla
se aplica **por convención**.
