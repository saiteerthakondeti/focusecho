"""Score contracts across distraction pressure, recovery time and session length."""
from itertools import product

import pytest

from app.services.scoring.focus_score import explain_focus_score


@pytest.mark.parametrize("count,seconds,minutes", product(
    (0, 1, 2, 3, 7, 15, 31), (0, 30, 60, 600, 1200),
    (1, 9, 10, 19, 20, 24, 25, 99, 100),
))
def test_score_breakdown_and_feedback(count, seconds, minutes):
    events = [{"recovery_time_seconds": seconds, "is_recovered": True}] * count
    result = explain_focus_score(events, minutes)
    control = {0:60, 1:45, 2:36.225562489, 3:30, 7:15, 15:0, 31:0}[count]
    recovery = 20 - seconds / 60 if count else 20
    expected = min(100, control + recovery + 20 + min(minutes // 10 * 2, 20))
    assert result["score"] == round(expected, 1)
    assert result["breakdown"]["distraction_control"] == round(control, 1)
    assert ("Slow average recovery time" in result["negative_factors"]) == bool(count and seconds >= 60)
    assert any("minute session" in text for text in result["positive_factors"]) == (minutes >= 25)
