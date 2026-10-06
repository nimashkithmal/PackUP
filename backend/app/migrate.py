"""Tiny additive migrations: create_all() makes new tables but never adds columns."""

from sqlalchemy import Engine, inspect, text

from app.db import Base

ADDED_COLUMNS = {
    "generated_lists": {"rating": "INTEGER NULL"},
}

ADDED_INDEXES = {
    "list_item_events": ["list_id", "item_id"],
}


def migrate(engine: Engine) -> None:
    Base.metadata.create_all(bind=engine)
    insp = inspect(engine)
    with engine.begin() as conn:
        for table, columns in ADDED_COLUMNS.items():
            existing = {c["name"] for c in insp.get_columns(table)}
            for name, ddl in columns.items():
                if name not in existing:
                    conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
        for table, columns in ADDED_INDEXES.items():
            indexed = {tuple(ix["column_names"]) for ix in insp.get_indexes(table)}
            # MySQL creates an index for every foreign key on its own.
            indexed |= {tuple(fk["constrained_columns"]) for fk in insp.get_foreign_keys(table)}
            for col in columns:
                if (col,) not in indexed:
                    conn.execute(text(f"CREATE INDEX ix_{table}_{col} ON {table} ({col})"))
