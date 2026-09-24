from fastapi import APIRouter, Query

from app.common.deps import CurrentUser, DbSession
from app.modules.progress import service
from app.modules.progress.achievements import AchievementOut
from app.modules.progress.schemas import ProgressOut

router = APIRouter(prefix="/progress", tags=["progress"])


@router.get("", response_model=ProgressOut, summary="Streaks and recent daily history")
def get_progress(user: CurrentUser, db: DbSession, days: int = Query(default=14, ge=1, le=90)):
    return service.progress(db, user, history_days=days)


achievements_router = APIRouter(prefix="/achievements", tags=["progress"])


@achievements_router.get("", response_model=list[AchievementOut], summary="My achievements and progress to each")
def get_achievements(user: CurrentUser, db: DbSession):
    return service.achievements(db, user)
