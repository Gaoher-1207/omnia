"""Scenario and sanitized evaluation report contracts."""

from dataclasses import dataclass
from typing import Any, Mapping

from Gaoher.ai.memory.models import MemorySelectionRequest


@dataclass(frozen=True)
class EvaluationScenario:
    scenario_id: str
    category: str
    user_id: str
    user_request: str
    authorized_context: Mapping[str, Any]
    expected_route: Mapping[str, Any]
    expected_context_policy: str | None
    expected_memory_usage: bool
    expected_result_status: str
    expected_module: str
    forbidden_behavior: tuple[str, ...] = ()
    notes: str = ""
    memory: MemorySelectionRequest | None = None
    model_behavior: str = "normal"
    module_output: Any | None = None


@dataclass(frozen=True)
class ScenarioResult:
    scenario_id: str
    category: str
    passed: bool
    failure_reason: str | None
    execution_time_ms: float


@dataclass(frozen=True)
class EvaluationReport:
    total_scenarios: int
    passed: int
    failed: int
    skipped: int
    results: tuple[ScenarioResult, ...]
