from __future__ import annotations

from typing import Annotated, List, Optional
from pydantic import BaseModel, Field


class IntentionRefineRequest(BaseModel):
    """
    Intention refinement request.
    Security: User is derived from JWT (require_auth). Never accept user_id from body.
    Max 120 characters to bound prompt size and prevent large payload attacks.
    """
    raw_intention: str = Field(
        ...,
        min_length=1,
        max_length=120,
        description="Raw user intention text. Treated as untrusted input."
    )


class LLMIntentionRefinePayload(BaseModel):
    """Strict JSON contract returned by the coach model for intention refinement."""
    is_sufficiently_clear: bool
    refined_intention: str = Field(..., min_length=1, max_length=120)
    clarity_score: int = Field(..., ge=1, le=100)
    coach_feedback: str = Field(..., min_length=1, max_length=250)

class IntentionRefineResponse(BaseModel):
    is_sufficiently_clear: bool
    refined_intention: str
    clarity_score: int = Field(..., ge=1, le=100)
    coach_feedback: str
    is_fallback: bool = False


class CoachQuestion(BaseModel):
    question: str = Field(min_length=1, max_length=120)
    previous_question: Optional[str] = Field(default=None, max_length=120)


class CoachAdvice(BaseModel):
    advice: str = Field(min_length=1, max_length=480)


class CoachAnswer(CoachAdvice):
    is_fallback: bool
    sessions_analyzed: int


class TaskSteps(BaseModel):
    steps: List[Annotated[str, Field(min_length=1, max_length=120)]] = Field(min_length=2, max_length=5)


class TaskDraft(TaskSteps):
    is_fallback: bool


class SessionDebriefRequest(BaseModel):
    """
    Post-session debrief request.
    Carries ONLY session_id. Server computes all stats internally.
    """
    session_id: str = Field(..., description="UUID of the completed focus session.")


class LLMSessionDebriefPayload(BaseModel):
    """Strict JSON contract returned by the coach model for a debrief."""
    headline: str = Field(..., min_length=1, max_length=80)
    body: str = Field(..., min_length=1, max_length=400)
    actionable_tip: str = Field(..., min_length=1, max_length=250)

class SessionDebriefResponse(BaseModel):
    session_id: str
    headline: str
    body: str
    actionable_tip: str
    distraction_minute_offsets: List[float] = Field(
        default_factory=list,
        description="Minute offset of each distraction from session start."
    )
    total_sessions_analyzed: int
    is_fallback: bool = False
    is_cached: bool = False


class CoachFeedbackRequest(BaseModel):
    insight_id: str
    feedback: int = Field(..., ge=-1, le=1, description="-1 = unhelpful, 0 = neutral, 1 = helpful")


class CoachOptInRequest(BaseModel):
    opt_in: bool


class CoachOptInResponse(BaseModel):
    is_opted_in: bool
    opted_in_at: Optional[str] = None
