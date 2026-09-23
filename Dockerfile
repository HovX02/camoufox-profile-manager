# One image, one process: FastAPI serves the REST API and the built web UI on a
# single port, exactly as `camoufox-pm` does outside a container. The UI is built
# in the first stage and copied in, so the runtime image carries no Node.
#
# Note: launching real browsers inside a container needs a virtual display
# (Camoufox headless="virtual" / Xvfb on Linux). This image runs the API, the
# scheduler and profile management; see docs/accessibility-roadmap.md.

FROM node:20-slim AS webui
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
ENV NEXT_EXPORT=1
RUN npm run build

FROM python:3.12-slim

# Install system dependencies required for Xvfb, Camoufox/Firefox, and remote visual display (noVNC)
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    openbox \
    libgtk-3-0 \
    libasound2 \
    libx11-xcb1 \
    libdbus-glib-1-2 \
    libxt6 \
    libpci3 \
    procps \
    && rm -rf /var/lib/apt/lists/*

# uv for fast, reproducible installs.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Install dependencies first (better layer caching).
COPY pyproject.toml uv.lock README.md ./
COPY src ./src
RUN uv sync --no-dev --frozen

# Pre-fetch the Camoufox browser binary and required assets
RUN uv run camoufox fetch

# The static export, where the package looks for it when no CPM_WEBUI_DIR is set.
COPY --from=webui /web/out ./src/camoufox_pm/webui

COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV CPM_HOST=0.0.0.0 \
    CPM_PORT=8000 \
    CPM_DB_PATH=/data/profiles.db \
    DISPLAY=:99

VOLUME ["/data"]
EXPOSE 8000 6080

ENTRYPOINT ["docker-entrypoint.sh"]

# The console script, so the container runs the same entry point as a local
# install rather than a second, drifting invocation of uvicorn.
CMD ["uv", "run", "camoufox-pm", "--host", "0.0.0.0", "--port", "8000", "--no-browser"]
