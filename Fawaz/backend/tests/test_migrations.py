import importlib.util
from datetime import UTC, date, datetime
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine
from sqlalchemy.dialects import postgresql
from sqlalchemy.sql import Select

from app.models import Base

BACKEND = Path(__file__).resolve().parents[1]


def _config(url: str) -> Config:
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "alembic"))
    cfg.set_main_option("sqlalchemy.url", url)
    cfg.attributes["configure_logger"] = False
    return cfg


def test_migrations_upgrade_match_models_and_downgrade(tmp_path):
    url = f"sqlite:///{tmp_path / 'migrate.db'}"
    cfg = _config(url)
    command.upgrade(cfg, "head")

    engine = create_engine(url)
    with engine.connect() as connection:
        context = MigrationContext.configure(connection)
        diff = compare_metadata(context, Base.metadata)
    assert diff == [], f"Models and migrations differ; run alembic revision --autogenerate: {diff}"

    command.downgrade(cfg, "base")
    engine.dispose()


def test_adaptive_replanning_migration_compiles_for_postgresql(monkeypatch):
    migration_path = BACKEND / "alembic" / "versions" / "0007_adaptive_replanning.py"
    spec = importlib.util.spec_from_file_location("adaptive_replanning_migration", migration_path)
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)

    plan_id, user_id = uuid4(), uuid4()
    row = SimpleNamespace(id=plan_id, user_id=user_id, plan_date=date(2026, 10, 4), created_at=datetime.now(UTC))
    compiled_backfill = []

    class BackfillBind:
        def execute(self, statement):
            compiled_backfill.append(str(statement.compile(dialect=postgresql.dialect())))
            return [row] if isinstance(statement, Select) else []

    output = StringIO()
    context = MigrationContext.configure(
        dialect_name="postgresql",
        opts={"as_sql": True, "output_buffer": output},
    )
    monkeypatch.setattr(migration.op, "get_bind", lambda: BackfillBind())
    with Operations.context(context):
        migration.upgrade()

    sql = output.getvalue()
    assert "ALTER COLUMN revision SET NOT NULL" in sql
    assert "CREATE TABLE replan_proposals" in sql
    assert "UUID NOT NULL" in sql and "TIMESTAMP WITH TIME ZONE" in sql
    assert any(statement.lstrip().startswith("UPDATE ai_plans") for statement in compiled_backfill)
