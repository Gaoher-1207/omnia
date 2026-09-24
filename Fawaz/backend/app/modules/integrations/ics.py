"""A tiny iCalendar (RFC 5545) writer: enough for subscribed read-only feeds."""

from datetime import UTC, date, datetime, time, timedelta


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\r", "").replace("\n", "\\n")


def _fold(line: str) -> str:
    """Lines longer than 75 octets continue on the next line after a space."""
    raw = line.encode()
    if len(raw) <= 75:
        return line
    parts, current = [], b""
    for char in line:
        encoded = char.encode()
        if len(current) + len(encoded) > (75 if not parts else 74):
            parts.append(current.decode())
            current = b""
        current += encoded
    parts.append(current.decode())
    return "\r\n ".join(parts)


class Calendar:
    def __init__(self, name: str, tz: str):
        self.tz = tz
        self.lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//OMNIA//Planner//EN",
            "CALSCALE:GREGORIAN",
            f"X-WR-CALNAME:{_escape(name)}",
            f"X-WR-TIMEZONE:{tz}",
        ]
        self.stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")

    def all_day(self, uid: str, day: date, summary: str, description: str | None = None) -> None:
        self._event(
            uid,
            f"DTSTART;VALUE=DATE:{day:%Y%m%d}",
            f"DTEND;VALUE=DATE:{day + timedelta(days=1):%Y%m%d}",
            summary,
            description,
        )

    def timed(self, uid: str, day: date, start: time, end: time, summary: str, description: str | None = None) -> None:
        self._event(
            uid,
            f"DTSTART;TZID={self.tz}:{datetime.combine(day, start):%Y%m%dT%H%M%S}",
            f"DTEND;TZID={self.tz}:{datetime.combine(day, end):%Y%m%dT%H%M%S}",
            summary,
            description,
        )

    def _event(self, uid: str, start: str, end: str, summary: str, description: str | None) -> None:
        self.lines += ["BEGIN:VEVENT", f"UID:{uid}@omnia", f"DTSTAMP:{self.stamp}", start, end]
        self.lines.append(f"SUMMARY:{_escape(summary)}")
        if description:
            self.lines.append(f"DESCRIPTION:{_escape(description)}")
        self.lines.append("END:VEVENT")

    def render(self) -> str:
        return "\r\n".join(_fold(line) for line in [*self.lines, "END:VCALENDAR"]) + "\r\n"
