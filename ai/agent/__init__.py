"""Request-scoped OMNIA assistant package.

Exports are resolved lazily to avoid cycles between models, integrations, and
context policies during package initialization.
"""

__all__ = [
    "ActionProposal", "AgentRequest", "AgentResponse", "ConfirmedAction",
    "ExecutorResult", "ExecutorStatus", "OmniaAgent",
]


def __getattr__(name):
    if name == "OmniaAgent":
        from .agent import OmniaAgent
        return OmniaAgent
    if name in {"ActionProposal", "AgentRequest", "AgentResponse", "ConfirmedAction", "ExecutorResult", "ExecutorStatus"}:
        from . import models
        return getattr(models, name)
    raise AttributeError(name)
