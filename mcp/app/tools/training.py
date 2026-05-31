"""MCP tools for querying the manual strength-training log."""

import logging

from fastmcp import FastMCP

from app.services.api_client import client
from app.utils import normalize_datetime

logger = logging.getLogger(__name__)

training_router = FastMCP(name="Training Tools")

_SPLIT_LABELS = {"push": "Push", "pull": "Pull", "legs": "Beine", "custom": "Custom"}


@training_router.tool
async def get_training_log(
    user_id: str,
    start_date: str,
    end_date: str,
    include_sets: bool = True,
) -> dict:
    """
    Get the user's manual strength-training log within a date range.

    Returns each training session (split, start/end, duration) and — when
    include_sets is true — every logged set grouped by exercise, plus computed
    training volume (sets x reps x weight) per exercise and per session. Use
    this to analyse training load, progression, and balance across muscle groups.

    Args:
        user_id: UUID of the user. Use get_users to discover available users.
        start_date: Start date in YYYY-MM-DD format.
        end_date: End date in YYYY-MM-DD format.
        include_sets: If true (default) fetch the sets for each session. Set to
                      false for a faster overview of just session metadata.

    Returns:
        A dict with user, period, sessions[], and a summary. Each session has:
        split, started_at, ended_at, duration_minutes, total_volume_kg, and
        exercises[] (name, muscle_group, sets[] with reps/weight_kg).

    Notes for LLMs:
        - Volume = sum over sets of reps * weight_kg (a standard training-load proxy).
        - Split tags: push, pull, legs, custom.
        - If no time period is given, default to the last 4 weeks.
        - Weights are kilograms.
    """
    try:
        try:
            user_data = await client.get_user(user_id)
            user = {
                "id": str(user_data.get("id")),
                "first_name": user_data.get("first_name"),
                "last_name": user_data.get("last_name"),
            }
        except ValueError as e:
            return {"error": f"User not found: {user_id}", "details": str(e)}

        sessions_data = await client.get_training_sessions(
            user_id=user_id, start_date=start_date, end_date=end_date
        )

        # Build an exercise_id -> {name, muscle_group} lookup once.
        exercises = await client.get_exercises(user_id)
        ex_lookup = {
            str(e.get("id")): {
                "name": e.get("name"),
                "muscle_group": e.get("primary_muscle_group"),
            }
            for e in exercises
        }

        sessions = []
        total_volume_all = 0.0

        for s in sessions_data:
            session_id = str(s.get("id"))
            started = s.get("started_at")
            ended = s.get("ended_at")
            duration_min = None
            if started and ended:
                try:
                    from datetime import datetime

                    d0 = datetime.fromisoformat(str(started).replace("Z", "+00:00"))
                    d1 = datetime.fromisoformat(str(ended).replace("Z", "+00:00"))
                    duration_min = round((d1 - d0).total_seconds() / 60)
                except (ValueError, TypeError):
                    duration_min = None

            session_obj = {
                "session_id": session_id,
                "split": _SPLIT_LABELS.get(s.get("split_tag"), s.get("split_tag")),
                "started_at": normalize_datetime(started),
                "ended_at": normalize_datetime(ended),
                "duration_minutes": duration_min,
                "notes": s.get("notes"),
            }

            if include_sets:
                sets_data = await client.get_training_session_sets(user_id, session_id)
                by_exercise: dict[str, dict] = {}
                session_volume = 0.0
                for st in sets_data:
                    ex_id = str(st.get("exercise_id"))
                    reps = st.get("reps") or 0
                    weight = float(st.get("weight_kg") or 0)
                    session_volume += reps * weight
                    info = ex_lookup.get(ex_id, {"name": "Unbekannt", "muscle_group": None})
                    grp = by_exercise.setdefault(
                        ex_id,
                        {"name": info["name"], "muscle_group": info["muscle_group"], "sets": []},
                    )
                    grp["sets"].append(
                        {
                            "set_number": st.get("set_number"),
                            "reps": reps,
                            "weight_kg": weight,
                        }
                    )
                session_obj["exercises"] = list(by_exercise.values())
                session_obj["total_volume_kg"] = round(session_volume)
                total_volume_all += session_volume

            sessions.append(session_obj)

        summary = {
            "total_sessions": len(sessions),
            "total_volume_kg": round(total_volume_all) if include_sets else None,
        }

        return {
            "user": user,
            "period": {"start": start_date, "end": end_date},
            "sessions": sessions,
            "summary": summary,
        }

    except ValueError as e:
        logger.error(f"API error in get_training_log: {e}")
        return {"error": str(e)}
    except Exception as e:
        logger.exception(f"Unexpected error in get_training_log: {e}")
        return {"error": f"Failed to fetch training log: {e}"}
