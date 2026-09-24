"""Backend-owned context retrieval boundary."""

from typing import Any, Mapping, Protocol


class ContextUnavailable(RuntimeError):
    """Raised when the backend cannot safely fetch request-scoped context."""


class ContextProvider(Protocol):
    def get_context(self, *, user_id: str, policy: str) -> Mapping[str, Any]:
        """Fetch only policy-approved data authorized for this authenticated user.

        Django must map policy IDs to fixed queries/fields; it must not accept
        model-selected field names or arbitrary database paths.
        """


class EmptyContextProvider:
    """Default before Django integration; returns no fabricated user data."""

    def get_context(self, *, user_id: str, policy: str) -> Mapping[str, Any]:
        return {}
