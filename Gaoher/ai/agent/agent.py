"""Request-scoped assistant orchestration with explicit trust boundaries."""

from dataclasses import replace
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from typing import Mapping

from .actions import ACTION_REGISTRY, ActionExecutor
from .model_adapter import (
    ModelAdapter, ModelCallOptions, ModelIntegrationPending, ModelPayloadTooLarge,
    ModelOutputTooLarge, ModelRequestCancelled, ProviderFailure, ProviderTimeout,
    ProviderUnavailable, PendingModelAdapter, StructuredOutputFailure, call_structured,
)
from .models import (
    ActionProposal, AgentError, AgentRequest, AgentResponse, ErrorCategory,
    ExecutorResult, ExecutorStatus, thaw_json,
)
from .routing import RequestRouter
from .validation import InvalidContext, InvalidModelOutput, validate_assistant_result
from ..context.context_manager import ContextManager
from ..integrations.context_provider import ContextProvider, ContextUnavailable, EmptyContextProvider
from ..integrations.confirmation_store import (
    PendingProposalStore, ProposalStore, ProposalStoreResult, ProposalStoreStatus,
)
from ..context.context_manager import AuthorizedContext, SelectedContext
from ..planning.service import PlanningService
from ..planning.models import PlanningRequest
from ..recommendations.service import RecommendationService
from ..recommendations.models import RecommendationRequest
from ..progress.service import ProgressService
from ..progress.models import ProgressRequest
from ..goals_streaks.service import GoalsStreaksService
from ..goals_streaks.models import GoalsStreaksRequest
from ..coaching.service import CoachingService
from ..coaching.models import CoachingRequest, CoachingRequestType
from ..food.nutrition_analysis import NutritionAnalysisService
from ..food.calorie_estimation import NutritionRequest
from ..memory.service import ConversationMemoryService
from ..memory.models import MemorySelectionRequest
from ..memory.validation import InvalidMemory


class OmniaAgent:
    """Coordinator with no per-user state; all identity and context is per call."""

    def __init__(
        self,
        model: ModelAdapter | None = None,
        context_provider: ContextProvider | None = None,
        action_executor: ActionExecutor | None = None,
        context_manager: ContextManager | None = None,
        proposal_store: ProposalStore | None = None,
        *,
        proposal_ttl_seconds: int = 300,
        planning_service: PlanningService | None = None,
        recommendation_service: RecommendationService | None = None,
        progress_service: ProgressService | None = None,
        goals_streaks_service: GoalsStreaksService | None = None,
        coaching_service: CoachingService | None = None,
        nutrition_service: NutritionAnalysisService | None = None,
        memory_service: ConversationMemoryService | None = None,
    ) -> None:
        if proposal_ttl_seconds <= 0:
            raise ValueError("proposal_ttl_seconds must be positive")
        self._model = model if model is not None else PendingModelAdapter()
        self._context_provider = context_provider if context_provider is not None else EmptyContextProvider()
        self._action_executor = action_executor
        self._context_manager = context_manager if context_manager is not None else ContextManager()
        self._proposal_store = proposal_store if proposal_store is not None else PendingProposalStore()
        self._proposal_ttl_seconds = proposal_ttl_seconds
        self._router = RequestRouter(self._model)
        self._planning = planning_service or PlanningService(self._model)
        self._recommendations = recommendation_service or RecommendationService(self._model)
        self._progress = progress_service or ProgressService(self._model)
        self._goals_streaks = goals_streaks_service or GoalsStreaksService(self._model)
        self._coaching = coaching_service or CoachingService(self._model)
        self._nutrition = nutrition_service or NutritionAnalysisService(self._model)
        self._memory = memory_service or ConversationMemoryService()

    def chat(
        self, request: AgentRequest, *, model_options: ModelCallOptions | None = None,
        memory_request: MemorySelectionRequest | None = None,
    ) -> AgentResponse:
        """Handle one authenticated request and return safe, categorized errors."""
        correlation_id = str(uuid4())
        if request.proposal_id is not None:
            return replace(self._confirm(request, correlation_id), correlation_id=correlation_id)

        try:
            route = self._router.route(request.message, options=model_options)
            category, policy = route["category"], route["policy"]
            intent = route["intent"]
            if intent == "clarification":
                return AgentResponse("What kind of help are you looking for?", kind="clarification", needs_clarification=True,
                                     intent=intent, correlation_id=correlation_id, status="clarification")
            context: Mapping[str, object] = {}
            selected = SelectedContext(request.user_id, self._context_manager.select({}, category="general", policy="general"))
            if category != "general" and policy != "other":
                try:
                    available = self._context_provider.get_context(user_id=request.user_id, policy=policy)
                except Exception as exc:
                    raise ContextUnavailable("context lookup failed") from exc
                selected = self._context_manager.select_for_user(
                    AuthorizedContext(request.user_id, available), user_id=request.user_id,
                    category=category, policy=policy,
                )
                context = selected.data

            selected_memory = None
            memory_payload = None
            if route["use_memory"] and memory_request is not None:
                if memory_request.user_id != request.user_id or memory_request.query.strip() != request.message.strip():
                    raise InvalidMemory("memory request does not match the current user request")
                selected_memory = self._memory.select(memory_request)
                memory_payload = selected_memory.for_model(request.user_id)

            # Selected memory is independently filtered and then passed as a
            # single bounded continuity domain; it never broadens backend access.
            augmented = thaw_json(context)
            if memory_payload is not None and intent not in {"nutrition", "action"}:
                augmented["conversation_memory"] = memory_payload
            selected_for_module = selected
            if augmented != thaw_json(context):
                from ..agent.models import freeze_json
                selected_for_module = SelectedContext(request.user_id, freeze_json(augmented))

            if intent == "planning":
                result = self._planning.create_plan(PlanningRequest(request.message, augmented))
                return self._module_response(result, intent, correlation_id, self._plan_message(result), result.status.value,
                                             result.confidence if hasattr(result, "confidence") else None,
                                             "; ".join(result.uncertainties) if result.uncertainties else None)
            if intent == "recommendation":
                result = self._recommendations.recommend(RecommendationRequest(request.user_id, request.message, selected_for_module))
                return self._module_response(result, intent, correlation_id, self._recommendation_message(result), result.status.value,
                                             result.confidence, result.uncertainty)
            if intent == "progress":
                result = self._progress.analyze(ProgressRequest(request.user_id, request.message, selected_for_module))
                return self._module_response(result, intent, correlation_id, result.summary.fact if result.summary else result.clarification_question,
                                             result.status.value, result.confidence, result.uncertainty,
                                             clarification=result.clarification_question)
            if intent == "goals_streaks":
                result = self._goals_streaks.analyze(GoalsStreaksRequest(request.user_id, request.message, selected_for_module))
                msg = result.goal_summary or result.streak_summary or result.clarification_question
                return self._module_response(result, intent, correlation_id, msg, result.status.value, result.confidence,
                                             result.uncertainty, clarification=result.clarification_question)
            if intent == "nutrition":
                result = self._nutrition.analyze(NutritionRequest(request.message))
                totals = result.totals
                msg = result.wording if totals is None else result.wording + " " + ", ".join(f"{k}: {v}" for k, v in totals.items())
                return self._module_response(result, intent, correlation_id, msg,
                                             result.status.value, result.confidence.value,
                                             None if result.status.value == "estimated" else "Food or portion details are uncertain.",
                                             clarification=result.clarification_question)
            if intent == "coaching":
                history = []
                if memory_payload:
                    history.extend(memory_payload["messages"])
                    if memory_payload["summary"]:
                        history.append({"summary": memory_payload["summary"]})
                    if memory_payload["memories"]:
                        history.append({"selected_memories": memory_payload["memories"]})
                request_type = CoachingRequestType.ACTION if category == "action" else CoachingRequestType.COACHING
                result = self._coaching.coach(CoachingRequest(request.user_id, request.message, selected_for_module,
                                                               request_type, tuple(history)))
                return self._module_response(result, intent, correlation_id, result.response, result.status.value,
                                             result.confidence, result.uncertainty,
                                             clarification=result.questions[0].question if result.questions else None)

            payload = {
                "message": request.message,
                "category": category,
                "policy": policy,
                "context": augmented,
                "conversation_memory": memory_payload,
                "allowed_actions": sorted(
                    name for name, definition in ACTION_REGISTRY.items()
                    if category == "action" and definition.allowed_context_policy == policy
                ),
            }
            raw = call_structured(self._model, "respond", payload, options=model_options)
            allowed_actions = frozenset(payload["allowed_actions"])
            result = validate_assistant_result(raw, allowed_action_names=allowed_actions)
        except ModelIntegrationPending:
            return self._error("Assistant model integration is not configured yet.", ErrorCategory.MODEL_PENDING, correlation_id)
        except ProviderTimeout:
            return self._error("The assistant request timed out. Please try again.", ErrorCategory.PROVIDER_TIMEOUT, correlation_id)
        except ProviderUnavailable:
            return self._error("The assistant is temporarily unavailable. Please try again.", ErrorCategory.PROVIDER_UNAVAILABLE, correlation_id)
        except ModelPayloadTooLarge:
            return self._error("That request is too large to process. Please shorten it.", ErrorCategory.PROVIDER_FAILURE, correlation_id)
        except ModelOutputTooLarge:
            return self._error("The assistant returned an unusable response. Please try again.", ErrorCategory.INVALID_MODEL_OUTPUT, correlation_id)
        except ModelRequestCancelled:
            return self._error("The request was cancelled.", ErrorCategory.MODEL_CANCELLED, correlation_id)
        except StructuredOutputFailure:
            return self._error("The assistant returned an unusable response. Please try again.", ErrorCategory.INVALID_MODEL_OUTPUT, correlation_id)
        except ProviderFailure:
            return self._error("The assistant is temporarily unavailable. Please try again.", ErrorCategory.PROVIDER_FAILURE, correlation_id)
        except InvalidContext:
            return self._error("I couldn't safely use the available OMNIA context.", ErrorCategory.INVALID_CONTEXT, correlation_id)
        except ContextUnavailable:
            return self._error("OMNIA context is temporarily unavailable.", ErrorCategory.CONTEXT_UNAVAILABLE, correlation_id)
        except InvalidModelOutput:
            return self._error("I couldn't safely process that response. Please try again.", ErrorCategory.INVALID_MODEL_OUTPUT, correlation_id)
        except Exception:
            return self._error("I couldn't safely process that request. Please try again.", ErrorCategory.INTERNAL_FAILURE, correlation_id)

        if result["kind"] == "clarification":
            return AgentResponse(result["message"], kind="clarification", needs_clarification=True,
                                 intent=intent, correlation_id=correlation_id, status="clarification")
        if result["kind"] == "action":
            definition = ACTION_REGISTRY[result["action"]["name"]]
            proposal = ActionProposal(
                name=result["action"]["name"],
                arguments=result["action"]["arguments"],
                proposal_id=str(uuid4()),
                expires_at=datetime.now(timezone.utc) + timedelta(seconds=self._proposal_ttl_seconds),
                requires_confirmation=definition.requires_confirmation,
            )
            try:
                saved = self._proposal_store.store(user_id=request.user_id, proposal=proposal)
            except Exception:
                return self._error("I couldn't safely prepare that action.", ErrorCategory.INTERNAL_FAILURE, correlation_id)
            if saved.status is not ProposalStoreStatus.STORED:
                return self._error(
                    "Action confirmation is unavailable; no action was performed.",
                    ErrorCategory.ACTION_NOT_CONNECTED if saved.status is ProposalStoreStatus.NOT_CONNECTED else ErrorCategory.INTERNAL_FAILURE,
                    correlation_id,
                )
            return AgentResponse(
                result["message"], kind="action", action=proposal,
                needs_confirmation=proposal.requires_confirmation,
                intent=intent, correlation_id=correlation_id, status="proposal",
            )
        return AgentResponse(result["message"], intent=intent, correlation_id=correlation_id, status="ready")

    @staticmethod
    def _module_response(result, intent, correlation_id, message, status, confidence, uncertainty, clarification=None):
        if not isinstance(message, str) or not message.strip():
            message = "I need a little more information to help with that."
        needs_clarification = status in {"clarification", "insufficient_context", "unclear", "conflict"}
        return AgentResponse(message=message, kind="module", needs_clarification=needs_clarification,
                             intent=intent, structured_result=result, confidence=confidence,
                             uncertainty=uncertainty, correlation_id=correlation_id, status=status)

    @staticmethod
    def _plan_message(result):
        if result.clarification_question:
            return result.clarification_question
        if not result.sessions:
            return "I couldn't build a useful plan from the available details."
        return "Proposed plan: " + "; ".join(f"{s.title} ({s.duration_minutes} min)" for s in result.sessions)

    @staticmethod
    def _recommendation_message(result):
        if result.clarification_question:
            return result.clarification_question
        return " ".join(item.recommendation for item in result.recommendations) or "I need more context to make a useful recommendation."

    def _confirm(self, request: AgentRequest, correlation_id: str) -> AgentResponse:
        if self._action_executor is None:
            return self._error(
                "Action integration is not connected; no action was performed.",
                ErrorCategory.ACTION_NOT_CONNECTED, correlation_id,
            )
        try:
            claim_result = self._proposal_store.claim(
                user_id=request.user_id,
                proposal_id=request.proposal_id or "",
                confirmation_token=request.confirmation_token or "",
                now=datetime.now(timezone.utc),
            )
        except Exception:
            return self._error("Confirmation could not be verified.", ErrorCategory.CONFIRMATION_REJECTED, correlation_id)
        if not isinstance(claim_result, ProposalStoreResult):
            return self._error("Confirmation could not be verified.", ErrorCategory.CONFIRMATION_REJECTED, correlation_id)
        claim = claim_result.claim
        if claim_result.status is not ProposalStoreStatus.CLAIMED or claim is None:
            category = ErrorCategory.ACTION_NOT_CONNECTED if claim_result.status is ProposalStoreStatus.NOT_CONNECTED else ErrorCategory.CONFIRMATION_REJECTED
            return self._error("Confirmation is invalid or expired; no action was performed.", category, correlation_id)
        if (
            claim.user_id != request.user_id
            or claim.proposal.proposal_id != request.proposal_id
            or claim.proposal.expires_at <= datetime.now(timezone.utc)
            or not claim.confirmation_receipt
            or not claim.idempotency_key
        ):
            return self._error("Confirmation is invalid or expired; no action was performed.", ErrorCategory.CONFIRMATION_REJECTED, correlation_id)
        try:
            validate_assistant_result({
                "kind": "action",
                "message": "Confirmed action.",
                "action": {"name": claim.proposal.name, "arguments": thaw_json(claim.proposal.arguments)},
            }, allowed_action_names=frozenset({claim.proposal.name}))
            definition = ACTION_REGISTRY[claim.proposal.name]
            if not definition.requires_confirmation or not claim.proposal.requires_confirmation:
                return self._error("Confirmation is invalid or expired; no action was performed.", ErrorCategory.CONFIRMATION_REJECTED, correlation_id)
        except Exception:
            return self._error("Confirmation is invalid or expired; no action was performed.", ErrorCategory.CONFIRMATION_REJECTED, correlation_id)
        try:
            result = self._action_executor.execute(action=claim)
        except Exception:
            # The backend must reconcile this proposal by idempotency key before retry.
            return self._error("Action status is unclear. Check its status before trying again.", ErrorCategory.ACTION_AMBIGUOUS, correlation_id, status=ExecutorStatus.AMBIGUOUS)
        if not isinstance(result, ExecutorResult):
            return self._error("Action status is unclear. Check its status before trying again.", ErrorCategory.ACTION_AMBIGUOUS, correlation_id, status=ExecutorStatus.AMBIGUOUS)
        if result.status is ExecutorStatus.SUCCESS:
            return AgentResponse("The action completed.", action_status=ExecutorStatus.SUCCESS)
        if result.status is ExecutorStatus.DENIED:
            return self._error("You are not able to perform that action.", ErrorCategory.ACTION_DENIED, correlation_id, status=result.status)
        if result.status is ExecutorStatus.NOT_CONNECTED:
            return self._error("Action integration is not connected; no action was performed.", ErrorCategory.ACTION_NOT_CONNECTED, correlation_id, status=result.status)
        if result.status is ExecutorStatus.AMBIGUOUS:
            return self._error("Action status is unclear. Check its status before trying again.", ErrorCategory.ACTION_AMBIGUOUS, correlation_id, status=result.status)
        return self._error("The action could not be completed. Please try again later.", ErrorCategory.ACTION_FAILED, correlation_id, status=ExecutorStatus.FAILED)

    @staticmethod
    def _error(
        message: str,
        category: ErrorCategory,
        correlation_id: str,
        *,
        status: ExecutorStatus | None = None,
    ) -> AgentResponse:
        return AgentResponse(
            message=message,
            action_status=status,
            error=AgentError(category=category, correlation_id=correlation_id),
            correlation_id=correlation_id,
            status="error",
        )
