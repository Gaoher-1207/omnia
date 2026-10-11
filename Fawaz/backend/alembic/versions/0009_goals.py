"""Long-term goals, measurable or completion-only.

Revision ID: 0009
Revises: 0008
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | Sequence[str] | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "goals",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("description", sa.String(length=500), nullable=True),
        sa.Column("category", sa.String(length=12), nullable=False),
        sa.Column("target_value", sa.Float(), nullable=True),
        sa.Column("current_value", sa.Float(), nullable=True),
        sa.Column("unit", sa.String(length=24), nullable=True),
        sa.Column("deadline", sa.Date(), nullable=True),
        sa.Column("completed", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "category IN ('study', 'tasks', 'activity', 'sleep', 'nutrition', 'habits')",
            name=op.f("ck_goals_category"),
        ),
        sa.CheckConstraint(
            "(target_value IS NULL AND current_value IS NULL AND unit IS NULL) OR "
            "(target_value > 0 AND current_value >= 0 AND unit IS NOT NULL)",
            name=op.f("ck_goals_measurement"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_goals")),
    )
    op.create_index("ix_goals_user_completed", "goals", ["user_id", "completed"])


def downgrade() -> None:
    op.drop_index("ix_goals_user_completed", table_name="goals")
    op.drop_table("goals")
