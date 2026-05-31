import { useMemo, useState } from 'react';
import { format } from 'date-fns';
import { Line, LineChart, CartesianGrid, XAxis, YAxis } from 'recharts';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from '@/components/ui/chart';
import { useTimeSeries } from '@/hooks/api/use-health';

type RangeDays = 30 | 90 | 365;

const RANGE_LABELS: Record<RangeDays, string> = {
  30: '30 Tage',
  90: '90 Tage',
  365: '1 Jahr',
};

// One body metric plotted over time, pulled from the existing timeseries
// pipeline (Apple Health import → series_type). No new storage needed.
export function BodyTrend({
  userId,
  seriesType,
  title,
  unit,
  color,
  domain,
}: {
  userId: string;
  seriesType: 'weight' | 'body_fat_percentage';
  title: string;
  unit: string;
  color: string;
  domain?: [number | 'auto', number | 'auto'];
}) {
  const [range, setRange] = useState<RangeDays>(90);

  // start/end as ISO; recomputed when range changes. No Date.now in module scope.
  const { startTime, endTime } = useMemo(() => {
    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - range);
    return { startTime: start.toISOString(), endTime: end.toISOString() };
  }, [range]);

  const { data, isLoading } = useTimeSeries(userId, {
    start_time: startTime,
    end_time: endTime,
    types: [seriesType],
    resolution: '1hour',
    limit: 1000,
  });

  const chartData = useMemo(() => {
    const samples = data?.data ?? [];
    return samples
      .filter((s) => s.type === seriesType && typeof s.value === 'number')
      .map((s) => ({
        ts: new Date(s.timestamp).getTime(),
        date: format(new Date(s.timestamp), 'dd.MM'),
        value: s.value,
      }))
      .sort((a, b) => a.ts - b.ts);
  }, [data, seriesType]);

  const latest = chartData.length > 0 ? chartData[chartData.length - 1].value : null;
  const first = chartData.length > 0 ? chartData[0].value : null;
  const delta = latest != null && first != null ? latest - first : null;

  return (
    <Card className="p-5 space-y-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-semibold">{title}</h3>
          <div className="flex items-baseline gap-2 mt-1">
            <span className="text-2xl font-semibold tabular-nums">
              {latest != null ? `${latest.toFixed(1)} ${unit}` : '–'}
            </span>
            {delta != null && (
              <span
                className={`text-xs tabular-nums ${
                  delta < 0 ? 'text-[hsl(var(--success-muted))]' : delta > 0 ? 'text-[hsl(var(--warning-muted))]' : 'text-muted-foreground'
                }`}
              >
                {delta > 0 ? '+' : ''}
                {delta.toFixed(1)} {unit} · {RANGE_LABELS[range]}
              </span>
            )}
          </div>
        </div>
        <div className="flex rounded-md border border-border/50 overflow-hidden text-xs shrink-0">
          {(Object.keys(RANGE_LABELS) as unknown as RangeDays[]).map((r) => {
            const rd = Number(r) as RangeDays;
            return (
              <button
                key={rd}
                type="button"
                onClick={() => setRange(rd)}
                className={`px-2.5 py-1 transition-colors ${
                  range === rd
                    ? 'bg-[hsl(var(--success-muted)/0.15)] font-medium'
                    : 'text-muted-foreground hover:bg-card/40'
                }`}
              >
                {RANGE_LABELS[rd]}
              </button>
            );
          })}
        </div>
      </div>

      {isLoading ? (
        <Skeleton className="h-[200px] w-full" />
      ) : chartData.length === 0 ? (
        <div className="h-[200px] flex items-center justify-center text-center text-sm text-muted-foreground">
          Keine {title}-Daten in diesem Zeitraum.
          <br />
          Importiere Apple-Health-Daten unter Einstellungen.
        </div>
      ) : (
        <ChartContainer
          config={{ value: { label: title, color } }}
          className="h-[200px] w-full"
        >
          <LineChart accessibilityLayer data={chartData}>
            <CartesianGrid vertical={false} strokeDasharray="3 3" />
            <XAxis
              dataKey="date"
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              interval="preserveStartEnd"
              tick={{ fill: '#71717a', fontSize: 11 }}
            />
            <YAxis
              tickLine={false}
              axisLine={false}
              tickMargin={8}
              tick={{ fill: '#71717a', fontSize: 11 }}
              domain={domain ?? ['auto', 'auto']}
              width={40}
              tickFormatter={(v) => `${v}`}
            />
            <ChartTooltip
              cursor={false}
              content={
                <ChartTooltipContent
                  formatter={(value) => `${Number(value).toFixed(1)} ${unit}`}
                />
              }
            />
            <Line
              dataKey="value"
              type="monotone"
              stroke={color}
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 4, fill: color }}
              connectNulls
            />
          </LineChart>
        </ChartContainer>
      )}
    </Card>
  );
}
