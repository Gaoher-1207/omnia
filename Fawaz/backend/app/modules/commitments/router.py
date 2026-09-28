import uuid
from datetime import date

from fastapi import APIRouter, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.time import local_today
from app.modules.commitments import service
from app.modules.commitments.schemas import AvailabilityOut, CommitmentInput, CommitmentOut

router = APIRouter(prefix="/commitments", tags=["commitments"])


@router.get("", response_model=list[CommitmentOut])
def list_commitments(user: CurrentUser, db: DbSession):
    return service.list_owned(db, user.id)


@router.get("/availability", response_model=AvailabilityOut)
def get_availability(user: CurrentUser, db: DbSession, day: date | None = Query(default=None)):
    selected = day or local_today(user.profile.timezone)
    start, end = user.profile.planning_start_minutes, user.profile.planning_end_minutes
    rows, busy, free = service.availability(db, user.id, selected, start, end)
    return AvailabilityOut(
        day=selected,
        planning_start_minutes=start,
        planning_end_minutes=end,
        commitments=rows,
        busy_intervals=busy,
        free_intervals=free,
    )


@router.post("", response_model=CommitmentOut, status_code=status.HTTP_201_CREATED)
def create_commitment(body: CommitmentInput, user: CurrentUser, db: DbSession):
    return service.save(db, user.id, body)


@router.put("/{commitment_id}", response_model=CommitmentOut)
def update_commitment(commitment_id: uuid.UUID, body: CommitmentInput, user: CurrentUser, db: DbSession):
    return service.save(db, user.id, body, commitment_id)


@router.delete("/{commitment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_commitment(commitment_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete(db, user.id, commitment_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
