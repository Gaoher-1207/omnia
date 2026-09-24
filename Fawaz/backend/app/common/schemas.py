from typing import Annotated, ClassVar, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

T = TypeVar("T")


def Text(max_length: int, min_length: int = 1):  # noqa: N802 - reads like a type
    """A trimmed string with length limits."""
    return Annotated[str, StringConstraints(strip_whitespace=True, min_length=min_length, max_length=max_length)]


HexColor = Annotated[str, StringConstraints(pattern=r"^#[0-9a-fA-F]{6}$")]


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class InputModel(BaseModel):
    """Request bodies reject unknown fields, so typos (or smuggled user_id fields) fail loudly."""

    model_config = ConfigDict(extra="forbid")


class PatchModel(InputModel):
    """PATCH body: omitted fields stay unchanged; explicit null is refused for required columns."""

    non_nullable: ClassVar[frozenset[str]] = frozenset()

    @model_validator(mode="after")
    def _no_null_for_required(self):
        bad = [name for name in self.model_fields_set if name in self.non_nullable and getattr(self, name) is None]
        if bad:
            raise ValueError(f"These fields cannot be null: {', '.join(sorted(bad))}")
        return self

    def changes(self) -> dict:
        return self.model_dump(exclude_unset=True)


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    limit: int
    offset: int


class PageParams(BaseModel):
    limit: int = Field(default=50, ge=1, le=200)
    offset: int = Field(default=0, ge=0)
