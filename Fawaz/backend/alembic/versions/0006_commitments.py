"""Account-owned manual commitments for planning availability."""

from alembic import op
import sqlalchemy as sa

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "commitments",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(80), nullable=False),
        sa.Column("category", sa.String(20), nullable=False),
        sa.Column("kind", sa.String(10), nullable=False),
        sa.Column("weekdays", sa.JSON(), nullable=False),
        sa.Column("day", sa.Date()),
        sa.Column("start_minutes", sa.Integer(), nullable=False),
        sa.Column("end_minutes", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("start_minutes >= 0 AND end_minutes <= 1439 AND start_minutes < end_minutes", name="ck_commitments_time_range"),
        sa.CheckConstraint("kind IN ('recurring', 'one_off')", name="ck_commitments_kind"),
    )
    op.create_index("ix_commitments_user_id", "commitments", ["user_id"])


def downgrade():
    op.drop_index("ix_commitments_user_id", table_name="commitments")
    op.drop_table("commitments")
