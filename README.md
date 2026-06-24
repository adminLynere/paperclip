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
- `VOLUME /root/.codex` para persistir el login de Codex entre reinicios/sleeps.
- **`USER root`** — clave para el fix del 401 (abajo).

## El fix del 401 ("missing bearer")

Codex ≥ 0.122 lee las credenciales **solo** de `$CODEX_HOME/auth.json`. El login vive en
`/root/.codex/auth.json` (propiedad de `root`, modo `0600`, en el volumen). Un proceso
**no-root** no puede leer ese archivo ni atravesar `/root` (modo `700`) → Codex no encuentra
credenciales y devuelve **401**. Por eso el contenedor corre como `root` (`USER root`).

Login (una vez, persiste en el volumen):

```bash
railway run --service paperclip -- codex login --device-auth
# verificar:
railway run --service paperclip -- codex --version
```

## Imagen GHCR

`ghcr.io/adminlynere/paperclip-codex` — construida y publicada por
`.github/workflows/build-paperclip-image.yml`:

- **PR** → build only (valida el Dockerfile).
- **push a `main`** / `workflow_dispatch` → build + push (`:latest` y `:sha-<sha>`).

La imagen es **privada**: el pull requiere un PAT con scope `read:packages`.

## Deploy en Railway

Dos modos (servicio `paperclip`, ID `931a5318-7340-4525-a83c-862e161fbc5f`, env `dev`):

1. **Build en Railway desde este repo** (config-as-code):
   - Source = `adminLynere/paperclip`, Config Path = `railway.toml`, Root Dir = `/`.
   - Railway construye el `Dockerfile` en cada push.
2. **Deploy por PULL de la imagen GHCR** (más rápido, evita rebuild en Railway):
   - Apuntar el servicio a `ghcr.io/adminlynere/paperclip-codex:latest`.
   - Dar a Railway un **PAT `read:packages`** (Variables / registry credentials) porque la
     imagen es privada.

En ambos casos: volumen `paperclip-volume` en `/root/.codex`, y **App Sleeping OFF**
(`sleepApplication = false`) — los heartbeats de los agentes no deben pausarse.

## Verificar que los agentes pueden ejecutar Codex

```bash
# CEO key en PAPERCLIP_API_KEY (.env):
curl -s https://paperclip-production-cf42.up.railway.app/api/agents/me \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY"
# disparar un heartbeat/invoke del CEO (self-only):
curl -s -X POST .../api/agents/4927e29e/heartbeat/invoke \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY"
```
