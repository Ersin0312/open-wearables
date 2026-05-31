"""Schemas for the 'Health Auto Export' iPhone app REST payload.

That app POSTs a JSON document shaped like:
    {
      "data": {
        "metrics": [
          {
            "name": "weight_body_mass",
            "units": "kg",
            "data": [{ "date": "2026-05-30 08:12:00 +0200", "qty": 82.4 }, ...]
          },
          { "name": "body_fat_percentage", "units": "%", "data": [...] }
        ]
      }
    }

We only care about a small set of body metrics; everything else is ignored.
Schema is intentionally permissive so a payload shape change never 500s the
ingest endpoint.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class HealthAutoExportDataPoint(BaseModel):
    model_config = ConfigDict(extra="ignore")

    date: str | None = None
    qty: float | None = None


class HealthAutoExportMetric(BaseModel):
    model_config = ConfigDict(extra="ignore")

    name: str
    units: str | None = None
    data: list[HealthAutoExportDataPoint] = []


class HealthAutoExportData(BaseModel):
    model_config = ConfigDict(extra="ignore")

    metrics: list[HealthAutoExportMetric] = []


class HealthAutoExportPayload(BaseModel):
    model_config = ConfigDict(extra="ignore")

    data: HealthAutoExportData = HealthAutoExportData()
