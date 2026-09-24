import base64
import binascii
import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.common.schemas import InputModel, ORMModel, PatchModel, Text

MealType = Literal["breakfast", "lunch", "dinner", "snack"]
MealSource = Literal["manual", "photo_estimate"]
ImageType = Literal["image/jpeg", "image/png", "image/webp"]
MAX_IMAGE_BYTES = 5 * 1024 * 1024

_MAGIC = {
    "image/jpeg": (b"\xff\xd8\xff",),
    "image/png": (b"\x89PNG\r\n\x1a\n",),
    "image/webp": (b"RIFF",),
}


class MealCreate(InputModel):
    day: date | None = Field(default=None, description="Defaults to today in your timezone")
    meal_type: MealType
    description: Text(200)
    calories: int = Field(default=0, ge=0, le=5000)
    protein_g: int = Field(default=0, ge=0, le=500)
    carbs_g: int = Field(default=0, ge=0, le=1000)
    fat_g: int = Field(default=0, ge=0, le=500)
    source: MealSource = "manual"


class MealUpdate(PatchModel):
    non_nullable = frozenset({"meal_type", "description", "calories", "protein_g", "carbs_g", "fat_g"})

    meal_type: MealType | None = None
    description: Text(200) | None = None
    calories: int | None = Field(default=None, ge=0, le=5000)
    protein_g: int | None = Field(default=None, ge=0, le=500)
    carbs_g: int | None = Field(default=None, ge=0, le=1000)
    fat_g: int | None = Field(default=None, ge=0, le=500)


class MealOut(ORMModel):
    id: uuid.UUID
    day: date
    meal_type: MealType
    description: str
    calories: int
    protein_g: int
    carbs_g: int
    fat_g: int
    source: MealSource
    created_at: datetime


class NutritionTotals(BaseModel):
    calories: int = 0
    protein_g: int = 0
    carbs_g: int = 0
    fat_g: int = 0


class DayMeals(BaseModel):
    day: date
    calorie_goal: int
    totals: NutritionTotals
    meals: list[MealOut]


class DayTotals(NutritionTotals):
    day: date
    meal_count: int = 0


class NutritionSummary(BaseModel):
    start: date
    end: date
    calorie_goal: int
    days: list[DayTotals]


# ---- food photo estimate


class PhotoEstimateIn(InputModel):
    image_base64: str = Field(description="The photo, base64-encoded. Max 5 MB decoded.")
    media_type: ImageType
    note: str | None = Field(default=None, max_length=200, description="Optional hint, e.g. 'half portion'")

    @field_validator("image_base64")
    @classmethod
    def _decodes(cls, value: str) -> str:
        value = value.strip()
        if value.startswith("data:") and "," in value:
            value = value.split(",", 1)[1]
        if len(value) > (MAX_IMAGE_BYTES * 4) // 3 + 8:
            raise ValueError("Image is larger than 5 MB")
        try:
            raw = base64.b64decode(value, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("Image is not valid base64") from None
        if not raw:
            raise ValueError("Image is empty")
        return value

    def image_bytes(self) -> bytes:
        return base64.b64decode(self.image_base64)

    def looks_like_declared_type(self) -> bool:
        head = self.image_bytes()[:12]
        return any(head.startswith(sig) for sig in _MAGIC[self.media_type])


class EstimatedItem(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    portion: str | None = Field(default=None, max_length=60)
    calories: int = Field(ge=0, le=5000)
    protein_g: int = Field(ge=0, le=500)
    carbs_g: int = Field(ge=0, le=1000)
    fat_g: int = Field(ge=0, le=500)


class PhotoEstimate(BaseModel):
    """Numbers are estimates for the user to confirm or edit; nothing is saved automatically."""

    items: list[EstimatedItem] = Field(max_length=12)
    totals: NutritionTotals
    confidence: Literal["low", "medium", "high"]
    suggested_description: str = Field(max_length=200)
    disclaimer: str = "AI estimate from a photo. Check it before saving; it isn't medical or dietary advice."
