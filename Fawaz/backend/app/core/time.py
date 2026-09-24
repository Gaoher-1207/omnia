"""Time helpers. "Today" always means today in the user's own timezone."""

import re
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def utcnow() -> datetime:
    """Single source of 'now' so tests can freeze time by patching this function."""
    return datetime.now(UTC)


# Browsers still report some pre-2015 names (Chrome in India sends "Asia/Calcutta").
# Store the current IANA name so every server resolves it, with or without legacy tzdata.
LEGACY_TIMEZONES = {
    "Asia/Calcutta": "Asia/Kolkata",
    "Asia/Katmandu": "Asia/Kathmandu",
    "Asia/Saigon": "Asia/Ho_Chi_Minh",
    "Asia/Rangoon": "Asia/Yangon",
    "Asia/Dacca": "Asia/Dhaka",
    "Asia/Thimbu": "Asia/Thimphu",
    "Asia/Ulan_Bator": "Asia/Ulaanbaatar",
    "Europe/Kiev": "Europe/Kyiv",
    "America/Buenos_Aires": "America/Argentina/Buenos_Aires",
    "America/Indianapolis": "America/Indiana/Indianapolis",
    "Atlantic/Faeroe": "Atlantic/Faroe",
    "Pacific/Truk": "Pacific/Chuuk",
    "Pacific/Ponape": "Pacific/Pohnpei",
    "Etc/UTC": "UTC",
    "Etc/GMT": "UTC",
}
_TZ_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_+\-]*(/[A-Za-z0-9_+\-]+){0,2}$")


def normalize_timezone(name: str) -> str | None:
    """Return the canonical IANA name, or None if the zone doesn't exist."""
    name = LEGACY_TIMEZONES.get(name.strip(), name.strip())
    if len(name) > 64 or not _TZ_NAME.match(name):
        return None
    try:
        ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return None
    return name


def is_valid_timezone(name: str) -> bool:
    return normalize_timezone(name) is not None


def local_now(tz: str) -> datetime:
    return utcnow().astimezone(ZoneInfo(tz))


def local_today(tz: str) -> date:
    return local_now(tz).date()


def to_local_date(moment: datetime, tz: str) -> date:
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=UTC)
    return moment.astimezone(ZoneInfo(tz)).date()
