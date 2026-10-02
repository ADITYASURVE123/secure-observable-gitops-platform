import os
from dataclasses import dataclass

from psycopg.conninfo import make_conninfo


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    version: str
    environment: str

    @classmethod
    def from_env(cls) -> "Settings":
        # All values come from the environment (ConfigMap + Secret in Kubernetes).
        # Nothing sensitive has a default.
        return cls(
            db_host=os.getenv("DB_HOST", "localhost"),
            db_port=int(os.getenv("DB_PORT", "5432")),
            db_name=os.getenv("DB_NAME", "orders"),
            db_user=os.getenv("DB_USER", "orders"),
            db_password=os.getenv("DB_PASSWORD", ""),
            version=os.getenv("APP_VERSION", "dev"),
            environment=os.getenv("APP_ENV", "local"),
        )

    def conninfo(self) -> str:
        # make_conninfo quotes the password correctly, unlike hand-built URLs.
        return make_conninfo(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=self.db_password,
            connect_timeout=5,
        )
