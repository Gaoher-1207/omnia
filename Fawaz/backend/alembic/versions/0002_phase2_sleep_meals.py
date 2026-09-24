"""phase 2: sleep, meals, task details, profile goals

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-24 15:35:41.338250

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0002'
down_revision: Union[str, Sequence[str], None] = '0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('meals',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('day', sa.Date(), nullable=False),
    sa.Column('meal_type', sa.String(length=10), nullable=False),
    sa.Column('description', sa.String(length=200), nullable=False),
    sa.Column('calories', sa.Integer(), nullable=False),
    sa.Column('protein_g', sa.Integer(), nullable=False),
    sa.Column('carbs_g', sa.Integer(), nullable=False),
    sa.Column('fat_g', sa.Integer(), nullable=False),
    sa.Column('source', sa.String(length=16), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')", name=op.f('ck_meals_meal_type')),
    sa.CheckConstraint("source IN ('manual', 'photo_estimate')", name=op.f('ck_meals_source')),
    sa.CheckConstraint('calories BETWEEN 0 AND 5000', name=op.f('ck_meals_calories_range')),
    sa.CheckConstraint('carbs_g BETWEEN 0 AND 1000', name=op.f('ck_meals_carbs_range')),
    sa.CheckConstraint('fat_g BETWEEN 0 AND 500', name=op.f('ck_meals_fat_range')),
    sa.CheckConstraint('protein_g BETWEEN 0 AND 500', name=op.f('ck_meals_protein_range')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_meals_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_meals'))
    )
    with op.batch_alter_table('meals', schema=None) as batch_op:
        batch_op.create_index('ix_meals_user_day', ['user_id', 'day'], unique=False)

    op.create_table('sleep_logs',
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('day', sa.Date(), nullable=False),
    sa.Column('duration_minutes', sa.Integer(), nullable=False),
    sa.Column('quality', sa.Integer(), nullable=True),
    sa.Column('bedtime', sa.Time(), nullable=True),
    sa.Column('wake_time', sa.Time(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint('duration_minutes BETWEEN 0 AND 1440', name=op.f('ck_sleep_logs_duration_range')),
    sa.CheckConstraint('quality BETWEEN 1 AND 5', name=op.f('ck_sleep_logs_quality_range')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_sleep_logs_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_sleep_logs')),
    sa.UniqueConstraint('user_id', 'day', name='uq_sleep_logs_user_day')
    )
    with op.batch_alter_table('sleep_logs', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_sleep_logs_user_id'), ['user_id'], unique=False)

    with op.batch_alter_table('profiles', schema=None) as batch_op:
        batch_op.add_column(sa.Column('daily_sleep_goal_minutes', sa.Integer(), server_default=sa.text('(480)'), nullable=False))
        batch_op.add_column(sa.Column('daily_calorie_goal', sa.Integer(), server_default=sa.text('(2000)'), nullable=False))
        batch_op.add_column(sa.Column('username', sa.String(length=30), nullable=True))
        batch_op.create_index(batch_op.f('ix_profiles_username'), ['username'], unique=True)
        batch_op.create_check_constraint(
            op.f('ck_profiles_sleep_goal_range'), 'daily_sleep_goal_minutes BETWEEN 0 AND 960'
        )
        batch_op.create_check_constraint(op.f('ck_profiles_calorie_goal_range'), 'daily_calorie_goal BETWEEN 0 AND 10000')

    with op.batch_alter_table('tasks', schema=None) as batch_op:
        batch_op.add_column(sa.Column('due_time', sa.Time(), nullable=True))
        batch_op.add_column(sa.Column('estimated_minutes', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('category', sa.String(length=12), server_default=sa.text("'tasks'"), nullable=False))
        batch_op.create_check_constraint(
            op.f('ck_tasks_category'),
            "category IN ('study', 'tasks', 'activity', 'sleep', 'nutrition', 'habits')",
        )
        batch_op.create_check_constraint(op.f('ck_tasks_estimate_range'), 'estimated_minutes BETWEEN 1 AND 1440')

    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('token_version', sa.Integer(), server_default=sa.text('0'), nullable=False))



def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_column('token_version')

    with op.batch_alter_table('tasks', schema=None) as batch_op:
        batch_op.drop_constraint(op.f('ck_tasks_estimate_range'), type_='check')
        batch_op.drop_constraint(op.f('ck_tasks_category'), type_='check')
        batch_op.drop_column('category')
        batch_op.drop_column('estimated_minutes')
        batch_op.drop_column('due_time')

    with op.batch_alter_table('profiles', schema=None) as batch_op:
        batch_op.drop_constraint(op.f('ck_profiles_calorie_goal_range'), type_='check')
        batch_op.drop_constraint(op.f('ck_profiles_sleep_goal_range'), type_='check')
        batch_op.drop_index(batch_op.f('ix_profiles_username'))
        batch_op.drop_column('username')
        batch_op.drop_column('daily_calorie_goal')
        batch_op.drop_column('daily_sleep_goal_minutes')

    with op.batch_alter_table('sleep_logs', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_sleep_logs_user_id'))

    op.drop_table('sleep_logs')
    with op.batch_alter_table('meals', schema=None) as batch_op:
        batch_op.drop_index('ix_meals_user_day')

    op.drop_table('meals')
