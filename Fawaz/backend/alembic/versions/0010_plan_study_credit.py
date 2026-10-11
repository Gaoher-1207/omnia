"""Credit study blocks marked done as study sessions, without double counting Focus time.

Revision ID: 0010
Revises: 0009
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | Sequence[str] | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("study_sessions") as batch:
        batch.add_column(sa.Column("source", sa.String(length=8), server_default="manual", nullable=False))
        batch.add_column(sa.Column("started_at", sa.DateTime(timezone=True), nullable=True))
        batch.create_check_constraint(op.f("ck_study_sessions_source"), "source IN ('manual', 'focus', 'plan')")
    with op.batch_alter_table("plan_item_outcomes") as batch:
        batch.add_column(sa.Column("minutes", sa.Integer(), nullable=True))
        batch.add_column(sa.Column("study_session_id", sa.Uuid(), nullable=True))
        batch.create_foreign_key(
            op.f("fk_plan_item_outcomes_study_session_id_study_sessions"),
            "study_sessions",
            ["study_session_id"],
            ["id"],
            ondelete="SET NULL",
        )


def downgrade() -> None:
    with op.batch_alter_table("plan_item_outcomes") as batch:
        batch.drop_constraint(op.f("fk_plan_item_outcomes_study_session_id_study_sessions"), type_="foreignkey")
        batch.drop_column("study_session_id")
        batch.drop_column("minutes")
    with op.batch_alter_table("study_sessions") as batch:
        batch.drop_constraint(op.f("ck_study_sessions_source"), type_="check")
        batch.drop_column("started_at")
        batch.drop_column("source")
