import { useMemo } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useIntakes, useSupplements } from '@/hooks/api/use-supplements';
import {
  addDays,
  dayCompletion,
  doseScaleColor,
  endOfDay,
  formatDateNumeric,
  formatDayLong,
  formatDayShort,
  isFutureDay,
  isSameDay,
  isToday,
  startOfWeek,
  weekDays,
} from '@/lib/supplements/shared';

type ViewMode = 'day' | 'week';

// Top navigator: ← date → with a Heute button and a Tag/Woche toggle.
export function DateNavigator({
  date,
  viewMode,
  onChangeDate,
  onChangeMode,
}: {
  date: Date;
  viewMode: ViewMode;
  onChangeDate: (d: Date) => void;
  onChangeMode: (m: ViewMode) => void;
}) {
  const step = viewMode === 'week' ? 7 : 1;
  const nextDisabled = viewMode === 'week'
    ? startOfWeek(addDays(date, 7)).getTime() > startOfWeek(new Date()).getTime()
    : isFutureDay(addDays(date, 1));

  const label =
    viewMode === 'week'
      ? `${formatDateNumeric(startOfWeek(date))} – ${formatDateNumeric(addDays(startOfWeek(date), 6))}`
      : formatDayLong(date);

  return (
    <div className="flex items-center justify-between gap-2">
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          aria-label="Zurück"
          onClick={() => onChangeDate(addDays(date, -step))}
        >
          <ChevronLeft className="h-5 w-5" />
        </Button>
        <div className="min-w-0">
          <div className="text-sm font-semibold capitalize truncate">{label}</div>
          {!isToday(date) && viewMode === 'day' && (
            <button
              type="button"
              onClick={() => onChangeDate(new Date())}
              className="text-xs text-muted-foreground hover:text-foreground underline-offset-2 hover:underline"
            >
              → heute
            </button>
          )}
        </div>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Vor"
          disabled={nextDisabled}
          onClick={() => onChangeDate(addDays(date, step))}
        >
          <ChevronRight className="h-5 w-5" />
        </Button>
      </div>

      {/* Tag / Woche segmented toggle */}
      <div className="flex rounded-md border border-border/50 overflow-hidden text-sm">
        {(['day', 'week'] as ViewMode[]).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => onChangeMode(m)}
            className={`px-3 py-1.5 transition-colors ${
              viewMode === m
                ? 'bg-[hsl(var(--success-muted)/0.15)] font-medium'
                : 'text-muted-foreground hover:bg-card/40'
            }`}
          >
            {m === 'day' ? 'Tag' : 'Woche'}
          </button>
        ))}
      </div>
    </div>
  );
}

// 7-day consistency strip (WHOOP-like): one ring per day showing completion %.
// Tapping a day jumps to it in day view.
export function WeekStrip({
  userId,
  anchorDate,
  onPickDay,
}: {
  userId: string;
  anchorDate: Date;
  onPickDay: (d: Date) => void;
}) {
  const days = useMemo(() => weekDays(anchorDate), [anchorDate]);
  const rangeStart = useMemo(() => startOfWeek(anchorDate), [anchorDate]);
  const rangeEnd = useMemo(() => endOfDay(addDays(rangeStart, 6)), [rangeStart]);

  const { data: intakes } = useIntakes(userId, {
    start_date: rangeStart.toISOString(),
    end_date: rangeEnd.toISOString(),
    limit: 500,
  });
  const { data: supplements } = useSupplements(userId);

  const perDay = useMemo(() => {
    return days.map((d) => {
      const dayIntakes = (intakes ?? []).filter((i) => isSameDay(new Date(i.taken_at), d));
      return {
        date: d,
        count: dayIntakes.length,
        pct: dayCompletion(dayIntakes, supplements ?? []),
      };
    });
  }, [days, intakes, supplements]);

  return (
    <div className="grid grid-cols-7 gap-1.5">
      {perDay.map(({ date, count, pct }) => {
        const future = isFutureDay(date);
        const ring = future ? 'transparent' : doseScaleColor(pct);
        return (
          <button
            key={date.toISOString()}
            type="button"
            disabled={future}
            onClick={() => onPickDay(date)}
            className={`flex flex-col items-center gap-1 rounded-md py-2 transition-colors ${
              future ? 'opacity-30 cursor-default' : 'hover:bg-card/40'
            } ${isToday(date) ? 'bg-card/30' : ''}`}
          >
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
              {formatDayShort(date)}
            </span>
            {/* Completion ring via conic-gradient */}
            <span
              className="relative flex h-9 w-9 items-center justify-center rounded-full"
              style={{
                background: future
                  ? 'transparent'
                  : `conic-gradient(${ring} ${Math.min(pct, 100) * 3.6}deg, hsl(var(--card)) 0deg)`,
              }}
            >
              <span className="flex h-7 w-7 items-center justify-center rounded-full bg-background text-[10px] font-medium tabular-nums">
                {date.getDate()}
              </span>
            </span>
            <span className="text-[10px] text-muted-foreground tabular-nums">
              {count > 0 ? `${pct}%` : '–'}
            </span>
          </button>
        );
      })}
    </div>
  );
}

export type { ViewMode };
