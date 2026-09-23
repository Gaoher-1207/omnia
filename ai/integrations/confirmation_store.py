"""Backend-owned persistence and one-time claim contract for proposals."""

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Protocol

from ..agent.models import ActionProposal, ConfirmedAction


class ProposalStoreStatus(str, Enum):
    STORED = "stored"
    CLAIMED = "claimed"
    NOT_CONNECTED = "not_connected"
    REJECTED = "rejected"


@dataclass(frozen=True)
class ProposalStoreResult:
    """Result from storing or atomically claiming an action proposal."""

    status: ProposalStoreStatus
    claim: ConfirmedAction | None = None


class ProposalStore(Protocol):
    def store(self, *, user_id: str, proposal: ActionProposal) -> ProposalStoreResult:
        """Persist original proposal with expiry and unique proposal/idempotency IDs."""

    def claim(
        self, *, user_id: str, proposal_id: str, confirmation_token: str, now: datetime
    ) -> ProposalStoreResult:
        """Atomically verify user, exact stored proposal, expiry, token, and one-time use.

        A successful claim returns the persisted action arguments plus a trusted
        receipt and idempotency key. The AI module cannot manufacture that claim.
        Django must implement this atomically in persistent storage.
        """


class PendingProposalStore:
    """No persistence: proposals cannot be confirmed or executed locally."""

    def store(self, *, user_id: str, proposal: ActionProposal) -> ProposalStoreResult:
        return ProposalStoreResult(ProposalStoreStatus.NOT_CONNECTED)

    def claim(self, *, user_id: str, proposal_id: str, confirmation_token: str, now: datetime) -> ProposalStoreResult:
        return ProposalStoreResult(ProposalStoreStatus.NOT_CONNECTED)
