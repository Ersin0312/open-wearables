"""MCP tools for querying body composition (weight, body fat, BMI)."""

import logging

from fastmcp import FastMCP

from app.services.api_client import client
from app.utils import normalize_datetime

logger = logging.getLogger(__name__)

body_router = FastMCP(name="Body Composition Tools")


@body_router.tool
async def get_body_composition(
    user_id: str,
    start_date: str | None = None,
    end_date: str | None = None,
) -> dict:
    """
    Get the user's body composition: current snapshot plus weight and body-fat
    trends over time.

    The snapshot (weight, body fat %, muscle mass, BMI) reflects the latest
    measurements. When start_date and end_date are given, also returns the
    weight and body-fat time series over that window (from the user's smart
    scale via Apple Health), so you can analyse trends and rate of change.

    Args:
        user_id: UUID of the user. Use get_users to discover available users.
        start_date: Optional trend window start (YYYY-MM-DD). Defaults to no trend.
        end_date: Optional trend window end (YYYY-MM-DD).

    Returns:
        A dict with user, snapshot (weight_kg, body_fat_percent, muscle_mass_kg,
        bmi), and — if a window was given — trend (weight[], body_fat[]) plus
        computed deltas over the window.

    Notes for LLMs:
        - Weight is kilograms, body fat is percent, BMI is kg/m^2.
        - The smart-scale data flows in via Apple Health auto-export; values may
          be sparse (e.g. only on days the user weighed themselves).
        - There can be two weight sources (scale + a wearable's profile weight);
          prefer the scale trend for tracking change over time.
        - If no window is given, default to the last 90 days for trends.
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

        body = await client.get_body_summary(user_id)
        slow = (body or {}).get("slow_changing", {}) if isinstance(body, dict) else {}
        snapshot = {
            "weight_kg": slow.get("weight_kg"),
            "body_fat_percent": slow.get("body_fat_percent"),
            "muscle_mass_kg": slow.get("muscle_mass_kg"),
            "bmi": slow.get("bmi"),
            "height_cm": slow.get("height_cm"),
        }

        result = {"user": user, "snapshot": snapshot}

        if start_date and end_date:
            # The timeseries endpoint caps limit at 100, so page through with the
            # cursor until exhausted (body-scale data is sparse, usually 1 page).
            samples: list[dict] = []
            cursor: str | None = None
            for _ in range(20):  # hard stop: max 2000 points
                ts = await client.get_timeseries(
                    user_id=user_id,
                    start_time=f"{start_date}T00:00:00Z",
                    end_time=f"{end_date}T23:59:59Z",
                    types=["weight", "body_fat_percentage"],
                    resolution="1hour",
                    limit=100,
                    cursor=cursor,
                )
                if not isinstance(ts, dict):
                    break
                samples.extend(ts.get("data", []))
                pagination = ts.get("pagination") or {}
                cursor = pagination.get("next_cursor")
                if not cursor or not pagination.get("has_more"):
                    break
            weight_pts = []
            fat_pts = []
            for s in samples:
                t = s.get("type")
                point = {"t": normalize_datetime(s.get("timestamp")), "value": s.get("value")}
                if t == "weight":
                    weight_pts.append(point)
                elif t == "body_fat_percentage":
                    fat_pts.append(point)
            weight_pts.sort(key=lambda p: p["t"] or "")
            fat_pts.sort(key=lambda p: p["t"] or "")

            def _delta(pts: list[dict]) -> float | None:
                vals = [p["value"] for p in pts if isinstance(p["value"], (int, float))]
                return round(vals[-1] - vals[0], 2) if len(vals) >= 2 else None

            result["trend"] = {
                "period": {"start": start_date, "end": end_date},
                "weight": weight_pts,
                "body_fat": fat_pts,
                "weight_delta_kg": _delta(weight_pts),
                "body_fat_delta_pct": _delta(fat_pts),
            }

        return result

    except ValueError as e:
        logger.error(f"API error in get_body_composition: {e}")
        return {"error": str(e)}
    except Exception as e:
        logger.exception(f"Unexpected error in get_body_composition: {e}")
        return {"error": f"Failed to fetch body composition: {e}"}
