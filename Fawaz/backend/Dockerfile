FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
RUN useradd --create-home --uid 10001 omnia && chown -R omnia /app
USER omnia

EXPOSE 8000
# The API never migrates on start: several replicas racing `alembic upgrade` is unsafe,
# and a failed migration must stop a release, not crash-loop the API. Run the release
# step first with the same image:  docker compose run --rm migrate  (see docs/OPERATIONS.md).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-access-log"]
