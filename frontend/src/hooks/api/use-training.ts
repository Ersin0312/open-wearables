import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import {
  trainingService,
  type ExerciseFilterParams,
  type SessionCreatePayload,
  type SetCreatePayload,
  type SetUpdatePayload,
} from '../../lib/api/services/training.service';

// ----- Query keys (local — small enough not to need the central registry) -----
const trainingKeys = {
  all: ['training'] as const,
  exercises: (params: ExerciseFilterParams) =>
    [...trainingKeys.all, 'exercises', params] as const,
  sessions: (userId: string, params?: object) =>
    [...trainingKeys.all, 'sessions', userId, params ?? {}] as const,
  session: (userId: string, sessionId: string) =>
    [...trainingKeys.all, 'session', userId, sessionId] as const,
  sets: (userId: string, sessionId: string) =>
    [...trainingKeys.all, 'sets', userId, sessionId] as const,
  lastSession: (userId: string, splitTag: string) =>
    [...trainingKeys.all, 'last-session', userId, splitTag] as const,
};

// ----- Exercises -----
export function useExercises(params: ExerciseFilterParams, enabled = true) {
  return useQuery({
    queryKey: trainingKeys.exercises(params),
    queryFn: () => trainingService.listExercises(params),
    enabled: enabled && !!params.user_id,
  });
}

// ----- Sessions -----
export function useTrainingSessions(
  userId: string,
  params?: { limit?: number; offset?: number; split_tag?: string }
) {
  return useQuery({
    queryKey: trainingKeys.sessions(userId, params),
    queryFn: () => trainingService.listSessions(userId, params),
    enabled: !!userId,
  });
}

export function useTrainingSession(userId: string, sessionId: string | null) {
  return useQuery({
    queryKey: trainingKeys.session(userId, sessionId ?? ''),
    queryFn: () => trainingService.getSession(userId, sessionId as string),
    enabled: !!userId && !!sessionId,
  });
}

export function useStartSession(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: SessionCreatePayload) => trainingService.startSession(userId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: trainingKeys.all });
      toast.success('Session gestartet');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to start session'),
  });
}

export function useEndSession(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sessionId: string) => trainingService.endSession(userId, sessionId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: trainingKeys.all });
      toast.success('Session beendet');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to end session'),
  });
}

export function useReopenSession(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sessionId: string) => trainingService.reopenSession(userId, sessionId),
    // Seed the single-session cache synchronously so the resume-guard in
    // TrainingPage reads ended_at=null immediately. Without this the guard
    // sees the stale (ended) cached session and instantly clears the active
    // session, bouncing the user back to the start screen.
    onSuccess: (data) => {
      qc.setQueryData(trainingKeys.session(userId, data.id), data);
      qc.invalidateQueries({ queryKey: trainingKeys.all });
      toast.success('Session wieder geöffnet');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to reopen session'),
  });
}

export function useDuplicateSession(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sessionId: string) => trainingService.duplicateSession(userId, sessionId),
    onSuccess: (data) => {
      qc.setQueryData(trainingKeys.session(userId, data.id), data);
      qc.invalidateQueries({ queryKey: trainingKeys.all });
      toast.success('Session dupliziert');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to duplicate session'),
  });
}

export function useDeleteSession(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (sessionId: string) => trainingService.deleteSession(userId, sessionId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: trainingKeys.all });
      toast.success('Session gelöscht');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to delete session'),
  });
}

// ----- Sets -----
export function useSessionSets(userId: string, sessionId: string | null) {
  return useQuery({
    queryKey: trainingKeys.sets(userId, sessionId ?? ''),
    queryFn: () => trainingService.listSets(userId, sessionId as string),
    enabled: !!userId && !!sessionId,
  });
}

export function useAddSet(userId: string, sessionId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: SetCreatePayload) => trainingService.addSet(userId, sessionId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: trainingKeys.sets(userId, sessionId) });
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to add set'),
  });
}

export function useUpdateSet(userId: string, sessionId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ setId, payload }: { setId: string; payload: SetUpdatePayload }) =>
      trainingService.updateSet(userId, sessionId, setId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: trainingKeys.sets(userId, sessionId) });
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to update set'),
  });
}

export function useDeleteSet(userId: string, sessionId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (setId: string) => trainingService.deleteSet(userId, sessionId, setId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: trainingKeys.sets(userId, sessionId) });
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Failed to delete set'),
  });
}
