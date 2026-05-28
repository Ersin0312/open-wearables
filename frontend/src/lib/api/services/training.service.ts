import { apiClient } from '../client';
import { API_ENDPOINTS } from '../config';

// ----- Types -----

export type Equipment = 'machine' | 'barbell' | 'dumbbell' | 'cable' | 'bodyweight';
export type MuscleGroup =
  | 'chest'
  | 'back'
  | 'shoulders'
  | 'biceps'
  | 'triceps'
  | 'legs'
  | 'core'
  | 'glutes'
  | 'fullbody';
export type ExerciseSplitTag = 'push' | 'pull' | 'legs' | 'core';
export type SessionSplitTag = 'push' | 'pull' | 'legs' | 'custom';

export interface Exercise {
  id: string;
  name: string;
  equipment: Equipment;
  primary_muscle_group: MuscleGroup;
  default_split_tag: ExerciseSplitTag;
  image_url: string | null;
  is_seeded: boolean;
  created_by_user_id: string | null;
  created_at: string;
}

export interface TrainingSession {
  id: string;
  user_id: string;
  started_at: string;
  ended_at: string | null;
  split_tag: SessionSplitTag;
  notes: string | null;
  created_at: string;
}

export interface TrainingSet {
  id: string;
  session_id: string;
  exercise_id: string;
  set_number: number;
  reps: number;
  weight_kg: string; // server returns Decimal as string
  rpe: string | null;
  notes: string | null;
  created_at: string;
}

export interface SessionCreatePayload {
  user_id: string;
  split_tag: SessionSplitTag;
  notes?: string | null;
  started_at?: string;
}

export interface SetCreatePayload {
  exercise_id: string;
  set_number: number;
  reps: number;
  weight_kg: number;
  rpe?: number | null;
  notes?: string | null;
}

export interface ExerciseFilterParams {
  user_id: string;
  split_tag?: string;
  muscle_group?: string;
  search?: string;
}

// ----- Service -----

export const trainingService = {
  // Exercises
  async listExercises(params: ExerciseFilterParams): Promise<Exercise[]> {
    return apiClient.get<Exercise[]>(API_ENDPOINTS.trainingExercises, { params });
  },

  async createExercise(payload: Omit<Exercise, 'id' | 'created_at' | 'is_seeded'>): Promise<Exercise> {
    return apiClient.post<Exercise>(API_ENDPOINTS.trainingExercises, {
      ...payload,
      is_seeded: false,
    });
  },

  // Sessions
  async listSessions(
    userId: string,
    params?: { limit?: number; offset?: number; split_tag?: string }
  ): Promise<TrainingSession[]> {
    return apiClient.get<TrainingSession[]>(API_ENDPOINTS.trainingSessions(userId), { params });
  },

  async getSession(userId: string, sessionId: string): Promise<TrainingSession> {
    return apiClient.get<TrainingSession>(API_ENDPOINTS.trainingSessionDetail(userId, sessionId));
  },

  async startSession(userId: string, payload: SessionCreatePayload): Promise<TrainingSession> {
    return apiClient.post<TrainingSession>(API_ENDPOINTS.trainingSessions(userId), payload);
  },

  async endSession(userId: string, sessionId: string): Promise<TrainingSession> {
    return apiClient.post<TrainingSession>(API_ENDPOINTS.trainingSessionEnd(userId, sessionId), {});
  },

  async deleteSession(userId: string, sessionId: string): Promise<TrainingSession> {
    return apiClient.delete<TrainingSession>(API_ENDPOINTS.trainingSessionDetail(userId, sessionId));
  },

  async getLastSession(userId: string, splitTag: string): Promise<TrainingSession | null> {
    return apiClient.get<TrainingSession | null>(API_ENDPOINTS.trainingLastSession(userId), {
      params: { split_tag: splitTag },
    });
  },

  // Sets
  async listSets(userId: string, sessionId: string): Promise<TrainingSet[]> {
    return apiClient.get<TrainingSet[]>(API_ENDPOINTS.trainingSessionSets(userId, sessionId));
  },

  async addSet(userId: string, sessionId: string, payload: SetCreatePayload): Promise<TrainingSet> {
    return apiClient.post<TrainingSet>(
      API_ENDPOINTS.trainingSessionSets(userId, sessionId),
      payload
    );
  },

  async deleteSet(userId: string, sessionId: string, setId: string): Promise<TrainingSet> {
    return apiClient.delete<TrainingSet>(
      API_ENDPOINTS.trainingSessionSetDetail(userId, sessionId, setId)
    );
  },
};
