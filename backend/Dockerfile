# Cloud Run image: dependencies from the lockfile, no dev tools, non-root user.
FROM ghcr.io/astral-sh/uv:0.12.19-python3.12-bookworm-slim AS build
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN uv sync --locked --no-dev --no-editable

FROM python:3.12-slim-bookworm
RUN useradd --create-home --uid 10001 pli
COPY --from=build --chown=pli:pli /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER pli
CMD ["sh", "-c", "exec uvicorn --factory pli.main:creer_app_depuis_env --host 0.0.0.0 --port ${PORT:-8080} --no-server-header"]
