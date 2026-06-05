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
from sqlalchemy import func, select

from app.config import settings
from app.database import DbSession
from app.models import CardioSession, DataPointSeries, NutritionEntry, SeriesTypeDefinition
from app.schemas.enums import SeriesType
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

# --- Proactive briefing prompts ---

_BRIEF_FORMAT = """# Ausgabeformat (strikt einhalten)
Zeile 1: EINE prägnante Headline (max. 12 Wörter, kein Markdown, keine Aufzählung).
Danach eine Leerzeile, dann der Body.

ABSOLUT WICHTIG zur Form des Body:
- Schreibe AUSSCHLIESSLICH in vollständigen, zusammenhängenden Sätzen und Absätzen.
- Verwende KEINE Aufzählungszeichen, KEINE Bullet-Points, KEINE Stichworte
  (also kein "-", "*", "•", keine Listen). Jeder Abschnitt ist Fließtext.
- Markdown-Überschriften mit "## " sind erlaubt, um Abschnitte zu gliedern, und
  **fett** für einzelne Begriffe — aber der Inhalt darunter ist immer Prosa.
- Roter Faden: Die Absätze bauen aufeinander auf, von Analyse zu Empfehlung.
- Beziehe IMMER die konkreten Zahlen aus den Daten ein und vergleiche mit den Vortagen."""

_MORNING_INSTRUCTION = """Erstelle einen ausführlichen, durchdachten Morgenbrief für heute,
in vollständigen Sätzen und zusammenhängenden Absätzen (keine Stichpunkte).

Beginne mit einem Absatz unter **## Lagebild**, der ALLE verfügbaren Zahlen in Prosa
zusammenfasst und einordnet: Recovery-Score, HRV, Ruhepuls, Schlafdauer, Schritte
gestern vs. Ziel, aktuelles Gewicht und Abstand zum Phasenziel, Ernährungsstand
(kcal/Protein bisher vs. Ziel), ob schon trainiert/Supplements/Wasser geloggt wurde,
Tag/Phase im Plan. Vergleiche dabei ausdrücklich mit den VORTAGEN (Trend der letzten
Tage bei Ernährung, Training, Supplements, Wasser, Schritten) statt nur den heutigen
Stand zu nennen, und verknüpfe die Werte zu einer Einschätzung.

Danach schreibst du detaillierte Empfehlungen als zusammenhängende Absätze:
**## Training** – die heutige Einheit, Voll- oder Teillast je nach Recovery, konkrete
Sätze/Intensität, mit Bezug zur letzten gleichen Einheit.
**## Ernährung & Flüssigkeit** – wie kcal/Protein heute realistisch erreicht werden
(konkrete Lebensmittel/Mengen), Timing rund ums Training, und ob das Wasserziel und die
10.000 Schritte gestern erreicht wurden bzw. wie heute.
**## Supplements & Recovery** – was heute sinnvoll ist (Timing, auch im Licht der
Vortage), Schlaf- und Stresshinweise.

Schließe mit **## Wichtigster Hebel heute** in ein bis zwei Sätzen. Wenn Daten fehlen,
benenne es offen statt zu raten."""

_WEEKLY_INSTRUCTION = """Schreibe ein ausführliches Wochenreview der letzten 7 Tage in
vollständigen, gut lesbaren Sätzen mit klarem rotem Faden — KEINE knappen Stichpunkte,
sondern zusammenhängende Absätze, die aufeinander aufbauen.

Beginne mit **## Ist-Analyse**: Schildere in mehreren Sätzen, wo der Nutzer aktuell
steht — Gewichtstrend der Woche und Abstand/Pace zum Phasenziel (mit Zahlen belegt),
Trainingsfrequenz und -volumen, Recovery-Verlauf, Ernährungs-Adherence (kcal/Protein).
Ordne ein, ob das zusammen ein stimmiges Bild ergibt oder wo es hakt.

Leite daraus **## Bewertung** ab: Was lief diese Woche gut und warum, was bremst den
Fortschritt — ehrlich und begründet, in Prosa.

Dann gibst du konkrete, schrittweise Empfehlungen für die kommende Woche, jeweils als
eigener zusammenhängender Absatz in ganzen Sätzen (keine Stichpunkte):
**## Training** – was beibehalten, was anpassen (Frequenz, Progression, Geräte).
**## Ernährung** – kcal/Protein-Justierung mit Begründung am Gewichtstrend der Woche.
**## Supplements** – was sinnvoll ist oder fehlt, gemessen an der Einnahme der Vortage.
**## Recovery, Schlaf & Aktivität** – Stellschrauben bei Schlaf, Recovery und den
täglichen 10.000 Schritten (Wochenschnitt der Schritte einordnen).

Schließe mit **## Fokus der Woche** und ein bis zwei messbaren Vorsätzen, die den größten
Hebel haben. Sei ehrlich: wenn Gewicht stagniert oder Training ausfiel, benenne es klar
und konstruktiv."""


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

        week_start = now - timedelta(days=7)

        # Supplements: per-day intake counts over the last 7 days (+ today's detail)
        try:
            sups = {str(s.id): s for s in supplement_service.list_visible_for_user(db, user_id)}
            week_intakes = supplement_intake_service.list_for_user(db, user_id, week_start, now, None, 500, 0)
            by_day: dict[str, set[str]] = {}
            for i in week_intakes:
                day = i.taken_at.strftime("%d.%m")
                by_day.setdefault(day, set()).add(str(i.supplement_id))
            lines.append("## Supplements (letzte 7 Tage)")
            if by_day:
                lines.append(f"An {len(by_day)} von 7 Tagen geloggt.")
                today_key = now.strftime("%d.%m")
                today_ids = by_day.get(today_key, set())
                if today_ids:
                    names = ", ".join(sups[s].name for s in today_ids if s in sups)
                    lines.append(f"Heute bereits: {names}.")
                else:
                    lines.append("Heute noch keine Supplements geloggt.")
            else:
                lines.append("In den letzten 7 Tagen nichts geloggt.")
        except Exception as e:  # noqa: BLE001
            lines.append(f"## Supplements: nicht abrufbar ({e}).")

        # Nutrition: per-day kcal + protein over the last 7 days
        try:
            entries = db.execute(
                select(NutritionEntry).where(
                    NutritionEntry.user_id == user_id, NutritionEntry.eaten_at >= week_start
                )
            ).scalars().all()
            if entries:
                per_day: dict[str, tuple[float, float]] = {}
                for e in entries:
                    day = e.eaten_at.strftime("%d.%m")
                    kcal, prot = per_day.get(day, (0.0, 0.0))
                    per_day[day] = (kcal + float(e.calories or 0), prot + float(e.protein_g or 0))
                lines.append("## Ernährung (letzte 7 Tage, kcal / Protein g)")
                for day in sorted(per_day):
                    kcal, prot = per_day[day]
                    lines.append(f"{day}: {round(kcal)} kcal, {round(prot)} g")
            else:
                lines.append("## Ernährung: in den letzten 7 Tagen nichts geloggt.")
        except Exception as e:  # noqa: BLE001
            lines.append(f"## Ernährung: nicht abrufbar ({e}).")

        # Cardio: last 7 days
        try:
            cardio = db.execute(
                select(CardioSession).where(
                    CardioSession.user_id == user_id, CardioSession.performed_at >= week_start
                ).order_by(CardioSession.performed_at)
            ).scalars().all()
            if cardio:
                total_min = sum(float(c.duration_min) for c in cardio)
                lines.append(f"## Cardio (letzte 7 Tage): {len(cardio)} Einheiten, zusammen {round(total_min)} min.")
            else:
                lines.append("## Cardio: in den letzten 7 Tagen nichts geloggt.")
        except Exception as e:  # noqa: BLE001
            lines.append(f"## Cardio: nicht abrufbar ({e}).")

        # Steps: per-day totals over the last 7 days (Apple Health, goal 10k)
        try:
            rows = db.execute(
                select(
                    func.date(DataPointSeries.recorded_at).label("day"),
                    func.sum(DataPointSeries.value).label("total"),
                )
                .join(SeriesTypeDefinition, SeriesTypeDefinition.id == DataPointSeries.series_type_definition_id)
                .where(
                    SeriesTypeDefinition.code == SeriesType.steps.value,
                    DataPointSeries.recorded_at >= week_start,
                )
                .group_by(func.date(DataPointSeries.recorded_at))
                .order_by(func.date(DataPointSeries.recorded_at))
            ).all()
            if rows:
                lines.append("## Schritte (letzte 7 Tage, Ziel 10.000/Tag)")
                for day, total in rows:
                    lines.append(f"{day}: {round(float(total))} Schritte")
            else:
                lines.append("## Schritte: keine Daten (in Apple Health / Health Auto Export Step Count exportieren).")
        except Exception as e:  # noqa: BLE001
            lines.append(f"## Schritte: nicht abrufbar ({e}).")

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

        return await self._call_claude(system, messages)

    async def brief(
        self,
        db: DbSession,
        user_id: UUID,
        kind: str,
        client_context: str,
    ) -> tuple[str, str]:
        """Generate a proactive briefing (morning | weekly). The client supplies
        its already-fetched metrics (recovery, sleep, weight, nutrition, phase);
        the backend adds training/supplement context and asks Claude for a tight,
        actionable brief. Returns (headline, body)."""
        if not self.is_enabled():
            raise ValueError("Coach ist nicht konfiguriert (ANTHROPIC_API_KEY fehlt).")

        backend_context = self._gather_context(db, user_id)
        instruction = _MORNING_INSTRUCTION if kind == "morning" else _WEEKLY_INSTRUCTION
        system = (
            f"{SYSTEM_PROMPT}\n\n{_BRIEF_FORMAT}\n\n"
            f"# Vom Client gemeldete Tagesdaten\n{client_context}\n\n"
            f"# Backend-Daten (Training/Supplements)\n{backend_context}"
        )
        messages = [{"role": "user", "content": instruction}]
        text = await self._call_claude(system, messages)
        return self._split_headline(text)

    @staticmethod
    def _split_headline(text: str) -> tuple[str, str]:
        """First non-empty line is the headline; the rest is the body."""
        lines = text.splitlines()
        headline = ""
        body_start = 0
        for i, ln in enumerate(lines):
            if ln.strip():
                headline = ln.strip().lstrip("#").strip().strip("*").strip()
                body_start = i + 1
                break
        body_lines = lines[body_start:]
        # Drop a leading markdown horizontal rule the model sometimes adds.
        while body_lines and (not body_lines[0].strip() or set(body_lines[0].strip()) <= {"-", "*", "_"}):
            body_lines.pop(0)
        body = "\n".join(body_lines).strip()
        return (headline or "Dein Briefing", body or text.strip())

    async def _call_claude(self, system: str, messages: list[dict]) -> str:
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

        parts = [b.get("text", "") for b in data.get("content", []) if b.get("type") == "text"]
        return "".join(parts).strip() or "(keine Antwort)"


coach_service = CoachService(log=getLogger(__name__))
