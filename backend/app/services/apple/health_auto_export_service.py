"""Ingest body metrics from the 'Health Auto Export' iPhone app.

Maps the app's metric names to our SeriesType timeseries and writes them via
the same bulk_create_samples path WHOOP/Apple-XML use, so data sources and
webhooks are handled consistently. Idempotency is provided downstream by the
data-point upsert on (data_source, series_type, recorded_at).
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation
from logging import Logger, getLogger
from uuid import UUID, uuid4

from dateutil import parser as date_parser

from app.database import DbSession
from app.schemas.enums import SeriesType
from app.schemas.model_crud.activities import TimeSeriesSampleCreate
from app.schemas.providers.apple.health_auto_export import HealthAutoExportPayload
from app.services.timeseries_service import timeseries_service

# Health Auto Export metric name (lowercased) → our SeriesType.
# Names can vary slightly between app versions, so we match by substring.
_METRIC_MATCHERS: list[tuple[tuple[str, ...], SeriesType]] = [
    (("weight_body_mass", "body_mass", "weight"), SeriesType.weight),
    (("body_fat_percentage", "body_fat"), SeriesType.body_fat_percentage),
]

# Source string — must contain "apple" so the provider resolves to APPLE.
_SOURCE = "apple_health_auto_export"


class HealthAutoExportService:
    def __init__(self, log: Logger):
        self.logger = log

    @staticmethod
    def _match_series_type(metric_name: str) -> SeriesType | None:
        name = metric_name.lower()
        for needles, series_type in _METRIC_MATCHERS:
            if any(n in name for n in needles):
                return series_type
        return None

    @staticmethod
    def _normalize_body_fat(value: Decimal) -> Decimal:
        # Some exports send body fat as a fraction (0.18), others as percent (18).
        # Store consistently as percent.
        return value * 100 if value <= 1 else value

    def ingest(
        self,
        db: DbSession,
        user_id: UUID,
        payload: HealthAutoExportPayload,
    ) -> dict[str, int]:
        samples: list[TimeSeriesSampleCreate] = []
        counts: dict[str, int] = {}

        for metric in payload.data.metrics:
            series_type = self._match_series_type(metric.name)
            if series_type is None:
                continue

            for point in metric.data:
                if point.qty is None or point.date is None:
                    continue
                try:
                    value = Decimal(str(point.qty))
                except (InvalidOperation, ValueError):
                    continue
                if series_type == SeriesType.body_fat_percentage:
                    value = self._normalize_body_fat(value)
                try:
                    recorded_at = date_parser.parse(point.date)
                except (ValueError, OverflowError):
                    continue

                samples.append(
                    TimeSeriesSampleCreate(
                        id=uuid4(),
                        user_id=user_id,
                        source=_SOURCE,
                        recorded_at=recorded_at,
                        value=value,
                        series_type=series_type,
                    )
                )
                counts[series_type.value] = counts.get(series_type.value, 0) + 1

        if samples:
            timeseries_service.bulk_create_samples(db, samples)
            db.commit()

        self.logger.debug(f"Health Auto Export ingest for {user_id}: {counts}")
        return counts


health_auto_export_service = HealthAutoExportService(log=getLogger(__name__))
