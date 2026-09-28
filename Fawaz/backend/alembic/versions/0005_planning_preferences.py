"""Account-scoped planning preferences, preserving existing day defaults."""
from alembic import op
import sqlalchemy as sa

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("profiles", sa.Column("planning_start_minutes", sa.Integer(), nullable=False, server_default="480"))
    op.add_column("profiles", sa.Column("planning_end_minutes", sa.Integer(), nullable=False, server_default="1320"))
    op.add_column("profiles", sa.Column("time_format", sa.String(3), nullable=False, server_default="24h"))

    with op.batch_alter_table("profiles") as batch:
        batch.create_check_constraint("planning_window", "planning_start_minutes >= 0 AND planning_end_minutes <= 1439 "
                                      "AND planning_start_minutes < planning_end_minutes")
        batch.create_check_constraint("time_format", "time_format IN ('12h', '24h')")


def downgrade():
    with op.batch_alter_table("profiles") as batch:
        batch.drop_constraint("time_format", type_="check")
        batch.drop_constraint("planning_window", type_="check")
        batch.drop_column("time_format")
        batch.drop_column("planning_end_minutes")
        batch.drop_column("planning_start_minutes")
