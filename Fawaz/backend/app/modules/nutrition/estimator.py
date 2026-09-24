"""Food photo → nutrition estimate, behind a small interface.

Only the image and the user's optional note are sent to the provider: no name,
email, goals or history. The image is never stored by OMNIA.
"""

import json
import logging
from typing import Protocol

import httpx
from pydantic import BaseModel, Field, ValidationError

from app.core.config import get_settings
from app.core.errors import AppError
from app.modules.nutrition.schemas import EstimatedItem, NutritionTotals, PhotoEstimate, PhotoEstimateIn

logger = logging.getLogger("omnia.nutrition")


class EstimatorUnavailableError(AppError):
    status_code = 503
    code = "service_unavailable"


class EstimatorFailedError(AppError):
    status_code = 502
    code = "upstream_error"


class FoodPhotoEstimator(Protocol):
    def estimate(self, request: PhotoEstimateIn) -> PhotoEstimate: ...


class NotConfiguredEstimator:
    def estimate(self, request: PhotoEstimateIn) -> PhotoEstimate:
        raise EstimatorUnavailableError(
            "Food photo analysis isn't set up on this server yet. You can still log meals by hand."
        )


PROMPT = """Identify the foods in this photo and estimate nutrition for the portion shown.
Reply with only a JSON object, no prose, in this shape:
{"items": [{"name": str, "portion": str, "calories": int, "protein_g": int, "carbs_g": int, "fat_g": int}],
 "confidence": "low" | "medium" | "high",
 "suggested_description": str}
If the photo shows no food, reply {"items": [], "confidence": "low", "suggested_description": "No food found"}.
Don't give medical or dietary advice."""


class _ProviderReply(BaseModel):
    items: list[EstimatedItem] = Field(max_length=12)
    confidence: str
    suggested_description: str = Field(max_length=200)


class AnthropicFoodEstimator:
    def __init__(self, *, api_key: str, model: str, base_url: str, timeout: float, client: httpx.Client | None = None):
        self._api_key = api_key
        self._model = model
        self._url = base_url.rstrip("/") + "/v1/messages"
        self._timeout = timeout
        self._client = client

    def estimate(self, request: PhotoEstimateIn) -> PhotoEstimate:
        text = PROMPT + (f"\nThe user adds: {request.note}" if request.note else "")
        payload = {
            "model": self._model,
            "max_tokens": 800,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": request.media_type,
                                "data": request.image_base64,
                            },
                        },
                        {"type": "text", "text": text},
                    ],
                }
            ],
        }
        headers = {"x-api-key": self._api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"}
        client = self._client or httpx.Client(timeout=self._timeout)
        try:
            response = client.post(self._url, json=payload, headers=headers, timeout=self._timeout)
        except httpx.TimeoutException:
            raise EstimatorFailedError("Photo analysis took too long. Try again or log the meal by hand.") from None
        except httpx.HTTPError:
            raise EstimatorFailedError("Photo analysis is unreachable right now. Log the meal by hand.") from None
        finally:
            if self._client is None:
                client.close()
        if response.status_code >= 400:
            logger.warning("Food estimator returned status %s", response.status_code)
            raise EstimatorFailedError("Photo analysis failed. Try again or log the meal by hand.")
        try:
            body = response.json()
            raw = "".join(b.get("text", "") for b in body.get("content", []) if b.get("type") == "text")
            start, end = raw.find("{"), raw.rfind("}")
            reply = _ProviderReply.model_validate(json.loads(raw[start : end + 1]))
        except (ValueError, ValidationError, AttributeError, TypeError):
            logger.warning("Food estimator returned an invalid reply")
            raise EstimatorFailedError("Photo analysis gave an unreadable answer. Log the meal by hand.") from None
        totals = NutritionTotals(
            calories=sum(i.calories for i in reply.items),
            protein_g=sum(i.protein_g for i in reply.items),
            carbs_g=sum(i.carbs_g for i in reply.items),
            fat_g=sum(i.fat_g for i in reply.items),
        )
        confidence = reply.confidence if reply.confidence in ("low", "medium", "high") else "low"
        return PhotoEstimate(
            items=reply.items,
            totals=totals,
            confidence=confidence,
            suggested_description=reply.suggested_description or "Meal",
        )


def get_estimator() -> FoodPhotoEstimator:
    settings = get_settings()
    if settings.ai_provider == "anthropic" and settings.ai_api_key:
        return AnthropicFoodEstimator(
            api_key=settings.ai_api_key,
            model=settings.ai_model,
            base_url=settings.ai_base_url,
            timeout=max(settings.ai_timeout_seconds, 30.0),
        )
    return NotConfiguredEstimator()
