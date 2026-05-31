import { createFileRoute } from '@tanstack/react-router';
import { Info } from 'lucide-react';
import { PageHeader } from '@/components/ui/page-header';
import { Skeleton } from '@/components/ui/skeleton';
import { useUsers } from '@/hooks/api/use-users';
import { BodySection } from '@/components/user/body-section';
import { BodyTrend } from '@/components/body/body-trend';

export const Route = createFileRoute('/_authenticated/body')({
  component: BodyPage,
});

function BodyPage() {
  const { data: users, isLoading: usersLoading } = useUsers({ limit: 1 });
  const userId = users?.items?.[0]?.id ?? '';

  if (usersLoading || !userId) {
    return (
      <div className="p-4 md:p-8 space-y-4">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  return (
    <div className="p-4 md:p-8 max-w-3xl mx-auto space-y-6">
      <PageHeader title="Körperzusammensetzung" description="Gewicht & Körperfett im Verlauf" />

      {/* Current snapshot — reuses the existing body-summary card */}
      <BodySection userId={userId} />

      {/* Trends from the timeseries pipeline (Apple Health import) */}
      <BodyTrend
        userId={userId}
        seriesType="weight"
        title="Gewicht"
        unit="kg"
        color="#60a5fa"
      />
      <BodyTrend
        userId={userId}
        seriesType="body_fat_percentage"
        title="Körperfett"
        unit="%"
        color="#fb923c"
        domain={[0, 'auto']}
      />

      <div className="flex items-start gap-2 rounded-md border border-border/40 bg-card/30 px-4 py-3 text-xs text-muted-foreground">
        <Info className="h-4 w-4 shrink-0 mt-0.5" />
        <p>
          Gewicht und Körperfett kommen aus deiner Körperwaage über Apple Health.
          Apple bietet keinen Live-Abruf — exportiere die Health-Daten auf dem iPhone
          (Health-App → Profil → „Alle Daten exportieren") und importiere die Datei
          unter Einstellungen. Danach erscheinen die Werte hier automatisch.
        </p>
      </div>
    </div>
  );
}
