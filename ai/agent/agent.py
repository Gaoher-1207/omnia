"""Request-scoped assistant orchestration with explicit trust boundaries."""

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

    def chat(
        self, request: AgentRequest, *, model_options: ModelCallOptions | None = None
    ) -> AgentResponse:
        """Handle one authenticated request and return safe, categorized errors."""
        correlation_id = str(uuid4())
        if request.proposal_id is not None:
            return self._confirm(request, correlation_id)

        try:
            route = self._router.route(request.message, options=model_options)
            category, policy = route["category"], route["policy"]
            context: Mapping[str, object] = {}
            if policy != "general" and policy != "other":
                try:
                    available = self._context_provider.get_context(user_id=request.user_id, policy=policy)
                except Exception as exc:
                    raise ContextUnavailable("context lookup failed") from exc
                context = self._context_manager.select(available, category=category, policy=policy)
            payload = {
                "message": request.message,
                "category": category,
                "policy": policy,
                "context": thaw_json(context),
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
            return AgentResponse(result["message"], kind="clarification", needs_clarification=True)
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
            )
        return AgentResponse(result["message"])

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
        )
