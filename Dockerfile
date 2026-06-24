# ─────────────────────────────────────────────────────────────────────────────
# Paperclip + Codex CLI (self-host en Railway)
# ─────────────────────────────────────────────────────────────────────────────
# Base: imagen de Paperclip (orquestación agentic). Le añadimos el CLI de Codex
# (@openai/codex) para que los agentes ejecuten Codex autenticado con la cuenta de
# ChatGPT (codex login --device-auth). La auth persiste en /root/.codex → se declara
# como VOLUME y se monta un volumen de Railway para sobrevivir reinicios/sleeps.
#
# ASUNCIÓN: la base es Debian/Ubuntu (usa apt-get). Si fuese Alpine, cambia a `apk add`
# y al instalador de Node de Alpine.
# ─────────────────────────────────────────────────────────────────────────────
FROM tuyenvd/paperclip

# Codex CLI requiere Node 22+. Instalamos también git y ripgrep (los usa `codex exec`).
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates git ripgrep \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && npm install -g @openai/codex \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Persistir credenciales/config de Codex (auth.json, config.toml) entre reinicios.
VOLUME ["/root/.codex"]

# Ejecutar como root para que los procesos de agente puedan LEER el login de Codex
# que vive en /root/.codex/auth.json (propiedad de root, modo 0600, en el volumen).
# Codex >= 0.122 lee las credenciales SOLO de $CODEX_HOME/auth.json; un proceso no-root
# no puede leer el auth.json 0600 de root ni atravesar /root (modo 700) -> 401 sin auth.
USER root
