from fastapi import APIRouter

from app.common.deps import CurrentUser, DbSession
from app.modules.dashboard import service
from app.modules.dashboard.schemas import DashboardOut

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("", response_model=DashboardOut, summary="Everything the Today screen needs in one call")
def get_dashboard(user: CurrentUser, db: DbSession):
    return service.dashboard(db, user)
