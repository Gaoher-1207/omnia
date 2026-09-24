"""phase 3 social

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-24 15:39:53.079570

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0003'
down_revision: Union[str, Sequence[str], None] = '0002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('friendships',
    sa.Column('requester_id', sa.Uuid(), nullable=False),
    sa.Column('addressee_id', sa.Uuid(), nullable=False),
    sa.Column('status', sa.String(length=10), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("status IN ('pending', 'accepted')", name=op.f('ck_friendships_status')),
    sa.CheckConstraint('requester_id <> addressee_id', name=op.f('ck_friendships_not_self')),
    sa.ForeignKeyConstraint(['addressee_id'], ['users.id'], name=op.f('fk_friendships_addressee_id_users'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['requester_id'], ['users.id'], name=op.f('fk_friendships_requester_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_friendships')),
    sa.UniqueConstraint('requester_id', 'addressee_id', name='uq_friendships_pair')
    )
    with op.batch_alter_table('friendships', schema=None) as batch_op:
        batch_op.create_index('ix_friendships_addressee_status', ['addressee_id', 'status'], unique=False)
        batch_op.create_index(batch_op.f('ix_friendships_requester_id'), ['requester_id'], unique=False)

    op.create_table('social_groups',
    sa.Column('owner_id', sa.Uuid(), nullable=False),
    sa.Column('name', sa.String(length=60), nullable=False),
    sa.Column('description', sa.String(length=300), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['owner_id'], ['users.id'], name=op.f('fk_social_groups_owner_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_social_groups'))
    )
    with op.batch_alter_table('social_groups', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_social_groups_owner_id'), ['owner_id'], unique=False)

    op.create_table('challenges',
    sa.Column('group_id', sa.Uuid(), nullable=False),
    sa.Column('created_by', sa.Uuid(), nullable=False),
    sa.Column('title', sa.String(length=100), nullable=False),
    sa.Column('metric', sa.String(length=20), nullable=False),
    sa.Column('target', sa.Integer(), nullable=False),
    sa.Column('start_date', sa.Date(), nullable=False),
    sa.Column('end_date', sa.Date(), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("metric IN ('study_minutes', 'study_sessions', 'steps', 'tasks_completed', 'workouts')", name=op.f('ck_challenges_metric')),
    sa.CheckConstraint('end_date >= start_date', name=op.f('ck_challenges_dates_ordered')),
    sa.CheckConstraint('target > 0', name=op.f('ck_challenges_target_positive')),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], name=op.f('fk_challenges_created_by_users'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['group_id'], ['social_groups.id'], name=op.f('fk_challenges_group_id_social_groups'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_challenges'))
    )
    with op.batch_alter_table('challenges', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_challenges_group_id'), ['group_id'], unique=False)

    op.create_table('group_members',
    sa.Column('group_id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('role', sa.String(length=10), nullable=False),
    sa.Column('joined_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("role IN ('owner', 'member')", name=op.f('ck_group_members_role')),
    sa.ForeignKeyConstraint(['group_id'], ['social_groups.id'], name=op.f('fk_group_members_group_id_social_groups'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_group_members_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('group_id', 'user_id', name=op.f('pk_group_members'))
    )
    with op.batch_alter_table('group_members', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_group_members_user_id'), ['user_id'], unique=False)

    op.create_table('group_messages',
    sa.Column('group_id', sa.Uuid(), nullable=False),
    sa.Column('sender_id', sa.Uuid(), nullable=False),
    sa.Column('body', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['group_id'], ['social_groups.id'], name=op.f('fk_group_messages_group_id_social_groups'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['sender_id'], ['users.id'], name=op.f('fk_group_messages_sender_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_group_messages'))
    )
    with op.batch_alter_table('group_messages', schema=None) as batch_op:
        batch_op.create_index('ix_group_messages_group_created', ['group_id', 'created_at'], unique=False)
        batch_op.create_index(batch_op.f('ix_group_messages_sender_id'), ['sender_id'], unique=False)

    op.create_table('posts',
    sa.Column('author_id', sa.Uuid(), nullable=False),
    sa.Column('kind', sa.String(length=12), nullable=False),
    sa.Column('body', sa.String(length=500), nullable=True),
    sa.Column('payload', sa.JSON(), nullable=False),
    sa.Column('visibility', sa.String(length=10), nullable=False),
    sa.Column('group_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.CheckConstraint("kind IN ('progress', 'achievement', 'text')", name=op.f('ck_posts_kind')),
    sa.CheckConstraint("visibility IN ('friends', 'group')", name=op.f('ck_posts_visibility')),
    sa.ForeignKeyConstraint(['author_id'], ['users.id'], name=op.f('fk_posts_author_id_users'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['group_id'], ['social_groups.id'], name=op.f('fk_posts_group_id_social_groups'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_posts'))
    )
    with op.batch_alter_table('posts', schema=None) as batch_op:
        batch_op.create_index('ix_posts_author_created', ['author_id', 'created_at'], unique=False)
        batch_op.create_index('ix_posts_group_created', ['group_id', 'created_at'], unique=False)

    op.create_table('challenge_participants',
    sa.Column('challenge_id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('joined_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['challenge_id'], ['challenges.id'], name=op.f('fk_challenge_participants_challenge_id_challenges'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_challenge_participants_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('challenge_id', 'user_id', name=op.f('pk_challenge_participants'))
    )
    with op.batch_alter_table('challenge_participants', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_challenge_participants_user_id'), ['user_id'], unique=False)

    op.create_table('post_likes',
    sa.Column('post_id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['post_id'], ['posts.id'], name=op.f('fk_post_likes_post_id_posts'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_post_likes_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('post_id', 'user_id', name=op.f('pk_post_likes'))
    )
    with op.batch_alter_table('post_likes', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_post_likes_user_id'), ['user_id'], unique=False)



def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('post_likes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_post_likes_user_id'))

    op.drop_table('post_likes')
    with op.batch_alter_table('challenge_participants', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_challenge_participants_user_id'))

    op.drop_table('challenge_participants')
    with op.batch_alter_table('posts', schema=None) as batch_op:
        batch_op.drop_index('ix_posts_group_created')
        batch_op.drop_index('ix_posts_author_created')

    op.drop_table('posts')
    with op.batch_alter_table('group_messages', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_group_messages_sender_id'))
        batch_op.drop_index('ix_group_messages_group_created')

    op.drop_table('group_messages')
    with op.batch_alter_table('group_members', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_group_members_user_id'))

    op.drop_table('group_members')
    with op.batch_alter_table('challenges', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_challenges_group_id'))

    op.drop_table('challenges')
    with op.batch_alter_table('social_groups', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_social_groups_owner_id'))

    op.drop_table('social_groups')
    with op.batch_alter_table('friendships', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_friendships_requester_id'))
        batch_op.drop_index('ix_friendships_addressee_status')

    op.drop_table('friendships')
