"""Record what actually happened to each plan block.

Revision ID: 0008
Revises: 0007
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0008"
down_revision: str | Sequence[str] | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "plan_item_outcomes",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("plan_date", sa.Date(), nullable=False),
        sa.Column("item_key", sa.String(length=80), nullable=False),
        sa.Column("plan_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(length=10), nullable=False),
        sa.Column("category", sa.String(length=12), nullable=False),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("start", sa.String(length=5), nullable=False),
        sa.Column("end", sa.String(length=5), nullable=False),
        sa.Column("task_id", sa.Uuid(), nullable=True),
        sa.Column("subject_id", sa.Uuid(), nullable=True),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("status IN ('done', 'partial', 'skipped')", name=op.f("ck_plan_item_outcomes_status")),
        sa.ForeignKeyConstraint(["plan_id"], ["ai_plans.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_plan_item_outcomes")),
    )
    op.create_index(
        "uq_plan_item_outcomes_owner_item", "plan_item_outcomes", ["user_id", "plan_date", "item_key"], unique=True
    )


def downgrade() -> None:
    op.drop_index("uq_plan_item_outcomes_owner_item", table_name="plan_item_outcomes")
    op.drop_table("plan_item_outcomes")
