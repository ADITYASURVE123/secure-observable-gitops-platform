# syntax=docker/dockerfile:1.7
# Stages: builder -> test -> runtime. `docker build` with no --target produces the
# runtime image; CI runs `--target test` so the pipeline needs no Python on the agent.

FROM python:3.12.12-slim-bookworm AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /build
COPY requirements.txt .
RUN pip install -r requirements.txt

FROM builder AS test
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt
COPY pytest.ini .
COPY orders_api ./orders_api
COPY tests ./tests
RUN pytest

FROM python:3.12.12-slim-bookworm AS runtime
# Fixed numeric UID/GID so Kubernetes `runAsNonRoot` can verify the user without name lookup.
RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app
# Patch fixable OS CVEs at build time, and drop packaging tools the app never uses
# (setuptools/wheel are a common source of scanner findings in python base images).
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && pip uninstall -y setuptools wheel pip || true
COPY --from=builder /opt/venv /opt/venv
WORKDIR /srv
COPY orders_api ./orders_api
ARG APP_VERSION=dev
# Baked in at build time (CI passes the git SHA) so the running version is always discoverable.
ENV PATH=/opt/venv/bin:$PATH PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 APP_VERSION=$APP_VERSION
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status==200 else 1)"
CMD ["uvicorn", "orders_api.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
