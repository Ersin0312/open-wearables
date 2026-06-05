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

# --- Proactive briefing prompts ---

_BRIEF_FORMAT = """# Ausgabeformat (strikt einhalten)
Zeile 1: EINE prägnante Headline (max. 12 Wörter, kein Markdown, keine Aufzählung).
Danach eine Leerzeile, dann der Body. Schreib in klaren, vollständigen Sätzen mit
rotem Faden — keine kryptischen Stichworte. Markdown-Überschriften (## ) und **fett**
sind erlaubt, um zu gliedern. Beziehe IMMER die konkreten Zahlen aus den Daten ein."""

_MORNING_INSTRUCTION = """Erstelle einen ausführlichen, durchdachten Morgenbrief für heute.

Beginne mit einem kurzen Absatz **## Lagebild**, der ALLE heute verfügbaren Zahlen
zusammenfasst und einordnet: Recovery-Score, HRV, Ruhepuls, Schlafdauer, aktuelles
Gewicht und Abstand zum Phasenziel, Ernährungsstand (kcal/Protein bisher vs. Ziel),
ob schon trainiert/Supplements geloggt wurden, Tag/Phase im Plan. Verknüpfe die Werte
(z. B. „HRV X bei Schlaf Y bedeutet …"), statt sie nur aufzulisten.

Danach detaillierte Empfehlungen, jeweils als eigener Absatz mit Überschrift und in
ganzen Sätzen begründet:
**## Training** – heutige Einheit, Voll- oder Teillast je nach Recovery, konkrete
Sätze/Intensität, ggf. Bezug zur letzten gleichen Einheit.
**## Ernährung** – wie kcal/Protein heute realistisch erreicht werden (konkrete
Lebensmittel/Mengen), Timing rund ums Training.
**## Supplements & Recovery** – was heute sinnvoll ist (Timing), Schlaf-/Stress-Hinweise.

Schließe mit **## Wichtigster Hebel heute** (1-2 Sätze). Wenn Daten fehlen, benenne
es offen statt zu raten."""

_WEEKLY_INSTRUCTION = """Schreibe ein ausführliches Wochenreview der letzten 7 Tage in
vollständigen, gut lesbaren Sätzen mit klarem rotem Faden — KEINE knappen Stichpunkte,
sondern zusammenhängende Absätze, die aufeinander aufbauen.

Beginne mit **## Ist-Analyse**: Schildere in mehreren Sätzen, wo der Nutzer aktuell
steht — Gewichtstrend der Woche und Abstand/Pace zum Phasenziel (mit Zahlen belegt),
Trainingsfrequenz und -volumen, Recovery-Verlauf, Ernährungs-Adherence (kcal/Protein).
Ordne ein, ob das zusammen ein stimmiges Bild ergibt oder wo es hakt.

Leite daraus **## Bewertung** ab: Was lief diese Woche gut und warum, was bremst den
Fortschritt — ehrlich und begründet, in Prosa.

Dann **konkrete, schrittweise Empfehlungen** für die kommende Woche, jeweils als eigener
Absatz in ganzen Sätzen:
**## Training** – was beibehalten, was anpassen (Frequenz, Progression, Geräte).
**## Ernährung** – kcal/Protein-Justierung mit Begründung am Gewichtstrend.
**## Supplements** – was sinnvoll ist/fehlt.
**## Recovery & Schlaf** – konkrete Stellschrauben.

Schließe mit **## Fokus der Woche**: 1-2 messbare Vorsätze, die den größten Hebel haben.
Sei ehrlich: wenn Gewicht stagniert oder Training ausfiel, benenne es klar und konstruktiv."""


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
