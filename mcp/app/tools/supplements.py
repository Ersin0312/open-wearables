"""MCP tools for querying the manual supplement (NEM) log."""

import logging
from collections import defaultdict

from fastmcp import FastMCP

from app.services.api_client import client
from app.utils import normalize_datetime

logger = logging.getLogger(__name__)

supplements_router = FastMCP(name="Supplement Tools")


@supplements_router.tool
async def get_supplement_log(
    user_id: str,
    start_date: str,
    end_date: str,
) -> dict:
    """
    Get the user's supplement (NEM) intake log within a date range.

    Returns logged intakes (what, how much, when, via which stack) plus a
    per-supplement daily-dose adherence summary (taken vs. recommended daily
    dose) and the user's configured stacks. Use this to analyse supplement
    consistency, dosing vs. recommendations, and which stacks are actually used.

    Args:
        user_id: UUID of the user. Use get_users to discover available users.
        start_date: Start date in YYYY-MM-DD format.
        end_date: End date in YYYY-MM-DD format.

    Returns:
        A dict with user, period, intakes[], stacks[], and adherence[] (per NEM:
        total taken, recommended daily dose, days logged, avg per logged day,
        percent_of_recommended).

    Notes for LLMs:
        - Doses carry their own unit (mg, g, IU, capsule, ...). Compare like with like.
        - recommended_daily_dose is an orientation value (DGE/EFSA); not every NEM has one.
        - If no time period is given, default to the last 2 weeks.
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

        supplements = await client.get_supplements(user_id)
        sup_lookup = {
            str(s.get("id")): {
                "name": s.get("name"),
                "brand": s.get("brand"),
                "unit": s.get("default_unit"),
                "recommended_daily_dose": s.get("recommended_daily_dose"),
            }
            for s in supplements
        }

        intakes_data = await client.get_supplement_intakes(
            user_id=user_id, start_date=start_date, end_date=end_date
        )

        intakes = []
        # (supplement_id) -> {total, days set, count}
        agg: dict[str, dict] = defaultdict(lambda: {"total": 0.0, "days": set(), "count": 0})

        for i in intakes_data:
            sid = str(i.get("supplement_id"))
            dose = float(i.get("dose") or 0)
            taken_at = i.get("taken_at")
            info = sup_lookup.get(sid, {"name": "Unbekannt", "unit": i.get("unit")})
            intakes.append(
                {
                    "supplement": info["name"],
                    "dose": dose,
                    "unit": i.get("unit") or info.get("unit"),
                    "taken_at": normalize_datetime(taken_at),
                    "via_stack": bool(i.get("stack_id")),
                }
            )
            a = agg[sid]
            a["total"] += dose
            a["count"] += 1
            if taken_at:
                a["days"].add(str(taken_at)[:10])

        adherence = []
        for sid, a in agg.items():
            info = sup_lookup.get(sid, {})
            rec = info.get("recommended_daily_dose")
            rec_f = float(rec) if rec else None
            days = len(a["days"]) or 1
            avg_per_day = a["total"] / days
            adherence.append(
                {
                    "supplement": info.get("name", "Unbekannt"),
                    "unit": info.get("unit"),
                    "total_taken": round(a["total"], 2),
                    "days_logged": len(a["days"]),
                    "avg_per_logged_day": round(avg_per_day, 2),
                    "recommended_daily_dose": rec_f,
                    "percent_of_recommended": (
                        round(avg_per_day / rec_f * 100) if rec_f and rec_f > 0 else None
                    ),
                }
            )
        adherence.sort(key=lambda x: x["supplement"])

        stacks_data = await client.get_supplement_stacks(user_id)
        stacks = [
            {
                "name": st.get("name"),
                "items": [
                    {
                        "supplement": sup_lookup.get(str(it.get("supplement_id")), {}).get("name", "Unbekannt"),
                        "dose": float(it["dose"]) if it.get("dose") is not None else None,
                        "unit": it.get("unit"),
                    }
                    for it in st.get("items", [])
                ],
            }
            for st in stacks_data
        ]

        return {
            "user": user,
            "period": {"start": start_date, "end": end_date},
            "intakes": intakes,
            "adherence": adherence,
            "stacks": stacks,
            "summary": {"total_intakes": len(intakes), "distinct_supplements": len(agg)},
        }

    except ValueError as e:
        logger.error(f"API error in get_supplement_log: {e}")
        return {"error": str(e)}
    except Exception as e:
        logger.exception(f"Unexpected error in get_supplement_log: {e}")
        return {"error": f"Failed to fetch supplement log: {e}"}
