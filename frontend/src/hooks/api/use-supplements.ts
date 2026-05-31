import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import {
  supplementsService,
  type IntakeCreatePayload,
  type IntakeUpdatePayload,
  type StackCreatePayload,
  type StackUpdatePayload,
} from '../../lib/api/services/supplements.service';

const supplementKeys = {
  all: ['supplements'] as const,
  library: (userId: string, search?: string, category?: string) =>
    [...supplementKeys.all, 'library', userId, { search, category }] as const,
  stacks: (userId: string) => [...supplementKeys.all, 'stacks', userId] as const,
  stack: (userId: string, stackId: string) =>
    [...supplementKeys.all, 'stack', userId, stackId] as const,
  intakes: (userId: string, params?: object) =>
    [...supplementKeys.all, 'intakes', userId, params ?? {}] as const,
};

// ----- Library -----
export function useSupplements(userId: string, params?: { search?: string; category?: string }) {
  return useQuery({
    queryKey: supplementKeys.library(userId, params?.search, params?.category),
    queryFn: () => supplementsService.listSupplements({ user_id: userId, ...params }),
    enabled: !!userId,
  });
}

export function useCreateSupplement() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: supplementsService.createSupplement,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.all });
      toast.success('NEM hinzugefügt');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useUpdateSupplement() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      supplementId,
      payload,
    }: {
      supplementId: string;
      payload: Parameters<typeof supplementsService.updateSupplement>[1];
    }) => supplementsService.updateSupplement(supplementId, payload),
    onSuccess: () => {
      // Touch everything: library list, stacks (item names), intakes (display names).
      qc.invalidateQueries({ queryKey: supplementKeys.all });
      toast.success('NEM aktualisiert');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useDeleteSupplement() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (supplementId: string) => supplementsService.deleteSupplement(supplementId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.all });
      toast.success('NEM gelöscht');
    },
    // 409 from the API (still referenced) surfaces its detail message here.
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler beim Löschen'),
  });
}

// ----- Stacks -----
export function useStacks(userId: string) {
  return useQuery({
    queryKey: supplementKeys.stacks(userId),
    queryFn: () => supplementsService.listStacks(userId),
    enabled: !!userId,
  });
}

export function useCreateStack(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: StackCreatePayload) => supplementsService.createStack(userId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.stacks(userId) });
      toast.success('Stack erstellt');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useUpdateStack(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ stackId, payload }: { stackId: string; payload: StackUpdatePayload }) =>
      supplementsService.updateStack(userId, stackId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.all });
      toast.success('Stack aktualisiert');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useDeleteStack(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (stackId: string) => supplementsService.deleteStack(userId, stackId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.stacks(userId) });
      toast.success('Stack gelöscht');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useLogStackNow(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    // takenAt (ISO) optional — backdates the log to a past day.
    mutationFn: ({ stackId, takenAt }: { stackId: string; takenAt?: string }) =>
      supplementsService.logStackNow(userId, stackId, takenAt),
    onSuccess: (intakes) => {
      qc.invalidateQueries({ queryKey: supplementKeys.intakes(userId) });
      toast.success(`${intakes.length} NEMs gelogged`);
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

// ----- Intakes -----
export function useIntakes(
  userId: string,
  params?: { start_date?: string; end_date?: string; supplement_id?: string; limit?: number },
) {
  return useQuery({
    queryKey: supplementKeys.intakes(userId, params),
    queryFn: () => supplementsService.listIntakes(userId, params),
    enabled: !!userId,
  });
}

export function useAddIntake(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (payload: IntakeCreatePayload) => supplementsService.addIntake(userId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.intakes(userId) });
      toast.success('Eintrag gelogged');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useUpdateIntake(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ intakeId, payload }: { intakeId: string; payload: IntakeUpdatePayload }) =>
      supplementsService.updateIntake(userId, intakeId, payload),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.intakes(userId) });
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}

export function useDeleteIntake(userId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (intakeId: string) => supplementsService.deleteIntake(userId, intakeId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: supplementKeys.intakes(userId) });
      toast.success('Eintrag gelöscht');
    },
    onError: (e: unknown) => toast.error(e instanceof Error ? e.message : 'Fehler'),
  });
}
