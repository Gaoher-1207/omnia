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

    # Food-photo provider stays independent from the two OmniAI capabilities.
    ai_provider: Literal["rules", "anthropic"] = "rules"
    ai_api_key: str = ""
    ai_model: str = "claude-sonnet-5"
    ai_base_url: str = "https://api.anthropic.com"
    planner_ai_provider: Literal["rules", "anthropic", "ollama", "openrouter"] | None = None
    ai_timeout_seconds: float = Field(default=20.0, gt=0, le=120)
    ai_rate_limit_per_hour: int = Field(default=20, ge=1)
    openrouter_api_key: str = ""
    openrouter_primary_model: str = "nvidia/nemotron-3-ultra-550b-a55b:free"
    openrouter_fallback_model: str = "openrouter/free"

    # Ask Omnia (POST /ai/chat). Separate from AI_PROVIDER, which selects the
    # daily planner provider. "off" answers 503; nothing is invented.
    assistant_provider: Literal["off", "ollama", "openrouter"] | None = None
    assistant_base_url: str = "http://localhost:11434"
    assistant_model: str = "qwen3:8b"
    # A local model's first answer includes loading it into memory.
    assistant_timeout_seconds: float = Field(default=60.0, gt=0, le=300)
    assistant_context_tokens: int = Field(default=8192, ge=2048, le=131072)
    assistant_rate_limit_per_hour: int = Field(default=60, ge=1)

    # When unset, preserve the legacy independent chat/planning configuration.
    omnia_ai_provider: Literal["off", "ollama"] | None = None
    omnia_ai_model: str | None = None
    omnia_ai_base_url: str | None = None
    omnia_ai_timeout_seconds: float | None = Field(default=None, gt=0, le=120)
    omnia_ai_context_tokens: int | None = Field(default=None, ge=2048, le=131072)

    def ollama_options(self) -> dict:
        return {
            "base_url": self.omnia_ai_base_url or self.assistant_base_url,
            "model": self.omnia_ai_model or self.assistant_model,
            "timeout": self.omnia_ai_timeout_seconds or min(self.assistant_timeout_seconds, 120),
            "context_tokens": self.omnia_ai_context_tokens or self.assistant_context_tokens,
        }

    def openrouter_options(self, *, timeout: float | None = None) -> dict:
        return {
            "api_key": self.openrouter_api_key,
            "primary_model": self.openrouter_primary_model,
            "fallback_model": self.openrouter_fallback_model,
            "timeout": timeout or self.ai_timeout_seconds,
        }

    auth_rate_limit_per_minute: int = Field(default=10, ge=1)

    @model_validator(mode="after")
    def _check_production_safety(self) -> "Settings":
        if self.app_env == "production":
            if len(self.auth_secret) < 32:
                raise ValueError("AUTH_SECRET must be set to at least 32 characters in production")
            if self.database_url.startswith("sqlite"):
                raise ValueError("Use PostgreSQL (DATABASE_URL) in production, not SQLite")
        if (self.ai_provider == "anthropic" or self.planner_ai_provider == "anthropic") and not self.ai_api_key:
            raise ValueError("AI_API_KEY is required when an Anthropic subsystem is enabled")
        if (
            self.planner_ai_provider == "openrouter" or self.assistant_provider == "openrouter"
        ) and not self.openrouter_api_key:
            raise ValueError("OPENROUTER_API_KEY is required when a subsystem uses OpenRouter")
        return self

    @property
    def effective_planner_ai_provider(self) -> str:
        """Resolve the subsystem setting first, then the legacy shared setting."""
        if self.planner_ai_provider is not None:
            return self.planner_ai_provider
        if self.omnia_ai_provider is not None:
            return self.omnia_ai_provider
        return "rules"

    @property
    def effective_assistant_provider(self) -> str:
        if self.assistant_provider is not None:
            return self.assistant_provider
        return self.omnia_ai_provider or "off"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
