import threading
from datetime import datetime, timezone
from typing import Protocol

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

SCHEMA = """
CREATE TABLE IF NOT EXISTS orders (
    id         BIGSERIAL PRIMARY KEY,
    item       TEXT        NOT NULL,
    quantity   INTEGER     NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


class OrderRepository(Protocol):
    def init_schema(self) -> None: ...
    def close(self) -> None: ...
    def ping(self) -> bool: ...
    def list_orders(self, limit: int) -> list[dict]: ...
    def create_order(self, item: str, quantity: int) -> dict: ...


class PostgresRepository:
    def __init__(self, conninfo: str) -> None:
        self._pool = ConnectionPool(
            conninfo,
            min_size=1,
            max_size=5,
            open=False,
            timeout=5,
            kwargs={"row_factory": dict_row},
        )

    def init_schema(self) -> None:
        # Idempotent bootstrap instead of a migration tool: fine for one table.
        # Waiting up to 60s absorbs the normal case of Postgres starting after the API.
        self._pool.open(wait=True, timeout=60)
        with self._pool.connection() as conn:
            conn.execute(SCHEMA)

    def close(self) -> None:
        self._pool.close()

    def ping(self) -> bool:
        try:
            with self._pool.connection(timeout=2) as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:
            return False

    def list_orders(self, limit: int) -> list[dict]:
        with self._pool.connection() as conn:
            return conn.execute(
                "SELECT id, item, quantity, created_at FROM orders ORDER BY id DESC LIMIT %s",
                (limit,),
            ).fetchall()

    def create_order(self, item: str, quantity: int) -> dict:
        with self._pool.connection() as conn:
            return conn.execute(
                "INSERT INTO orders (item, quantity) VALUES (%s, %s) "
                "RETURNING id, item, quantity, created_at",
                (item, quantity),
            ).fetchone()


class InMemoryRepository:
    """Used by unit tests so CI needs no database."""

    def __init__(self) -> None:
        self._rows: list[dict] = []
        self._lock = threading.Lock()

    def init_schema(self) -> None:
        pass

    def close(self) -> None:
        pass

    def ping(self) -> bool:
        return True

    def list_orders(self, limit: int) -> list[dict]:
        with self._lock:
            return list(reversed(self._rows))[:limit]

    def create_order(self, item: str, quantity: int) -> dict:
        with self._lock:
            row = {
                "id": len(self._rows) + 1,
                "item": item,
                "quantity": quantity,
                "created_at": datetime.now(timezone.utc),
            }
            self._rows.append(row)
            return row
