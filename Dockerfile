# ─────────────────────────────────────────────────────────────────────────────
# Paperclip + Codex CLI (self-host en Railway) — backend de modelo vía OpenRouter
# ─────────────────────────────────────────────────────────────────────────────
# Base: imagen de Paperclip (orquestación agentic). Le añadimos el CLI de Codex
# (@openai/codex) para que los agentes ejecuten trabajo (`codex exec`).
#
# Backend de modelo = OpenRouter (proveedor OpenAI-compatible). Codex lee la API key
# en RUNTIME de $OPENROUTER_API_KEY (variable del servicio en Railway) — NO se hornea
# en la imagen. Esto SUSTITUYE al antiguo login device-auth de ChatGPT:
#   · Antes: `codex login --device-auth` → /root/.codex/auth.json (root, 0600, en un
#     volumen). Un proceso no-root no podía leerlo → 401 "missing bearer", de ahí el
#     VOLUME y el USER root.
#   · Ahora: la credencial es una API key por env var → desaparecen auth.json, el VOLUME
#     y el motivo del USER root. Para cambiar de modelo (Claude/Gemini/etc.) basta con
#     repuntar el slug; OpenRouter da facturación unificada y fallback entre modelos.
#
# ASUNCIÓN: la base es Debian/Ubuntu (usa apt-get). Si fuese Alpine, cambia a `apk add`
# y al instalador de Node de Alpine.
# ─────────────────────────────────────────────────────────────────────────────
FROM tuyenvd/paperclip

# Modelo por defecto (slug de OpenRouter). Mantiene los mismos modelos que el Codex
# local de lynere (.codex/config.toml: gpt-5.4-mini). Override en build:
#   docker build --build-arg CODEX_MODEL=anthropic/claude-sonnet-4 ...
# Verifica el slug exacto en https://openrouter.ai/models.
ARG CODEX_MODEL=openai/gpt-5.4-mini

# Codex CLI requiere Node 22+. Instalamos también git y ripgrep (los usa `codex exec`).
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates git ripgrep \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && npm install -g @openai/codex \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Config de Codex horneada en la imagen: apunta el harness a OpenRouter.
# CODEX_HOME=/opt/codex es la ruta primaria (NUNCA montada como volumen, así un volumen
# de Railway no puede ocultar la config). Escribimos también una copia en /root/.codex
# por si algún proceso de Paperclip fuerza el CODEX_HOME por defecto.
# La API key NO va aquí: es secreto de runtime ($OPENROUTER_API_KEY).
ENV CODEX_HOME=/opt/codex
RUN for dir in /opt/codex /root/.codex; do \
      mkdir -p "$dir"; \
      { \
        echo "# Generado en build (imagen paperclip-codex). Backend de modelo: OpenRouter."; \
        echo "# La API key NO se hornea: Codex la lee en runtime de \$OPENROUTER_API_KEY."; \
        echo "# Cambiar de modelo: rebuild con --build-arg CODEX_MODEL=<slug de openrouter.ai/models>."; \
        echo "model = \"$CODEX_MODEL\""; \
        echo "model_provider = \"openrouter\""; \
        echo ""; \
        echo "[model_providers.openrouter]"; \
        echo "name = \"OpenRouter\""; \
        echo "base_url = \"https://openrouter.ai/api/v1\""; \
        echo "env_key = \"OPENROUTER_API_KEY\""; \
        echo "wire_api = \"chat\""; \
        echo ""; \
        echo "[model_providers.openrouter.http_headers]"; \
        echo "\"X-Title\" = \"Lynere Paperclip\""; \
      } > "$dir/config.toml"; \
    done

# Se ejecuta como root igual que la imagen base (Paperclip espera root). Ya NO es por
# auth.json — esa credencial desapareció con el switch a OpenRouter por env var.
USER root
