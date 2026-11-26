from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException
from supabase import Client, create_client

from ..auth import require_auth

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


def _client() -> Client:
    from os import getenv

    url = getenv("SUPABASE_URL", "")
    key = getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise HTTPException(status_code=500, detail="Supabase env not configured")
    return create_client(url, key)


def _all_rows(build_query) -> list[dict[str, Any]]:
    rows = []
    page_size = 500
    while True:
        page = (
            build_query().order("id").range(len(rows), len(rows) + page_size - 1)
            .execute().data or []
        )
        rows.extend(page)
        if len(page) < page_size:
            return rows


def _owned_distractions(client, user_id, columns, since, until):
    return _all_rows(
        lambda: client.table("distraction_events")
        .select(f"{columns},focus_sessions!inner(user_id)")
        .eq("focus_sessions.user_id", user_id)
        .eq("event_type", "distraction")
        .gte("triggered_at", since.isoformat())
        .lt("triggered_at", until.isoformat())
    )


@router.get("/summary/{user_id}")
def summary(
    user_id: str,
    authed_user: Annotated[str, Depends(require_auth)],
) -> dict[str, Any]:
    # C3 fix: callers may only read their own analytics.
    if authed_user != user_id:
        raise HTTPException(status_code=403, detail="Access denied: user_id mismatch.")

    client = _client()
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=7)
    sessions = _all_rows(
        lambda: client.table("focus_sessions")
        .select("id,focus_score")
        .eq("user_id", user_id)
        .eq("status", "completed")
        .gte("start_time", since.isoformat())
        .lt("start_time", now.isoformat())
        .lte("end_time", now.isoformat())
    )
    events = _owned_distractions(client, user_id, "app_label", since, now)

    avg_focus = round(
        sum(float(s.get("focus_score", 0)) for s in sessions) / max(len(sessions), 1),
        2,
    )
    app_counts = Counter(e.get("app_label", "Unknown") for e in events)
    return {
        "weekly_sessions": len(sessions),
        "focus_score_average": avg_focus,
        "top_distracting_apps": app_counts.most_common(5),
    }


@router.get("/sessions/{user_id}")
def sessions(
    user_id: str,
    authed_user: Annotated[str, Depends(require_auth)],
) -> list[dict[str, Any]]:
    if authed_user != user_id:
        raise HTTPException(status_code=403, detail="Access denied: user_id mismatch.")

    client = _client()
    rows = (
        client.table("focus_sessions")
        .select("*")
        .eq("user_id", user_id)
        .order("start_time", desc=True)
        .limit(30)
        .execute()
        .data
        or []
    )
    return list(rows)


@router.get("/risk-trend/{user_id}")
def risk_trend(
    user_id: str,
    authed_user: Annotated[str, Depends(require_auth)],
) -> list[dict[str, Any]]:
    if authed_user != user_id:
        raise HTTPException(status_code=403, detail="Access denied: user_id mismatch.")

    client = _client()
    now = datetime.now(timezone.utc)
    since = now.replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=13)
    events = _owned_distractions(client, user_id, "triggered_at,risk_score", since, now)
    grouped: dict[str, list[str]] = defaultdict(list)
    for event in events:
        ts = datetime.fromisoformat(str(event["triggered_at"]).replace("Z", "+00:00"))
        grouped[ts.astimezone(timezone.utc).date().isoformat()].append(str(event.get("risk_score")))

    daily = []
    for day, risks in sorted(grouped.items()):
        daily.append({"date": day, "risk_scores": risks})
    return daily
