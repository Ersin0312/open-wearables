// Shared constants + helpers for the Supplements feature.
// Extracted so the route file and the day/week view components share one source.
import type { Supplement, SupplementIntake, Unit } from '../api/services/supplements.service';

export const CATEGORY_LABELS: Record<string, string> = {
  protein: 'Protein',
  performance: 'Performance',
  recovery: 'Recovery',
  fatty_acid: 'Omega/Fettsäuren',
  vitamin: 'Vitamine',
  mineral: 'Mineralien',
  amino_acid: 'Aminosäuren',
  nootropic: 'Nootropika',
  other: 'Sonstiges',
};

export const CATEGORY_ORDER = [
  'protein', 'performance', 'recovery', 'fatty_acid',
  'vitamin', 'mineral', 'amino_acid', 'nootropic', 'other',
];

export const UNIT_OPTIONS: { value: Unit; label: string }[] = [
  { value: 'mg', label: 'mg' },
  { value: 'g', label: 'g' },
  { value: 'ml', label: 'ml' },
  { value: 'iu', label: 'IE (i.U.)' },
  { value: 'capsule', label: 'Kapsel' },
  { value: 'tablet', label: 'Tablette' },
  { value: 'scoop', label: 'Scoop' },
  { value: 'drop', label: 'Tropfen' },
];

// One row of the stack editor: dose kept as string for controlled input,
// parsed to a number only at submit time.
export interface StackItemForm {
  supplement_id: string;
  dose: string;
  unit: string;
}

export function toFormItem(s: Supplement): StackItemForm {
  return {
    supplement_id: s.id,
    dose: s.default_dose ? String(parseFloat(s.default_dose)) : '',
    unit: s.default_unit,
  };
}

// ---- Daily-dose colour scale (user spec) ----
// 0% dunkelrot · >0–33 hellrot · >33–66 hellgrün · >66–<100 grün · ≥100 dunkelgrün
export function doseScaleColor(pct: number): string {
  if (pct <= 0) return '#7f1d1d';
  if (pct <= 33) return '#f87171';
  if (pct <= 66) return '#86efac';
  if (pct < 100) return '#22c55e';
  return '#15803d';
}

// ---- Date helpers (local time, calendar-day scoped) ----

export function startOfDay(d: Date): Date {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

export function endOfDay(d: Date): Date {
  const x = new Date(d);
  x.setHours(23, 59, 59, 999);
  return x;
}

export function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

export function isSameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

export function isToday(d: Date): boolean {
  return isSameDay(d, new Date());
}

export function isFutureDay(d: Date): boolean {
  return startOfDay(d).getTime() > startOfDay(new Date()).getTime();
}

// Monday-based week start (DE convention).
export function startOfWeek(d: Date): Date {
  const x = startOfDay(d);
  const day = (x.getDay() + 6) % 7; // Mon=0 … Sun=6
  return addDays(x, -day);
}

export function weekDays(anchor: Date): Date[] {
  const start = startOfWeek(anchor);
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}

export function formatDayLong(d: Date): string {
  return d.toLocaleDateString('de-DE', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
  });
}

export function formatDayShort(d: Date): string {
  return d.toLocaleDateString('de-DE', { weekday: 'short' });
}

export function formatDateNumeric(d: Date): string {
  return d.toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit' });
}

export function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}

// ---- Daily-dose aggregation for a set of intakes ----
export interface DailyProgressRow {
  sid: string;
  name: string;
  unit: string;
  total: number;
  rec: number;
  pct: number;
}

export function computeDailyProgress(
  intakes: SupplementIntake[],
  supplements: Supplement[],
): DailyProgressRow[] {
  const totals: Record<string, number> = {};
  intakes.forEach((i) => {
    totals[i.supplement_id] = (totals[i.supplement_id] ?? 0) + parseFloat(i.dose);
  });
  return Object.entries(totals)
    .map(([sid, total]) => {
      const sup = supplements.find((s) => s.id === sid);
      const rec = sup?.recommended_daily_dose ? parseFloat(sup.recommended_daily_dose) : 0;
      return {
        sid,
        name: sup?.name ?? 'Unbekannt',
        unit: sup?.default_unit ?? '',
        total,
        rec,
        pct: rec > 0 ? Math.round((total / rec) * 100) : 0,
      };
    })
    .filter((x) => x.rec > 0)
    .sort((a, b) => a.name.localeCompare(b.name));
}

// Day-level completion for the week strip: average % across NEMs with a daily
// dose that were taken that day, capped at 100. Returns 0 when nothing logged.
export function dayCompletion(
  intakes: SupplementIntake[],
  supplements: Supplement[],
): number {
  const rows = computeDailyProgress(intakes, supplements);
  if (rows.length === 0) return 0;
  const avg = rows.reduce((sum, r) => sum + Math.min(r.pct, 100), 0) / rows.length;
  return Math.round(avg);
}
