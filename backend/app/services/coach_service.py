"""In-app coach: a thin proxy that gathers the user's logged data, builds an
evidence-based coaching system prompt, and calls the Anthropic Claude API.

The Anthropic API key lives only in backend settings (never in the iOS app).
Data gathering reuses the existing services so there is one source of truth.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from logging import Logger, getLogger
from uuid import UUID

import httpx

from app.config import settings
from app.database import DbSession
from app.services.supplement_service import (
    supplement_intake_service,
    supplement_service,
)
from app.services.training_service import training_session_service

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"

SYSTEM_PROMPT = """Du bist „Der Wissenschaftler" — ein datengetriebener, evidenzbasierter
Health- & Performance-Coach. Stil: nüchtern, präzise, motivierend. Deutsch, Fachbegriffe
auf Englisch ok.

Du bekommst unten die aktuellen Daten des Nutzers (Training, Supplements, Körper).
Nutze sie konkret. Wenn Daten fehlen, sag das offen statt zu raten.

Bei einem Tagesplan gliedere in: Ernährung · Flüssigkeit · NEMs/Supplements · Recovery · Training.
Beziehe konkrete Zahlen ein und mach den Plan anpassbar (1-2 Alternativen je nach Tagesform).

Grenzen (immer einhalten): Du bist kein Arzt, keine Diagnosen, keine Medikamenten-Dosierung.
Supplement-Empfehlungen im sicheren Rahmen (DGE/EFSA). Du änderst nichts selbst — du
analysierst und empfiehlst; Änderungen macht der Nutzer in der App."""


class CoachService:
    def __init__(self, log: Logger):
        self.logger = log

    def is_enabled(self) -> bool:
        return settings.ANTHROPIC_API_KEY is not None and bool(
            settings.ANTHROPIC_API_KEY.get_secret_value()
        )

    def _gather_context(self, db: DbSession, user_id: UUID) -> str:
        """Build a compact, human-readable snapshot of the user's recent logs.
        Kept small on purpose to control token cost."""
        lines: list[str] = []
        now = datetime.now(timezone.utc)
        since = now - timedelta(days=14)

        # Training: last sessions + per-session volume
        try:
            sessions = training_session_service.list_for_user(db, user_id, since, now, None, 10, 0)
            if sessions:
                lines.append("## Training (letzte 14 Tage)")
                for s in sessions[:8]:
                    full = training_session_service.get_with_sets(db, s.id)
                    vol = sum(int(st.reps) * float(st.weight_kg) for st in full.sets)
                    started = s.started_at.strftime("%d.%m") if s.started_at else "?"
                    lines.append(
                        f"- {started} {s.split_tag}: {len(full.sets)} Sätze, Volumen {round(vol)} kg"
                    )
            else:
                lines.append("## Training: keine Sessions in den letzten 14 Tagen.")
        except Exception as e:  # noqa: BLE001
            lines.append(f"## Training: nicht abrufbar ({e}).")

        # Supplements: today's intakes vs. recommended
        try:
            sups = {str(s.id): s for s in supplement_service.list_visible_for_user(db, user_id)}
            day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
            intakes = supplement_intake_service.list_for_user(db, user_id, day_start, now, None, 200, 0)
            if intakes:
                lines.append("## Supplements heute")
                totals: dict[str, float] = {}
                for i in intakes:
                    totals[str(i.supplement_id)] = totals.get(str(i.supplement_id), 0) + float(i.dose)
                for sid, total in totals.items():
                    sup = sups.get(sid)
                    if not sup:
                        continue
                    rec = float(sup.recommended_daily_dose) if sup.recommended_daily_dose else None
                    if rec:
                        pct = round(total / rec * 100)
                        lines.append(f"- {sup.name}: {total} {sup.default_unit} ({pct}% der Tagesdosis)")
                    else:
                        lines.append(f"- {sup.name}: {total} {sup.default_unit}")
            else:
                lines.append("## Supplements: heute noch nichts geloggt.")
        except Exception as e:  # noqa: BLE001
            lines.append(f"## Supplements: nicht abrufbar ({e}).")

        return "\n".join(lines) if lines else "Keine Daten verfügbar."

    async def chat(
        self,
        db: DbSession,
        user_id: UUID,
        message: str,
        history: list[dict] | None = None,
    ) -> str:
        if not self.is_enabled():
            raise ValueError("Coach ist nicht konfiguriert (ANTHROPIC_API_KEY fehlt).")

        context = self._gather_context(db, user_id)
        system = f"{SYSTEM_PROMPT}\n\n# Aktuelle Daten des Nutzers\n{context}"

        messages: list[dict] = []
        for turn in (history or [])[-10:]:
            role = turn.get("role")
            content = turn.get("content")
            if role in ("user", "assistant") and content:
                messages.append({"role": role, "content": content})
        messages.append({"role": "user", "content": message})

        payload = {
            "model": settings.COACH_MODEL,
            "max_tokens": settings.COACH_MAX_TOKENS,
            "system": system,
            "messages": messages,
        }
        headers = {
            "x-api-key": settings.ANTHROPIC_API_KEY.get_secret_value(),
            "anthropic-version": ANTHROPIC_VERSION,
            "content-type": "application/json",
        }

        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(ANTHROPIC_URL, json=payload, headers=headers)
            if resp.status_code != 200:
                self.logger.error(f"Anthropic error {resp.status_code}: {resp.text[:300]}")
                raise ValueError(f"Coach-API Fehler {resp.status_code}")
            data = resp.json()

        # Concatenate text blocks from the response.
        parts = [b.get("text", "") for b in data.get("content", []) if b.get("type") == "text"]
        return "".join(parts).strip() or "(keine Antwort)"


coach_service = CoachService(log=getLogger(__name__))
