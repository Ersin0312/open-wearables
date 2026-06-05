"""Unofficial Renpho cloud sync.

Renpho has no public API. This talks to their legacy mobile backend
(renpho.qnclouds.com) the same way the app does: RSA-encrypt the password with
a hardcoded public key, sign in for a session token, then pull measurements.

It exists to fetch the body-composition metrics Apple Health cannot represent
(visceral fat, body water %, bone mass, BMR, protein %). Fragile by nature — if
Renpho changes their backend this breaks, and that's expected. Credentials live
only in backend settings (.env), never in the client or the repo.
"""

from __future__ import annotations

import base64
import time
from datetime import datetime, timezone
from logging import Logger, getLogger
from uuid import UUID

import httpx
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import load_pem_public_key

from app.config import settings
from app.database import DbSession
from app.models import BodyScan

# Public key shipped in the Renpho app — used to encrypt the password at login.
# A public key is not a secret; it only lets us talk to their auth endpoint.
_PUBLIC_KEY = """-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC+25I2upukpfQ7rIaaTZtVE744
u2zV+HaagrUhDOTq8fMVf9yFQvEZh2/HKxFudUxP0dXUa8F6X4XmWumHdQnum3zm
Jr04fz2b2WCcN0ta/rbF2nYAnMVAk2OJVZAMudOiMWhcxV1nNJiKgTNNr13de0EQ
IiOL2CUBzu+HmIfUbQIDAQAB
-----END PUBLIC KEY-----"""

_AUTH_URL = "https://renpho.qnclouds.com/api/v3/users/sign_in.json?app_id=Renpho"
_MEASUREMENTS_URL = "https://renpho.qnclouds.com/api/v2/measurements/list.json"

# Renpho measurement field → our BodyScan column.
_FIELD_MAP = {
    "weight": "weight_kg",
    "bmi": "bmi",
    "bodyfat": "body_fat_percent",
    "muscle": "muscle_mass_kg",
    "water": "body_water_percent",
    "bone": "bone_mass_kg",
    "bmr": "bmr_kcal",
    "visfat": "visceral_fat",
    "subfat": "subcutaneous_fat_percent",
    "protein": "protein_percent",
}


class RenphoService:
    def __init__(self, log: Logger):
        self.logger = log

    def is_enabled(self) -> bool:
        return bool(settings.RENPHO_EMAIL) and settings.RENPHO_PASSWORD is not None

    @staticmethod
    def _encrypt_password(password: str) -> str:
        key = load_pem_public_key(_PUBLIC_KEY.encode())
        encrypted = key.encrypt(password.encode("utf-8"), padding.PKCS1v15())
        return base64.b64encode(encrypted).decode("utf-8")

    async def _sign_in(self, client: httpx.AsyncClient) -> tuple[str, str]:
        """Returns (session_token, user_id)."""
        enc = self._encrypt_password(settings.RENPHO_PASSWORD.get_secret_value())
        body = {"secure_flag": "1", "email": settings.RENPHO_EMAIL, "password": enc}
        resp = await client.post(_AUTH_URL, json=body)
        if resp.status_code != 200:
            raise ValueError(f"Renpho-Login fehlgeschlagen (HTTP {resp.status_code}).")
        data = resp.json()
        token = data.get("terminal_user_session_key")
        if not token:
            raise ValueError("Renpho-Login: kein Session-Token (Zugangsdaten falsch?).")
        return token, str(data.get("id", ""))

    async def fetch_latest_measurements(self) -> list[dict]:
        """Sign in and return the raw measurement rows (newest first)."""
        if not self.is_enabled():
            raise ValueError("Renpho nicht konfiguriert (RENPHO_EMAIL/RENPHO_PASSWORD fehlen).")
        async with httpx.AsyncClient(timeout=30) as client:
            token, user_id = await self._sign_in(client)
            ts = int(time.time())
            url = (
                f"{_MEASUREMENTS_URL}?user_id={user_id}&last_at={ts}"
                f"&locale=en&app_id=Renpho&terminal_user_session_key={token}"
            )
            resp = await client.get(url)
            if resp.status_code != 200:
                raise ValueError(f"Renpho-Messdaten nicht abrufbar (HTTP {resp.status_code}).")
            data = resp.json()
            return data.get("last_ary") or []

    def sync(self, db: DbSession, user_id: UUID, rows: list[dict]) -> int:
        """Upsert measurement rows into body_scan. Dedupe by measured_at.
        Returns the number of new scans stored."""
        existing = {
            s.measured_at
            for s in db.query(BodyScan).filter(BodyScan.user_id == user_id).all()
        }
        new_count = 0
        for row in rows:
            ts = row.get("time_stamp") or row.get("created_at")
            if ts is None:
                continue
            measured_at = datetime.fromtimestamp(int(ts), tz=timezone.utc).replace(tzinfo=None)
            if measured_at in existing:
                continue
            scan = BodyScan(user_id=user_id, measured_at=measured_at, source="renpho")
            for field, column in _FIELD_MAP.items():
                value = row.get(field)
                if value is not None:
                    try:
                        setattr(scan, column, float(value))
                    except (TypeError, ValueError):
                        pass
            db.add(scan)
            existing.add(measured_at)
            new_count += 1
        db.commit()
        return new_count


renpho_service = RenphoService(log=getLogger(__name__))
