#!/usr/bin/env python3
"""Seed the supplement library with 18 common bodybuilding / health basics.

Idempotent: skips entries whose `name` already exists. Run via:
    docker compose exec app uv run python scripts/init/seed_supplements.py
"""

from decimal import Decimal
from uuid import uuid4

from app.database import SessionLocal
from app.models import Supplement


# `recommended_daily_dose` = orientation value for the "% of daily dose reached
# today" display (DGE / EFSA upper-safe / common daily target — editable later).
# Left as None for protein/amino acids where a fixed micronutrient daily dose
# does not apply (target scales with bodyweight/goals, not a fixed amount).
SEED_SUPPLEMENTS: list[dict] = [
    # Protein
    {"name": "Whey Protein", "category": "protein", "default_dose": Decimal("30"), "default_unit": "g",
     "recommended_daily_dose": None,
     "notes": "Schnelles Protein, ideal post-workout"},
    {"name": "Casein Protein", "category": "protein", "default_dose": Decimal("30"), "default_unit": "g",
     "recommended_daily_dose": None,
     "notes": "Langsames Protein, abends/vor dem Schlafen"},

    # Performance / Strength
    {"name": "Creatin Monohydrat", "category": "performance", "default_dose": Decimal("5"), "default_unit": "g",
     "recommended_daily_dose": Decimal("5"),
     "notes": "Klassiker für Kraft + Muskelaufbau, täglich konstant"},
    {"name": "Beta-Alanin", "category": "performance", "default_dose": Decimal("3.2"), "default_unit": "g",
     "recommended_daily_dose": Decimal("3.2"),
     "notes": "Puffert Laktat, hilft bei langen Sätzen (8-15 Reps)"},
    {"name": "Citrullin Malat", "category": "performance", "default_dose": Decimal("8"), "default_unit": "g",
     "recommended_daily_dose": Decimal("8"),
     "notes": "Pre-workout, Pump + Ausdauer"},
    {"name": "Koffein", "category": "performance", "default_dose": Decimal("200"), "default_unit": "mg",
     "recommended_daily_dose": Decimal("400"),
     "notes": "Pre-workout Fokus / Energie (EFSA: max 400 mg/Tag)"},

    # Recovery
    {"name": "EAA / BCAA", "category": "recovery", "default_dose": Decimal("10"), "default_unit": "g",
     "recommended_daily_dose": None,
     "notes": "Aminosäuren intra- oder post-workout"},
    {"name": "Kollagen", "category": "recovery", "default_dose": Decimal("10"), "default_unit": "g",
     "recommended_daily_dose": Decimal("10"),
     "notes": "Gelenke + Bindegewebe"},
    {"name": "Glutamin", "category": "recovery", "default_dose": Decimal("5"), "default_unit": "g",
     "recommended_daily_dose": Decimal("5"),
     "notes": "Darmgesundheit + Recovery"},

    # Fatty acids
    {"name": "Omega-3 (Fischöl)", "category": "fatty_acid", "default_dose": Decimal("2"), "default_unit": "g",
     "recommended_daily_dose": Decimal("2"),
     "notes": "EPA+DHA für Entzündung + Herz"},

    # Vitamins
    {"name": "Vitamin D3 + K2", "category": "vitamin", "default_dose": Decimal("5000"), "default_unit": "iu",
     "recommended_daily_dose": Decimal("4000"),
     "notes": "Knochen + Immunsystem + Testosteron (EFSA UL: 4000 IE/Tag)"},
    {"name": "Vitamin B-Komplex", "category": "vitamin", "default_dose": Decimal("1"), "default_unit": "tablet",
     "recommended_daily_dose": Decimal("1"),
     "notes": "Energiestoffwechsel"},
    {"name": "Vitamin C", "category": "vitamin", "default_dose": Decimal("1000"), "default_unit": "mg",
     "recommended_daily_dose": Decimal("1000"),
     "notes": "Antioxidans + Kollagensynthese (DGE: 110 mg, supplementär oft 1000 mg)"},
    {"name": "Multivitamin", "category": "vitamin", "default_dose": Decimal("1"), "default_unit": "tablet",
     "recommended_daily_dose": Decimal("1"),
     "notes": "Basis-Mikronährstoffe"},

    # Minerals
    {"name": "Magnesium (Glycinat)", "category": "mineral", "default_dose": Decimal("400"), "default_unit": "mg",
     "recommended_daily_dose": Decimal("400"),
     "notes": "Muskelentspannung, Schlaf, abends (DGE: ~350-400 mg)"},
    {"name": "Zink", "category": "mineral", "default_dose": Decimal("25"), "default_unit": "mg",
     "recommended_daily_dose": Decimal("25"),
     "notes": "Immunsystem + Testosteron (UL: ~25 mg/Tag)"},

    # Other
    {"name": "Ashwagandha", "category": "nootropic", "default_dose": Decimal("600"), "default_unit": "mg",
     "recommended_daily_dose": Decimal("600"),
     "notes": "Adaptogen, reduziert Cortisol, Stress + Schlaf"},
    {"name": "Curcumin", "category": "other", "default_dose": Decimal("500"), "default_unit": "mg",
     "recommended_daily_dose": Decimal("500"),
     "notes": "Antientzündlich, Gelenke"},
    {"name": "Probiotika", "category": "other", "default_dose": Decimal("1"), "default_unit": "capsule",
     "recommended_daily_dose": Decimal("1"),
     "notes": "Darmgesundheit"},
]


def seed_supplements() -> None:
    inserted = 0
    skipped = 0
    backfilled = 0
    with SessionLocal() as db:
        existing = {row.name: row for row in db.query(Supplement).all()}
        for entry in SEED_SUPPLEMENTS:
            existing_row = existing.get(entry["name"])
            if existing_row is not None:
                skipped += 1
                # Backfill the recommended daily dose on already-seeded rows that
                # predate this column (only when still empty — never overwrite a
                # value the user may have edited).
                if (
                    existing_row.is_seeded
                    and existing_row.recommended_daily_dose is None
                    and entry.get("recommended_daily_dose") is not None
                ):
                    existing_row.recommended_daily_dose = entry["recommended_daily_dose"]
                    backfilled += 1
                continue
            supplement = Supplement(
                id=uuid4(),
                name=entry["name"],
                category=entry["category"],
                default_dose=entry["default_dose"],
                default_unit=entry["default_unit"],
                recommended_daily_dose=entry.get("recommended_daily_dose"),
                notes=entry.get("notes"),
                is_seeded=True,
                created_by_user_id=None,
            )
            db.add(supplement)
            inserted += 1
        db.commit()

    print(
        f"✓ Supplement library seeded: {inserted} inserted, {skipped} already present, "
        f"{backfilled} daily-dose backfilled ({len(SEED_SUPPLEMENTS)} total)"
    )


if __name__ == "__main__":
    seed_supplements()
