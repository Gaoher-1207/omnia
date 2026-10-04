"""Persist adaptive replan proposals and snapshot revisions.

Revision ID: 0007
Revises: 0006
"""

from collections import defaultdict
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007"
down_revision: str | Sequence[str] | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    bind = op.get_bind()
    ai_plans = sa.table(
        "ai_plans",
        sa.column("id", sa.Uuid()),
        sa.column("user_id", sa.Uuid()),
        sa.column("plan_date", sa.Date()),
        sa.column("created_at", sa.DateTime(timezone=True)),
        sa.column("revision", sa.Integer()),
    )
    op.add_column("ai_plans", sa.Column("revision", sa.Integer(), nullable=True))
    rows = bind.execute(
        sa.select(ai_plans.c.id, ai_plans.c.user_id, ai_plans.c.plan_date, ai_plans.c.created_at).order_by(
            ai_plans.c.user_id, ai_plans.c.plan_date, ai_plans.c.created_at, ai_plans.c.id
        )
    )
    counters: dict[tuple[object, object], int] = defaultdict(int)
    for row in rows:
        key = (row.user_id, row.plan_date)
        counters[key] += 1
        bind.execute(sa.update(ai_plans).where(ai_plans.c.id == row.id).values(revision=counters[key]))
    with op.batch_alter_table("ai_plans") as batch:
        batch.alter_column("revision", existing_type=sa.Integer(), nullable=False, server_default=sa.text("1"))
    op.create_index("uq_ai_plans_user_date_revision", "ai_plans", ["user_id", "plan_date", "revision"], unique=True)

    op.create_table(
        "replan_proposals",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("base_plan_id", sa.Uuid(), nullable=False),
        sa.Column("base_revision", sa.Integer(), nullable=False),
        sa.Column("base_fingerprint", sa.String(length=64), nullable=False),
        sa.Column("plan_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(length=12), server_default="pending", nullable=False),
        sa.Column("provider", sa.String(length=20), nullable=False),
        sa.Column("request", sa.String(length=1000), nullable=False),
        sa.Column("summary", sa.String(length=280), nullable=False),
        sa.Column("explanation", sa.String(length=1000), nullable=False),
        sa.Column("operations", sa.JSON(), nullable=False),
        sa.Column("schedule", sa.JSON(), nullable=False),
        sa.Column("warnings", sa.JSON(), nullable=False),
        sa.Column("validation", sa.JSON(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("applied_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("dismissed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "status IN ('pending', 'applied', 'dismissed', 'stale', 'expired', 'invalid')",
            name=op.f("ck_replan_proposals_status"),
        ),
        sa.ForeignKeyConstraint(["base_plan_id"], ["ai_plans.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_replan_proposals")),
    )
    op.create_index("ix_replan_proposals_owner_status", "replan_proposals", ["user_id", "status"])
    op.create_index("ix_replan_proposals_base_plan", "replan_proposals", ["base_plan_id"])
    op.create_index("ix_replan_proposals_owner_date", "replan_proposals", ["user_id", "plan_date", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_replan_proposals_owner_date", table_name="replan_proposals")
    op.drop_index("ix_replan_proposals_base_plan", table_name="replan_proposals")
    op.drop_index("ix_replan_proposals_owner_status", table_name="replan_proposals")
    op.drop_table("replan_proposals")
    op.drop_index("uq_ai_plans_user_date_revision", table_name="ai_plans")
    op.drop_column("ai_plans", "revision")
