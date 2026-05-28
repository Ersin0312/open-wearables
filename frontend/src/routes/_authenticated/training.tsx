import { createFileRoute } from '@tanstack/react-router';
import { useEffect, useMemo, useState } from 'react';
import { Dumbbell, History, Plus, Search, Square, Trash2, X } from 'lucide-react';
import { PageHeader } from '@/components/ui/page-header';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from '@/components/ui/dialog';
import { useUsers } from '@/hooks/api/use-users';
import {
  useExercises,
  useTrainingSession,
  useTrainingSessions,
  useSessionSets,
  useStartSession,
  useEndSession,
  useAddSet,
  useDeleteSet,
} from '@/hooks/api/use-training';
import type {
  Exercise,
  SessionSplitTag,
  TrainingSession,
  TrainingSet,
} from '@/lib/api/services/training.service';

const ACTIVE_SESSION_KEY = 'health-platform.active-training-session';
const SPLIT_TAGS: SessionSplitTag[] = ['push', 'pull', 'legs', 'custom'];

const MUSCLE_LABELS: Record<string, string> = {
  chest: 'Brust',
  back: 'Rücken',
  shoulders: 'Schultern',
  biceps: 'Bizeps',
  triceps: 'Trizeps',
  legs: 'Beine',
  glutes: 'Gesäß',
  core: 'Rumpf',
  fullbody: 'Ganzkörper',
};

const MUSCLE_ORDER = [
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'legs', 'glutes', 'core', 'fullbody',
];

const SPLIT_LABELS: Record<string, string> = {
  push: 'Push',
  pull: 'Pull',
  legs: 'Beine',
  custom: 'Custom',
};

export const Route = createFileRoute('/_authenticated/training')({
  component: TrainingPage,
});

// ===================== Page root =====================
function TrainingPage() {
  const { data: users, isLoading: usersLoading } = useUsers({ limit: 1 });
  const userId = users?.items?.[0]?.id ?? '';

  const [activeSessionId, setActiveSessionId] = useState<string | null>(() => {
    if (typeof window === 'undefined') return null;
    return window.localStorage.getItem(ACTIVE_SESSION_KEY);
  });

  const { data: sessions } = useTrainingSessions(userId, { limit: 10 });
  const { data: persistedSession, isError: persistedError } = useTrainingSession(
    userId,
    activeSessionId,
  );

  useEffect(() => {
    if (!activeSessionId) return;
    if (persistedError) {
      window.localStorage.removeItem(ACTIVE_SESSION_KEY);
      setActiveSessionId(null);
      return;
    }
    if (persistedSession && persistedSession.ended_at) {
      window.localStorage.removeItem(ACTIVE_SESSION_KEY);
      setActiveSessionId(null);
    }
  }, [activeSessionId, persistedSession, persistedError]);

  function handleStarted(session: TrainingSession) {
    window.localStorage.setItem(ACTIVE_SESSION_KEY, session.id);
    setActiveSessionId(session.id);
  }

  function handleEnded() {
    window.localStorage.removeItem(ACTIVE_SESSION_KEY);
    setActiveSessionId(null);
  }

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
      <PageHeader title="Training" description="Live-log your strength sessions" />

      {activeSessionId ? (
        <ActiveSessionView
          userId={userId}
          sessionId={activeSessionId}
          onEnded={handleEnded}
        />
      ) : (
        <NewSessionView userId={userId} onStarted={handleStarted} />
      )}

      <SessionHistorySection
        userId={userId}
        sessions={sessions ?? []}
        activeSessionId={activeSessionId}
      />
    </div>
  );
}

// ===================== New session start =====================
function NewSessionView({
  userId,
  onStarted,
}: {
  userId: string;
  onStarted: (session: TrainingSession) => void;
}) {
  const startSession = useStartSession(userId);

  return (
    <Card className="p-5 space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Neue Session starten</h2>
        <p className="text-sm text-muted-foreground">Wähle deinen Split — beginnt sofort.</p>
      </div>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {SPLIT_TAGS.map((tag) => (
          <Button
            key={tag}
            size="lg"
            className="h-16 text-base capitalize"
            disabled={startSession.isPending}
            onClick={() =>
              startSession.mutate(
                { user_id: userId, split_tag: tag },
                { onSuccess: onStarted },
              )
            }
          >
            <Dumbbell className="h-5 w-5 mr-2" />
            {SPLIT_LABELS[tag]}
          </Button>
        ))}
      </div>
    </Card>
  );
}

// ===================== Active session — live logger =====================
function ActiveSessionView({
  userId,
  sessionId,
  onEnded,
}: {
  userId: string;
  sessionId: string;
  onEnded: () => void;
}) {
  const { data: session, isLoading: sessionLoading } = useTrainingSession(userId, sessionId);
  const { data: sets, isLoading: setsLoading } = useSessionSets(userId, sessionId);
  const endSession = useEndSession(userId);

  if (sessionLoading || !session) {
    return (
      <Card className="p-5">
        <Skeleton className="h-6 w-32" />
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card className="p-5 space-y-3 border-[hsl(var(--success-muted)/0.3)] bg-[hsl(var(--success-muted)/0.05)]">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-2">
              <span className="relative flex h-2 w-2">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[hsl(var(--success-muted))] opacity-60" />
                <span className="relative inline-flex h-2 w-2 rounded-full bg-[hsl(var(--success-muted))]" />
              </span>
              <h2 className="text-lg font-semibold">Live: {SPLIT_LABELS[session.split_tag]} Session</h2>
            </div>
            <p className="text-xs text-muted-foreground mt-1">
              Gestartet {formatTime(session.started_at)} · {sets?.length ?? 0} Sätze
            </p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => endSession.mutate(sessionId, { onSuccess: onEnded })}
            disabled={endSession.isPending}
          >
            <Square className="h-4 w-4 mr-2" />
            Session beenden
          </Button>
        </div>
      </Card>

      <SetLoggerForm userId={userId} session={session} />

      <SetList
        userId={userId}
        sessionId={sessionId}
        sets={sets ?? []}
        isLoading={setsLoading}
      />
    </div>
  );
}

// ===================== Set logger form =====================
function SetLoggerForm({
  userId,
  session,
}: {
  userId: string;
  session: TrainingSession;
}) {
  const splitFilter = session.split_tag === 'custom' ? undefined : session.split_tag;
  const { data: exercises } = useExercises({ user_id: userId, split_tag: splitFilter });

  const [exerciseId, setExerciseId] = useState<string>('');
  const [reps, setReps] = useState<string>('');
  const [weight, setWeight] = useState<string>('');
  const [search, setSearch] = useState<string>('');
  const [lightboxOpen, setLightboxOpen] = useState(false);

  const { data: existingSets } = useSessionSets(userId, session.id);
  const nextSetNumber = useMemo(() => {
    if (!existingSets || !exerciseId) return 1;
    return existingSets.filter((s) => s.exercise_id === exerciseId).length + 1;
  }, [existingSets, exerciseId]);

  const addSet = useAddSet(userId, session.id);

  const groupedExercises = useMemo(
    () => groupExercises(exercises ?? [], search),
    [exercises, search],
  );

  const selectedExercise = exercises?.find((e) => e.id === exerciseId);

  const submit = () => {
    if (!exerciseId) return;
    const repsNum = parseInt(reps, 10);
    const weightNum = parseFloat(weight);
    if (isNaN(repsNum) || isNaN(weightNum)) return;

    addSet.mutate(
      {
        exercise_id: exerciseId,
        set_number: nextSetNumber,
        reps: repsNum,
        weight_kg: weightNum,
      },
      {
        onSuccess: () => setReps(''),
      },
    );
  };

  return (
    <Card className="p-5 space-y-4">
      <Label>Übung</Label>

      {selectedExercise ? (
        <SelectedExerciseCard
          exercise={selectedExercise}
          nextSetNumber={nextSetNumber}
          onChange={() => {
            setExerciseId('');
            setSearch('');
          }}
          onImageClick={() => setLightboxOpen(true)}
        />
      ) : (
        <ExercisePicker
          search={search}
          onSearchChange={setSearch}
          grouped={groupedExercises}
          onSelect={(id) => {
            setExerciseId(id);
            setSearch('');
          }}
        />
      )}

      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-2">
          <Label htmlFor="reps">Wiederholungen</Label>
          <Input
            id="reps"
            type="number"
            inputMode="numeric"
            className="h-12 text-base"
            value={reps}
            onChange={(e) => setReps(e.target.value)}
            placeholder="10"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="weight">Gewicht (kg)</Label>
          <Input
            id="weight"
            type="number"
            inputMode="decimal"
            step="0.5"
            className="h-12 text-base"
            value={weight}
            onChange={(e) => setWeight(e.target.value)}
            placeholder="70"
          />
        </div>
      </div>

      <Button
        size="lg"
        className="w-full h-14 text-base"
        onClick={submit}
        disabled={!exerciseId || !reps || !weight || addSet.isPending}
      >
        <Plus className="h-5 w-5 mr-2" />
        Satz hinzufügen
      </Button>

      {selectedExercise?.image_url && (
        <Dialog open={lightboxOpen} onOpenChange={setLightboxOpen}>
          <DialogContent className="max-w-3xl p-2 sm:p-4">
            <DialogTitle className="text-base px-2 pt-1">{selectedExercise.name}</DialogTitle>
            <img
              src={selectedExercise.image_url}
              alt={selectedExercise.name}
              className="w-full h-auto max-h-[80vh] object-contain rounded-md"
            />
          </DialogContent>
        </Dialog>
      )}
    </Card>
  );
}

// ===================== Combobox: live-filterable exercise list =====================
function ExercisePicker({
  search,
  onSearchChange,
  grouped,
  onSelect,
}: {
  search: string;
  onSearchChange: (v: string) => void;
  grouped: { group: string; label: string; items: Exercise[] }[];
  onSelect: (id: string) => void;
}) {
  return (
    <div className="space-y-2">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          type="text"
          className="h-12 text-base pl-9"
          placeholder="z. B. 3014, Brustpresse, Butterfly…"
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
          autoFocus
        />
        {search && (
          <button
            type="button"
            onClick={() => onSearchChange('')}
            className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-muted-foreground hover:text-foreground"
            aria-label="Suche löschen"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>

      <div className="border border-border/40 rounded-md max-h-72 overflow-y-auto bg-background">
        {grouped.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center p-6">
            Keine Übung gefunden für „{search}"
          </p>
        ) : (
          grouped.map(({ group, label, items }) => (
            <div key={group}>
              <div className="sticky top-0 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground px-3 py-1.5 bg-card/80 backdrop-blur border-b border-border/30">
                {label}
              </div>
              {items.map((ex) => (
                <button
                  key={ex.id}
                  type="button"
                  onClick={() => onSelect(ex.id)}
                  className="w-full text-left px-3 py-2.5 text-base hover:bg-card/40 border-b border-border/10 last:border-b-0 transition-colors"
                >
                  {ex.name}
                </button>
              ))}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

function SelectedExerciseCard({
  exercise,
  nextSetNumber,
  onChange,
  onImageClick,
}: {
  exercise: Exercise;
  nextSetNumber: number;
  onChange: () => void;
  onImageClick: () => void;
}) {
  return (
    <div className="space-y-3 border border-border/40 rounded-md p-3 bg-card/30">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="font-medium">{exercise.name}</div>
          <div className="text-xs text-muted-foreground mt-0.5">
            {MUSCLE_LABELS[exercise.primary_muscle_group]} · Satz #{nextSetNumber}
          </div>
        </div>
        <Button variant="ghost" size="sm" onClick={onChange}>
          Ändern
        </Button>
      </div>
      {exercise.image_url && (
        <button
          type="button"
          onClick={onImageClick}
          className="block w-full rounded-md overflow-hidden border border-border/40 bg-card/40 hover:border-border transition-colors cursor-zoom-in"
          aria-label="Bild vergrößern"
        >
          <img
            src={exercise.image_url}
            alt={exercise.name}
            className="w-full h-auto max-h-48 object-contain"
            loading="lazy"
          />
        </button>
      )}
    </div>
  );
}

// ===================== Sets in current session =====================
function SetList({
  userId,
  sessionId,
  sets,
  isLoading,
}: {
  userId: string;
  sessionId: string;
  sets: TrainingSet[];
  isLoading: boolean;
}) {
  const deleteSet = useDeleteSet(userId, sessionId);

  if (isLoading) return <Skeleton className="h-24 w-full" />;
  if (sets.length === 0) {
    return (
      <Card className="p-5 text-center text-sm text-muted-foreground">
        Noch keine Sätze in dieser Session. Logge oben deinen ersten Satz.
      </Card>
    );
  }

  const grouped: Record<string, TrainingSet[]> = {};
  for (const s of sets) {
    (grouped[s.exercise_id] ??= []).push(s);
  }

  return (
    <Card className="p-5 space-y-4">
      <h3 className="font-semibold">Sätze in dieser Session</h3>
      <div className="space-y-3">
        {Object.entries(grouped).map(([exId, exSets]) => (
          <ExerciseSetGroup
            key={exId}
            userId={userId}
            exerciseId={exId}
            sets={exSets}
            onDelete={(setId) => deleteSet.mutate(setId)}
          />
        ))}
      </div>
    </Card>
  );
}

function ExerciseSetGroup({
  userId,
  exerciseId,
  sets,
  onDelete,
}: {
  userId: string;
  exerciseId: string;
  sets: TrainingSet[];
  onDelete?: (setId: string) => void;
}) {
  const { data: exercises } = useExercises({ user_id: userId });
  const exercise = exercises?.find((e) => e.id === exerciseId);

  return (
    <div className="space-y-2">
      <div className="text-sm font-medium">{exercise?.name ?? 'Unbekannte Übung'}</div>
      <div className="space-y-1">
        {sets.map((s) => (
          <div
            key={s.id}
            className="flex items-center justify-between text-sm px-2 py-1 rounded bg-card/50"
          >
            <div className="flex items-center gap-3">
              <Badge variant="outline" className="font-mono">#{s.set_number}</Badge>
              <span>
                {s.reps} reps × {parseFloat(s.weight_kg)} kg
              </span>
              <span className="text-xs text-muted-foreground">{formatTime(s.created_at)}</span>
            </div>
            {onDelete && (
              <Button variant="ghost" size="sm" onClick={() => onDelete(s.id)}>
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ===================== Past sessions — collapsed behind a button =====================
function SessionHistorySection({
  userId,
  sessions,
  activeSessionId,
}: {
  userId: string;
  sessions: TrainingSession[];
  activeSessionId: string | null;
}) {
  const [historyOpen, setHistoryOpen] = useState(false);
  const [detailSessionId, setDetailSessionId] = useState<string | null>(null);
  const past = sessions.filter((s) => s.id !== activeSessionId).slice(0, 10);

  if (past.length === 0) return null;

  return (
    <>
      <Button
        variant="outline"
        size="lg"
        className="w-full h-14 text-base"
        onClick={() => setHistoryOpen(true)}
      >
        <History className="h-5 w-5 mr-2" />
        Letzte Sessions ({past.length})
      </Button>

      {/* History list dialog. Hides itself while the detail dialog is open so
          they don't stack visually; state stays so closing the detail returns here. */}
      <Dialog
        open={historyOpen && !detailSessionId}
        onOpenChange={(open) => setHistoryOpen(open)}
      >
        <DialogContent className="max-w-md">
          <DialogTitle>Letzte Sessions</DialogTitle>
          <div className="space-y-2 max-h-[60vh] overflow-y-auto -mx-2 px-2">
            {past.map((s) => {
              const duration =
                s.ended_at && s.started_at
                  ? Math.round(
                      (new Date(s.ended_at).getTime() - new Date(s.started_at).getTime()) / 60000,
                    )
                  : null;
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => setDetailSessionId(s.id)}
                  className="w-full flex items-center justify-between text-sm px-3 py-3 rounded border border-border/40 hover:border-border hover:bg-card/40 transition-colors text-left"
                >
                  <div>
                    <span className="font-medium">{SPLIT_LABELS[s.split_tag] ?? s.split_tag}</span>
                    <span className="text-muted-foreground"> · {formatDate(s.started_at)}</span>
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {duration !== null ? `${duration} min` : 'noch offen'}
                  </div>
                </button>
              );
            })}
          </div>
        </DialogContent>
      </Dialog>

      <SessionDetailDialog
        userId={userId}
        sessionId={detailSessionId}
        onClose={() => setDetailSessionId(null)}
      />
    </>
  );
}

function SessionDetailDialog({
  userId,
  sessionId,
  onClose,
}: {
  userId: string;
  sessionId: string | null;
  onClose: () => void;
}) {
  const { data: session, isLoading: sessionLoading } = useTrainingSession(userId, sessionId);
  const { data: sets, isLoading: setsLoading } = useSessionSets(userId, sessionId);

  const grouped = useMemo(() => {
    const g: Record<string, TrainingSet[]> = {};
    (sets ?? []).forEach((s) => (g[s.exercise_id] ??= []).push(s));
    return g;
  }, [sets]);

  const duration =
    session?.ended_at && session.started_at
      ? Math.round((new Date(session.ended_at).getTime() - new Date(session.started_at).getTime()) / 60000)
      : null;

  return (
    <Dialog open={!!sessionId} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogTitle>
          {session
            ? `${SPLIT_LABELS[session.split_tag] ?? session.split_tag} Session — ${formatDate(session.started_at)}`
            : 'Session'}
        </DialogTitle>

        {sessionLoading || setsLoading || !session ? (
          <div className="space-y-3 py-4">
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <div className="space-y-4">
            <div className="text-xs text-muted-foreground">
              Gestartet {formatDateTime(session.started_at)}
              {session.ended_at
                ? ` · Beendet ${formatTime(session.ended_at)}${duration !== null ? ` · Dauer ${duration} min` : ''}`
                : ' · (noch offen)'}
              {sets ? ` · ${sets.length} Sätze` : ''}
            </div>

            {!sets || sets.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center py-8">
                Keine Sätze in dieser Session geloggt.
              </p>
            ) : (
              <div className="space-y-3">
                {Object.entries(grouped).map(([exId, exSets]) => (
                  <ExerciseSetGroup
                    key={exId}
                    userId={userId}
                    exerciseId={exId}
                    sets={exSets}
                    // No delete in history view — read-only
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

// ===================== Helpers =====================
function groupExercises(
  exercises: Exercise[],
  search: string,
): { group: string; label: string; items: Exercise[] }[] {
  const searchLower = search.trim().toLowerCase();
  const filtered = exercises.filter((ex) =>
    searchLower ? ex.name.toLowerCase().includes(searchLower) : true,
  );
  const groups: Record<string, Exercise[]> = {};
  filtered.forEach((ex) => {
    (groups[ex.primary_muscle_group] ??= []).push(ex);
  });
  return MUSCLE_ORDER
    .filter((g) => groups[g]?.length)
    .map((g) => ({ group: g, label: MUSCLE_LABELS[g], items: groups[g] }));
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('de-DE', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
  });
}

function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return `${d.toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' })} ${d.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })}`;
}
