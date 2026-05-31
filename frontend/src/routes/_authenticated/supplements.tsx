import { createFileRoute } from '@tanstack/react-router';
import { useState } from 'react';
import { BookOpen, Layers, Plus } from 'lucide-react';
import { PageHeader } from '@/components/ui/page-header';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { useUsers } from '@/hooks/api/use-users';
import { DateNavigator, WeekStrip, type ViewMode } from '@/components/supplements/date-navigator';
import { DayPanel } from '@/components/supplements/day-panel';
import { NemLibrarySection } from '@/components/supplements/nem-library';
import {
  StacksSection,
  SingleIntakeForm,
  CreateSupplementDialog,
} from '@/components/supplements/logging-section';
import { isToday } from '@/lib/supplements/shared';

export const Route = createFileRoute('/_authenticated/supplements')({
  component: SupplementsPage,
});

function SupplementsPage() {
  const { data: users, isLoading: usersLoading } = useUsers({ limit: 1 });
  const userId = users?.items?.[0]?.id ?? '';

  const [date, setDate] = useState<Date>(() => new Date());
  const [viewMode, setViewMode] = useState<ViewMode>('day');

  // The three header tools open as dialogs so they aren't duplicated per day.
  const [stacksOpen, setStacksOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [libraryOpen, setLibraryOpen] = useState(false);

  if (usersLoading || !userId) {
    return (
      <div className="p-4 md:p-8 space-y-4">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="h-32 w-full" />
      </div>
    );
  }

  // Logging targets the selected day. Undefined when it's today → backend now().
  const targetDate = isToday(date) ? undefined : date;

  return (
    <div className="p-4 md:p-8 max-w-3xl mx-auto space-y-6">
      <div className="space-y-3">
        <PageHeader title="Supplements" description="Tagesübersicht & NEM-Tracking" />
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={() => setStacksOpen(true)}>
            <Layers className="h-4 w-4 mr-2" />
            Daily Stacks
          </Button>
          <Button variant="outline" size="sm" onClick={() => setCreateOpen(true)}>
            <Plus className="h-4 w-4 mr-2" />
            Eigene NEM
          </Button>
          <Button variant="outline" size="sm" onClick={() => setLibraryOpen(true)}>
            <BookOpen className="h-4 w-4 mr-2" />
            Bibliothek
          </Button>
        </div>
      </div>

      {/* WHOOP-style date navigator + 7-day strip */}
      <Card className="p-4 space-y-4">
        <DateNavigator
          date={date}
          viewMode={viewMode}
          onChangeDate={setDate}
          onChangeMode={setViewMode}
        />
        <WeekStrip
          userId={userId}
          anchorDate={date}
          onPickDay={(d) => {
            setDate(d);
            setViewMode('day');
          }}
        />
      </Card>

      {/* The selected day's intakes + daily-dose progress */}
      <DayPanel userId={userId} date={date} />

      {/* Single-intake logging always visible, targeting the selected day. */}
      {targetDate && (
        <div className="rounded-md border border-[hsl(var(--success-muted)/0.3)] bg-[hsl(var(--success-muted)/0.06)] px-4 py-2 text-xs text-muted-foreground">
          Du protokollierst für einen vergangenen Tag — Einträge werden auf dieses Datum gebucht.
        </div>
      )}
      <SingleIntakeForm userId={userId} targetDate={targetDate} />

      {/* ---- Dialogs opened from the header tools ---- */}
      <Dialog open={stacksOpen} onOpenChange={setStacksOpen}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogTitle>Daily Stacks</DialogTitle>
          <StacksSection userId={userId} targetDate={targetDate} />
        </DialogContent>
      </Dialog>

      <Dialog open={libraryOpen} onOpenChange={setLibraryOpen}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogTitle>NEM-Bibliothek</DialogTitle>
          <NemLibrarySection userId={userId} />
        </DialogContent>
      </Dialog>

      <CreateSupplementDialog userId={userId} open={createOpen} onClose={() => setCreateOpen(false)} />
    </div>
  );
}
