import { apiClient } from '../client';
import { API_ENDPOINTS } from '../config';

// ----- Types -----

export type SupplementCategory =
  | 'amino_acid'
  | 'vitamin'
  | 'mineral'
  | 'protein'
  | 'fatty_acid'
  | 'nootropic'
  | 'performance'
  | 'recovery'
  | 'other';

export type Unit = 'mg' | 'g' | 'ml' | 'iu' | 'capsule' | 'tablet' | 'scoop' | 'drop';

export interface Supplement {
  id: string;
  name: string;
  brand: string | null;
  category: SupplementCategory;
  default_dose: string | null;
  default_unit: Unit;
  recommended_daily_dose: string | null;
  notes: string | null;
  is_seeded: boolean;
  created_by_user_id: string | null;
  created_at: string;
}

export interface SupplementStackItem {
  id: string;
  stack_id: string;
  supplement_id: string;
  order_index: number;
  dose: string | null;
  unit: string | null;
  created_at: string;
}

export interface SupplementStack {
  id: string;
  user_id: string;
  name: string;
  notes: string | null;
  items: SupplementStackItem[];
  created_at: string;
}

export interface SupplementIntake {
  id: string;
  user_id: string;
  supplement_id: string;
  stack_id: string | null;
  taken_at: string;
  dose: string;
  unit: string;
  notes: string | null;
  created_at: string;
}

export interface StackCreatePayload {
  name: string;
  notes?: string | null;
  items: Array<{
    supplement_id: string;
    order_index?: number;
    dose?: number | null;
    unit?: string | null;
  }>;
}

export interface StackUpdatePayload {
  name?: string | null;
  notes?: string | null;
  items?: Array<{
    supplement_id: string;
    order_index?: number;
    dose?: number | null;
    unit?: string | null;
  }>;
}

export interface IntakeCreatePayload {
  supplement_id: string;
  taken_at?: string;
  dose: number;
  unit: string;
  notes?: string | null;
  stack_id?: string | null;
}

export interface IntakeUpdatePayload {
  dose?: number;
  unit?: string;
  taken_at?: string;
  notes?: string | null;
}

// ----- Service -----

export const supplementsService = {
  // Library
  async listSupplements(params: {
    user_id: string;
    category?: string;
    search?: string;
  }): Promise<Supplement[]> {
    return apiClient.get<Supplement[]>(API_ENDPOINTS.supplements, { params });
  },

  async createSupplement(payload: {
    name: string;
    brand?: string | null;
    category: SupplementCategory;
    default_dose?: number | null;
    default_unit: Unit;
    recommended_daily_dose?: number | null;
    notes?: string | null;
    // Required so the custom NEM is visible to its owner — the library query
    // returns seeded entries OR rows where created_by_user_id matches.
    created_by_user_id?: string | null;
  }): Promise<Supplement> {
    return apiClient.post<Supplement>(API_ENDPOINTS.supplements, payload);
  },

  async updateSupplement(
    supplementId: string,
    payload: {
      name?: string;
      brand?: string | null;
      category?: SupplementCategory;
      default_dose?: number | null;
      default_unit?: Unit;
      recommended_daily_dose?: number | null;
      notes?: string | null;
    },
  ): Promise<Supplement> {
    return apiClient.patch<Supplement>(API_ENDPOINTS.supplementDetail(supplementId), payload);
  },

  async deleteSupplement(supplementId: string): Promise<Supplement> {
    return apiClient.delete<Supplement>(API_ENDPOINTS.supplementDetail(supplementId));
  },

  // Stacks
  async listStacks(userId: string): Promise<SupplementStack[]> {
    return apiClient.get<SupplementStack[]>(API_ENDPOINTS.supplementStacks(userId));
  },

  async getStack(userId: string, stackId: string): Promise<SupplementStack> {
    return apiClient.get<SupplementStack>(API_ENDPOINTS.supplementStackDetail(userId, stackId));
  },

  async createStack(userId: string, payload: StackCreatePayload): Promise<SupplementStack> {
    return apiClient.post<SupplementStack>(API_ENDPOINTS.supplementStacks(userId), payload);
  },

  async updateStack(
    userId: string,
    stackId: string,
    payload: StackUpdatePayload,
  ): Promise<SupplementStack> {
    return apiClient.patch<SupplementStack>(
      API_ENDPOINTS.supplementStackDetail(userId, stackId),
      payload,
    );
  },

  async deleteStack(userId: string, stackId: string): Promise<SupplementStack> {
    return apiClient.delete<SupplementStack>(API_ENDPOINTS.supplementStackDetail(userId, stackId));
  },

  async logStackNow(
    userId: string,
    stackId: string,
    takenAt?: string,
  ): Promise<SupplementIntake[]> {
    return apiClient.post<SupplementIntake[]>(
      API_ENDPOINTS.supplementStackLogNow(userId, stackId),
      {},
      takenAt ? { params: { taken_at: takenAt } } : undefined,
    );
  },

  // Intakes
  async listIntakes(
    userId: string,
    params?: { start_date?: string; end_date?: string; supplement_id?: string; limit?: number },
  ): Promise<SupplementIntake[]> {
    return apiClient.get<SupplementIntake[]>(API_ENDPOINTS.supplementIntakes(userId), { params });
  },

  async addIntake(userId: string, payload: IntakeCreatePayload): Promise<SupplementIntake> {
    return apiClient.post<SupplementIntake>(API_ENDPOINTS.supplementIntakes(userId), payload);
  },

  async updateIntake(
    userId: string,
    intakeId: string,
    payload: IntakeUpdatePayload,
  ): Promise<SupplementIntake> {
    return apiClient.patch<SupplementIntake>(
      API_ENDPOINTS.supplementIntakeDetail(userId, intakeId),
      payload,
    );
  },

  async deleteIntake(userId: string, intakeId: string): Promise<SupplementIntake> {
    return apiClient.delete<SupplementIntake>(
      API_ENDPOINTS.supplementIntakeDetail(userId, intakeId),
    );
  },
};
