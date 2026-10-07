"""Create trips with persistent ID uniqueness and validated integer money.

Revision ID: 0001_create_trips
Revises:
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0001_create_trips"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "trips",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("start", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end", sa.DateTime(timezone=True), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("payment", sa.String(), nullable=False),
        sa.Column("commission", sa.Integer(), nullable=False),
        sa.CheckConstraint("amount > 0", name="ck_trips_amount_positive"),
        sa.CheckConstraint("commission >= 0", name="ck_trips_commission_nonnegative"),
        sa.CheckConstraint("payment IN ('cash', 'card')", name="ck_trips_payment"),
        sa.CheckConstraint('"end" > start', name="ck_trips_end_after_start"),
        sa.CheckConstraint(
            "typeof(amount) = 'integer'", name="ck_trips_amount_integer"
        ),
        sa.CheckConstraint(
            "typeof(commission) = 'integer'", name="ck_trips_commission_integer"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_trips_start", "trips", ["start"])


def downgrade() -> None:
    op.drop_index("ix_trips_start", table_name="trips")
    op.drop_table("trips")
