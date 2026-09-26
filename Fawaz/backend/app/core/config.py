from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration, read from environment variables (or backend/.env).

    Only variable names belong in docs; real values stay in protected secrets.
    """

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "INFO"

    database_url: str = "sqlite:///./omnia.db"

    auth_secret: str = ""
    access_token_expire_minutes: int = Field(default=720, ge=5, le=60 * 24 * 30)
    password_hash_n: int = Field(default=2**15, ge=2**10)

    cors_origins: str = "http://localhost:5173"
    # Public URL of the API (e.g. https://api.omnia.app). Used to build calendar links behind proxies.
    public_base_url: str = ""
    max_request_bytes: int = Field(default=8 * 1024 * 1024, ge=1024)

    ai_provider: Literal["rules", "anthropic"] = "rules"
    ai_api_key: str = ""
    ai_model: str = "claude-sonnet-5"
    ai_base_url: str = "https://api.anthropic.com"
    ai_timeout_seconds: float = Field(default=20.0, gt=0, le=120)
    ai_rate_limit_per_hour: int = Field(default=20, ge=1)

    # Ask Omnia (POST /ai/chat). Separate from AI_PROVIDER so the daily plan and
    # photo estimates are unaffected. "off" answers 503; nothing is invented.
    assistant_provider: Literal["off", "ollama"] = "off"
    assistant_base_url: str = "http://localhost:11434"
    assistant_model: str = "qwen3:8b"
    # A local model's first answer includes loading it into memory.
    assistant_timeout_seconds: float = Field(default=60.0, gt=0, le=300)
    assistant_context_tokens: int = Field(default=8192, ge=2048, le=131072)
    assistant_rate_limit_per_hour: int = Field(default=60, ge=1)

    auth_rate_limit_per_minute: int = Field(default=10, ge=1)

    @model_validator(mode="after")
    def _check_production_safety(self) -> "Settings":
        if self.app_env == "production":
            if len(self.auth_secret) < 32:
                raise ValueError("AUTH_SECRET must be set to at least 32 characters in production")
            if self.database_url.startswith("sqlite"):
                raise ValueError("Use PostgreSQL (DATABASE_URL) in production, not SQLite")
        if self.ai_provider == "anthropic" and not self.ai_api_key:
            raise ValueError("AI_API_KEY is required when AI_PROVIDER=anthropic")
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
