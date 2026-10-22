#!/usr/bin/env python3
"""
Moon phase calculator.

Calculates the current phase of the moon (or for a given date) using a
simple astronomical approximation based on the known synodic month length
and a reference new moon date. No external dependencies required.

Usage:
    python moon_phase.py                  # today's phase
    python moon_phase.py 2024-12-25        # phase on a specific date (YYYY-MM-DD)
"""

import sys
from datetime import datetime, timezone

# Ensure emoji / unicode output works on all platforms (e.g. Windows cp1252 console)
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# Known reference new moon (UTC): January 6, 2000, 18:14 UTC
REFERENCE_NEW_MOON = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)

# Average length of a synodic month (new moon to new moon), in days
SYNODIC_MONTH = 29.53058867

PHASES = [
    (0.0, "New Moon", "🌑"),
    (0.125, "Waxing Crescent", "🌒"),
    (0.25, "First Quarter", "🌓"),
    (0.375, "Waxing Gibbous", "🌔"),
    (0.5, "Full Moon", "🌕"),
    (0.625, "Waning Gibbous", "🌖"),
    (0.75, "Last Quarter", "🌗"),
    (0.875, "Waning Crescent", "🌘"),
    (1.0, "New Moon", "🌑"),
]


def moon_age(date: datetime) -> float:
    """Days since the last new moon (0 = new moon, ~14.76 = full moon)."""
    days_since_reference = (date - REFERENCE_NEW_MOON).total_seconds() / 86400
    age = days_since_reference % SYNODIC_MONTH
    return age


def moon_phase_fraction(date: datetime) -> float:
    """Fraction through the current lunar cycle, 0.0 to 1.0."""
    return moon_age(date) / SYNODIC_MONTH


def phase_name(fraction: float) -> tuple[str, str]:
    """Map a 0.0-1.0 fraction to the nearest named phase + emoji."""
    # Find the closest boundary (wrapping New Moon at both ends)
    closest = min(PHASES, key=lambda p: min(abs(fraction - p[0]), abs(fraction - p[0] + 1), abs(fraction - p[0] - 1)))
    return closest[1], closest[2]


def illumination(fraction: float) -> float:
    """Approximate percentage of the moon's visible disk illuminated."""
    import math
    return (1 - math.cos(2 * math.pi * fraction)) / 2 * 100


def main() -> None:
    if len(sys.argv) > 1:
        try:
            date = datetime.strptime(sys.argv[1], "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            print("Invalid date format. Use YYYY-MM-DD, e.g. 2024-12-25")
            sys.exit(1)
    else:
        date = datetime.now(timezone.utc)

    age = moon_age(date)
    fraction = moon_phase_fraction(date)
    name, emoji = phase_name(fraction)
    percent_lit = illumination(fraction)

    print(f"Date: {date.strftime('%Y-%m-%d')} (UTC)")
    print(f"Moon age: {age:.1f} days into a {SYNODIC_MONTH:.2f}-day cycle")
    print(f"Illumination: {percent_lit:.1f}%")
    print(f"Phase: {emoji}  {name}")


if __name__ == "__main__":
    main()
