from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.common.deps import DbSession
from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.core.logging import RequestContextMiddleware, configure_logging
from app.modules.activity.router import router as activity_router
from app.modules.ai.router import router as ai_router
from app.modules.auth.router import router as auth_router
from app.modules.dashboard.router import router as dashboard_router
from app.modules.integrations.router import router as integrations_router
from app.modules.nutrition.router import router as nutrition_router
from app.modules.progress.router import achievements_router
from app.modules.progress.router import router as progress_router
from app.modules.sleep.router import router as sleep_router
from app.modules.social.router import router as social_router
from app.modules.study.router import router as study_router
from app.modules.tasks.router import router as tasks_router
from app.modules.users.router import router as profile_router

health_router = APIRouter(prefix="/health", tags=["health"])


@health_router.get("", summary="Liveness: the process is up")
def health():
    return {"status": "ok"}


@health_router.get("/ready", summary="Readiness: the database answers")
def ready(db: DbSession):
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "ok"}


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)
    app = FastAPI(
        title="OMNIA API",
        version="0.2.0",
        description="Backend for OMNIA, the AI-powered personal life platform.",
        docs_url=None if settings.is_production else "/api/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/api/openapi.json",
    )
    app.add_middleware(
        RequestContextMiddleware, max_body_bytes=settings.max_request_bytes, production=settings.is_production
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        # `flutter run -d chrome` serves from a random localhost port; allow any port in development only.
        allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?" if settings.app_env == "development" else None,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
        expose_headers=["X-Request-ID", "Retry-After"],
    )
    register_error_handlers(app)

    api = APIRouter(prefix="/api")
    for router in (
        health_router,
        auth_router,
        profile_router,
        dashboard_router,
        tasks_router,
        study_router,
        activity_router,
        progress_router,
        achievements_router,
        sleep_router,
        nutrition_router,
        social_router,
        integrations_router,
        ai_router,
    ):
        api.include_router(router)
    app.include_router(api)
    return app


app = create_app()
