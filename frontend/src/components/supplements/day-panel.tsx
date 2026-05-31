import { useMemo, useState } from 'react';
import { Check, Pencil, Pill, Trash2, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { useIntakes, useSupplements, useUpdateIntake, useDeleteIntake } from '@/hooks/api/use-supplements';
import {
  computeDailyProgress,
  doseScaleColor,
  endOfDay,
  formatTime,
  startOfDay,
  type DailyProgressRow,
} from '@/lib/supplements/shared';

// Per-NEM progress toward the recommended daily dose, coloured by the scale.
function DailyDoseBar({ name, unit, total, rec, pct }: DailyProgressRow) {
  const color = doseScaleColor(pct);
  const width = Math.min(pct, 100);
  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-xs">
        <span className="font-medium truncate pr-2">{name}</span>
        <span className="text-muted-foreground shrink-0 tabular-nums">
          {total} / {rec} {unit}
          <span className="font-medium ml-1" style={{ color }}>· {pct}%</span>
        </span>
      </div>
      <div className="h-2 w-full rounded-full bg-card/60 overflow-hidden">
        <div
          className="h-full rounded-full transition-all"
          style={{ width: `${width}%`, backgroundColor: color }}
        />
      </div>
    </div>
  );
}

// One logged-intake row with inline dose editing (pencil) + delete (trash).
function IntakeRow({
  name,
  dose,
  unit,
  takenAt,
  viaStack,
  onSave,
  onDelete,
}: {
  name: string;
  dose: number;
  unit: string;
  takenAt: string;
  viaStack: boolean;
  onSave: (dose: number) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState(String(dose));

  const startEdit = () => {
    setValue(String(dose));
    setEditing(true);
  };
  const save = () => {
    const n = parseFloat(value);
    if (!isNaN(n)) onSave(n);
    setEditing(false);
  };

  return (
    <div className="flex items-center justify-between text-sm px-3 py-2 rounded bg-card/50 border border-border/30">
      <div className="flex items-center gap-3 min-w-0">
        <Pill className="h-4 w-4 text-muted-foreground shrink-0" />
        <div className="min-w-0">
          <div className="font-medium truncate">{name}</div>
          {editing ? (
            <div className="flex items-center gap-1.5 mt-1">
              <Input
                type="number"
                inputMode="decimal"
                step="0.01"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    save();
                  } else if (e.key === 'Escape') {
                    e.preventDefault();
                    setEditing(false);
                  }
                }}
                className="h-8 w-20 text-sm"
                aria-label={`Dosis für ${name}`}
                autoFocus
              />
              <span className="text-xs text-muted-foreground">{unit}</span>
            </div>
          ) : (
            <div className="text-xs text-muted-foreground">
              {dose} {unit} · {formatTime(takenAt)}
              {viaStack ? ' · via Stack' : ''}
            </div>
          )}
        </div>
      </div>
      <div className="flex items-center gap-0.5 shrink-0">
        {editing ? (
          <>
            <Button variant="ghost" size="sm" onClick={save} aria-label="Speichern">
              <Check className="h-3.5 w-3.5 text-[hsl(var(--success-muted))]" />
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setEditing(false)} aria-label="Abbrechen">
              <X className="h-3.5 w-3.5" />
            </Button>
          </>
        ) : (
          <>
            <Button variant="ghost" size="sm" onClick={startEdit} aria-label="Dosis bearbeiten">
              <Pencil className="h-3.5 w-3.5" />
            </Button>
            <Button variant="ghost" size="sm" onClick={onDelete} aria-label="Eintrag löschen">
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </>
        )}
      </div>
    </div>
  );
}

// The intakes + daily-dose progress for ONE calendar day.
export function DayPanel({ userId, date }: { userId: string; date: Date }) {
  const range = useMemo(
    () => ({ start: startOfDay(date).toISOString(), end: endOfDay(date).toISOString() }),
    [date],
  );

  const { data: intakes, isLoading } = useIntakes(userId, {
    start_date: range.start,
    end_date: range.end,
    limit: 500,
  });
  const { data: supplements } = useSupplements(userId);
  const updateIntake = useUpdateIntake(userId);
  const deleteIntake = useDeleteIntake(userId);

  const dailyProgress = useMemo(
    () => computeDailyProgress(intakes ?? [], supplements ?? []),
    [intakes, supplements],
  );

  if (isLoading) {
    return (
      <Card className="p-5">
        <Skeleton className="h-24 w-full" />
      </Card>
    );
  }

  if (!intakes || intakes.length === 0) {
    return (
      <Card className="p-5 text-center text-sm text-muted-foreground">
        Keine Einträge an diesem Tag.
      </Card>
    );
  }

  return (
    <Card className="p-5 space-y-4">
      <h2 className="text-lg font-semibold">Geloggt ({intakes.length})</h2>

      {dailyProgress.length > 0 && (
        <div className="space-y-3">
          <h3 className="text-sm font-medium text-muted-foreground">Tagesdosis</h3>
          {dailyProgress.map((d) => (
            <DailyDoseBar key={d.sid} {...d} />
          ))}
        </div>
      )}

      <div className="space-y-2">
        {intakes.map((intake) => (
          <IntakeRow
            key={intake.id}
            name={supplements?.find((s) => s.id === intake.supplement_id)?.name ?? 'Unbekannt'}
            dose={parseFloat(intake.dose)}
            unit={intake.unit}
            takenAt={intake.taken_at}
            viaStack={Boolean(intake.stack_id)}
            onSave={(dose) => updateIntake.mutate({ intakeId: intake.id, payload: { dose } })}
            onDelete={() => deleteIntake.mutate(intake.id)}
          />
        ))}
      </div>
    </Card>
  );
}
