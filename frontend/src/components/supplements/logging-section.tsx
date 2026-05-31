import { useEffect, useMemo, useState } from 'react';
import { Pill, Plus, Search, Settings, Trash2, X, Zap } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Skeleton } from '@/components/ui/skeleton';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import {
  useSupplements,
  useStacks,
  useCreateStack,
  useCreateSupplement,
  useUpdateStack,
  useDeleteStack,
  useLogStackNow,
  useAddIntake,
} from '@/hooks/api/use-supplements';
import {
  CATEGORY_LABELS,
  CATEGORY_ORDER,
  UNIT_OPTIONS,
  toFormItem,
  type StackItemForm,
} from '@/lib/supplements/shared';
import type {
  Supplement,
  SupplementCategory,
  SupplementStack,
  Unit,
} from '@/lib/api/services/supplements.service';

const selectClass =
  'h-11 w-full rounded-md border border-input bg-background px-3 text-sm focus:outline-none focus:ring-2 focus:ring-ring';

// Builds an ISO timestamp at local noon of the given day, so a backdated log
// lands squarely inside that calendar day regardless of timezone. `undefined`
// when logging for today → backend uses now().
function logTimestamp(targetDate?: Date): string | undefined {
  if (!targetDate) return undefined;
  const d = new Date(targetDate);
  d.setHours(12, 0, 0, 0);
  return d.toISOString();
}

// ===================== Daily Stacks =====================
export function StacksSection({
  userId,
  targetDate,
}: {
  userId: string;
  // When set (a past day), logs are backdated to that day. Undefined = today.
  targetDate?: Date;
}) {
  const { data: stacks, isLoading } = useStacks(userId);
  const logStackNow = useLogStackNow(userId);
  const deleteStack = useDeleteStack(userId);
  const [editStack, setEditStack] = useState<SupplementStack | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const takenAt = logTimestamp(targetDate);

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <p className="text-xs text-muted-foreground">
            {targetDate
              ? 'Ein Klick → für den gewählten Tag geloggt'
              : 'Ein Klick → alle NEMs des Stacks geloggt (heute)'}
          </p>
          <Button variant="outline" size="sm" onClick={() => setCreateOpen(true)}>
            <Plus className="h-4 w-4 mr-2" />
            Neuer Stack
          </Button>
        </div>

        {isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : !stacks || stacks.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-6">
            Noch keine Stacks. Lege einen an, um schneller zu loggen.
          </p>
        ) : (
          <div className="space-y-3">
            {stacks.map((s) => (
              <div
                key={s.id}
                className="flex items-center justify-between p-3 rounded border border-border/40 bg-card/40"
              >
                <div className="min-w-0">
                  <div className="font-medium truncate">{s.name}</div>
                  <div className="text-xs text-muted-foreground">{s.items.length} NEMs</div>
                </div>
                <div className="flex items-center gap-2">
                  <Button
                    size="sm"
                    onClick={() => logStackNow.mutate({ stackId: s.id, takenAt })}
                    disabled={logStackNow.isPending || s.items.length === 0}
                  >
                    <Zap className="h-4 w-4 mr-2" />
                    {targetDate ? 'Loggen' : 'Jetzt loggen'}
                  </Button>
                  <Button variant="ghost" size="sm" onClick={() => setEditStack(s)} aria-label="Stack bearbeiten">
                    <Settings className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    aria-label="Stack löschen"
                    onClick={() => {
                      if (confirm(`Stack "${s.name}" wirklich löschen?`)) deleteStack.mutate(s.id);
                    }}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <StackEditDialog userId={userId} stack={editStack} onClose={() => setEditStack(null)} />
      <StackCreateDialog userId={userId} open={createOpen} onClose={() => setCreateOpen(false)} />
    </>
  );
}

function StackCreateDialog({
  userId,
  open,
  onClose,
}: {
  userId: string;
  open: boolean;
  onClose: () => void;
}) {
  const createStack = useCreateStack(userId);
  const { data: supplements } = useSupplements(userId);
  const [name, setName] = useState('');
  const [selected, setSelected] = useState<StackItemForm[]>([]);

  const buildDefaultName = (): string => {
    const names = selected
      .map((it) => supplements?.find((s) => s.id === it.supplement_id)?.name)
      .filter((n): n is string => Boolean(n));
    if (names.length === 0) return 'Neuer Stack';
    if (names.length <= 2) return names.join(' + ');
    return `${names.slice(0, 2).join(' + ')} +${names.length - 2}`;
  };

  const submit = () => {
    if (selected.length === 0) return;
    createStack.mutate(
      {
        name: name.trim() || buildDefaultName(),
        items: selected.map((it, idx) => ({
          supplement_id: it.supplement_id,
          order_index: idx,
          dose: it.dose ? parseFloat(it.dose) : null,
          unit: it.unit || null,
        })),
      },
      {
        onSuccess: () => {
          setName('');
          setSelected([]);
          onClose();
        },
      },
    );
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogTitle>Neuen Stack anlegen</DialogTitle>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="stack-name">Name <span className="text-muted-foreground font-normal">(optional)</span></Label>
            <Input
              id="stack-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="z. B. Morning Stack — leer = automatisch"
              className="h-11"
            />
          </div>

          <SupplementSelector
            userId={userId}
            selected={selected}
            onToggle={(s) =>
              setSelected((prev) =>
                prev.some((it) => it.supplement_id === s.id)
                  ? prev.filter((it) => it.supplement_id !== s.id)
                  : [...prev, toFormItem(s)],
              )
            }
            onDoseChange={(id, dose) =>
              setSelected((prev) => prev.map((it) => (it.supplement_id === id ? { ...it, dose } : it)))
            }
          />

          <Button
            size="lg"
            className="w-full"
            onClick={submit}
            disabled={selected.length === 0 || createStack.isPending}
          >
            {selected.length === 0
              ? 'Mindestens 1 NEM auswählen'
              : `Stack mit ${selected.length} NEM${selected.length === 1 ? '' : 's'} erstellen`}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function StackEditDialog({
  userId,
  stack,
  onClose,
}: {
  userId: string;
  stack: SupplementStack | null;
  onClose: () => void;
}) {
  const updateStack = useUpdateStack(userId);
  const { data: supplements } = useSupplements(userId);
  const [name, setName] = useState('');
  const [selected, setSelected] = useState<StackItemForm[]>([]);

  useEffect(() => {
    if (stack) {
      setName(stack.name);
      setSelected(
        stack.items.map((i) => {
          const sup = supplements?.find((s) => s.id === i.supplement_id);
          const dose = i.dose ?? sup?.default_dose ?? null;
          return {
            supplement_id: i.supplement_id,
            dose: dose != null ? String(parseFloat(String(dose))) : '',
            unit: i.unit ?? sup?.default_unit ?? '',
          };
        }),
      );
    }
  }, [stack, supplements]);

  if (!stack) return null;

  const submit = () => {
    updateStack.mutate(
      {
        stackId: stack.id,
        payload: {
          name: name.trim(),
          items: selected.map((it, idx) => ({
            supplement_id: it.supplement_id,
            order_index: idx,
            dose: it.dose ? parseFloat(it.dose) : null,
            unit: it.unit || null,
          })),
        },
      },
      { onSuccess: onClose },
    );
  };

  return (
    <Dialog open={!!stack} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogTitle>Stack bearbeiten</DialogTitle>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="stack-name-edit">Name</Label>
            <Input id="stack-name-edit" value={name} onChange={(e) => setName(e.target.value)} className="h-11" />
          </div>

          <SupplementSelector
            userId={userId}
            selected={selected}
            onToggle={(s) =>
              setSelected((prev) =>
                prev.some((it) => it.supplement_id === s.id)
                  ? prev.filter((it) => it.supplement_id !== s.id)
                  : [...prev, toFormItem(s)],
              )
            }
            onDoseChange={(id, dose) =>
              setSelected((prev) => prev.map((it) => (it.supplement_id === id ? { ...it, dose } : it)))
            }
          />

          <Button size="lg" className="w-full" onClick={submit} disabled={!name.trim() || updateStack.isPending}>
            Speichern ({selected.length} NEMs)
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function SupplementSelector({
  userId,
  selected,
  onToggle,
  onDoseChange,
}: {
  userId: string;
  selected: StackItemForm[];
  onToggle: (supplement: Supplement) => void;
  onDoseChange: (supplementId: string, dose: string) => void;
}) {
  const [search, setSearch] = useState('');
  const { data: supplements } = useSupplements(userId);

  const grouped = useMemo(() => {
    const tokens = search.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const filtered = (supplements ?? []).filter((s) => {
      if (tokens.length === 0) return true;
      const name = s.name.toLowerCase();
      return tokens.every((t) => name.includes(t));
    });
    const groups: Record<string, Supplement[]> = {};
    filtered.forEach((s) => {
      (groups[s.category] ??= []).push(s);
    });
    return CATEGORY_ORDER.filter((c) => groups[c]?.length).map((c) => ({
      category: c,
      label: CATEGORY_LABELS[c],
      items: groups[c],
    }));
  }, [supplements, search]);

  return (
    <div className="space-y-2">
      <Label>NEMs auswählen ({selected.length})</Label>
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          type="text"
          className="h-11 text-base pl-9"
          placeholder="Suche..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Escape' && search) {
              e.preventDefault();
              e.stopPropagation();
              setSearch('');
            }
          }}
        />
      </div>
      <div className="border border-border/40 rounded-md max-h-72 overflow-y-auto bg-background">
        {grouped.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center p-6">Keine NEMs gefunden</p>
        ) : (
          grouped.map(({ category, label, items }) => (
            <div key={category}>
              <div className="sticky top-0 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground px-3 py-1.5 bg-card/80 backdrop-blur border-b border-border/30">
                {label}
              </div>
              {items.map((s) => {
                const picked = selected.find((it) => it.supplement_id === s.id);
                const isSelected = Boolean(picked);
                return (
                  <div
                    key={s.id}
                    className={`px-3 py-2.5 text-sm border-b border-border/10 last:border-b-0 transition-colors ${
                      isSelected ? 'bg-[hsl(var(--success-muted)/0.1)]' : 'hover:bg-card/40'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-3">
                      <button type="button" onClick={() => onToggle(s)} className="flex-1 text-left min-w-0">
                        <div className="font-medium truncate">{s.name}</div>
                        {!isSelected && s.default_dose && (
                          <div className="text-xs text-muted-foreground">
                            Standard: {parseFloat(s.default_dose)} {s.default_unit}
                          </div>
                        )}
                      </button>

                      {isSelected ? (
                        <div className="flex items-center gap-1.5 shrink-0">
                          <Input
                            type="number"
                            inputMode="decimal"
                            step="0.01"
                            value={picked?.dose ?? ''}
                            onChange={(e) => onDoseChange(s.id, e.target.value)}
                            className="h-8 w-20 text-sm"
                            aria-label={`Dosis für ${s.name}`}
                          />
                          <span className="text-xs text-muted-foreground w-12">
                            {picked?.unit || s.default_unit}
                          </span>
                          <button
                            type="button"
                            onClick={() => onToggle(s)}
                            className="p-1 text-muted-foreground hover:text-foreground"
                            aria-label={`${s.name} entfernen`}
                          >
                            <X className="h-4 w-4" />
                          </button>
                        </div>
                      ) : (
                        <button type="button" onClick={() => onToggle(s)} className="shrink-0" aria-label={`${s.name} hinzufügen`}>
                          <Plus className="h-4 w-4 text-muted-foreground" />
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          ))
        )}
      </div>
    </div>
  );
}

// ===================== Single intake quick form =====================
export function SingleIntakeForm({
  userId,
  targetDate,
}: {
  userId: string;
  // When set (a past day), the intake is backdated to that day. Undefined = today.
  targetDate?: Date;
}) {
  const [supplementId, setSupplementId] = useState('');
  const [dose, setDose] = useState('');
  const [search, setSearch] = useState('');

  const { data: supplements } = useSupplements(userId);
  const addIntake = useAddIntake(userId);
  const takenAt = logTimestamp(targetDate);

  const selected = supplements?.find((s) => s.id === supplementId);

  const handleSelect = (id: string) => {
    setSupplementId(id);
    const sup = supplements?.find((s) => s.id === id);
    setDose(sup?.default_dose ? String(parseFloat(sup.default_dose)) : '');
    setSearch('');
  };

  const submit = () => {
    if (!supplementId || !dose || !selected) return;
    const doseNum = parseFloat(dose);
    if (isNaN(doseNum)) return;
    addIntake.mutate(
      {
        supplement_id: supplementId,
        dose: doseNum,
        unit: selected.default_unit,
        ...(takenAt ? { taken_at: takenAt } : {}),
      },
      {
        onSuccess: () => {
          setSupplementId('');
          setDose('');
        },
      },
    );
  };

  const grouped = useMemo(() => {
    const tokens = search.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const filtered = (supplements ?? []).filter((s) => {
      if (tokens.length === 0) return true;
      const name = s.name.toLowerCase();
      return tokens.every((t) => name.includes(t));
    });
    const groups: Record<string, Supplement[]> = {};
    filtered.forEach((s) => {
      (groups[s.category] ??= []).push(s);
    });
    return CATEGORY_ORDER.filter((c) => groups[c]?.length).map((c) => ({
      category: c,
      label: CATEGORY_LABELS[c],
      items: groups[c],
    }));
  }, [supplements, search]);

  return (
    <Card className="p-5 space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Einzeln loggen</h2>
        <p className="text-xs text-muted-foreground mt-1">Nicht im Stack? Hier einzelne Einnahme erfassen (heute).</p>
      </div>

      {selected ? (
        <div className="space-y-3 border border-border/40 rounded-md p-3 bg-card/30">
          <div className="flex items-start justify-between">
            <div>
              <div className="font-medium">{selected.name}</div>
              <div className="text-xs text-muted-foreground">{CATEGORY_LABELS[selected.category]}</div>
            </div>
            <Button variant="ghost" size="sm" onClick={() => setSupplementId('')}>
              Ändern
            </Button>
          </div>
        </div>
      ) : (
        <div className="space-y-2">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              type="text"
              className="h-11 text-base pl-9"
              placeholder="z. B. Magnesium, Creatin..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Escape') {
                  e.preventDefault();
                  setSearch('');
                }
              }}
            />
            {search && (
              <button
                type="button"
                onClick={() => setSearch('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-muted-foreground hover:text-foreground"
              >
                <X className="h-4 w-4" />
              </button>
            )}
          </div>
          <div className="border border-border/40 rounded-md max-h-56 overflow-y-auto bg-background">
            {grouped.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center p-4">Keine NEMs gefunden</p>
            ) : (
              grouped.map(({ category, label, items }) => (
                <div key={category}>
                  <div className="sticky top-0 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground px-3 py-1 bg-card/80 backdrop-blur border-b border-border/30">
                    {label}
                  </div>
                  {items.map((s) => (
                    <button
                      key={s.id}
                      type="button"
                      onClick={() => handleSelect(s.id)}
                      className="w-full text-left px-3 py-2 text-sm hover:bg-card/40 border-b border-border/10 last:border-b-0"
                    >
                      {s.name}
                    </button>
                  ))}
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {selected && (
        <>
          <div className="grid grid-cols-[1fr_auto] gap-3">
            <div className="space-y-2">
              <Label htmlFor="dose">Dosis</Label>
              <Input
                id="dose"
                type="number"
                inputMode="decimal"
                step="0.01"
                value={dose}
                onChange={(e) => setDose(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    submit();
                  }
                }}
                className="h-11"
              />
            </div>
            <div className="space-y-2">
              <Label>Einheit</Label>
              <div className="h-11 flex items-center px-3 rounded-md border border-input bg-background text-sm text-muted-foreground">
                {selected.default_unit}
              </div>
            </div>
          </div>

          <Button size="lg" className="w-full h-12" onClick={submit} disabled={!dose || addIntake.isPending}>
            <Pill className="h-5 w-5 mr-2" />
            Eintrag loggen
          </Button>
        </>
      )}
    </Card>
  );
}

// ===================== Create custom supplement (own NEM) =====================
export function CreateSupplementDialog({
  userId,
  open,
  onClose,
}: {
  userId: string;
  open: boolean;
  onClose: () => void;
}) {
  const createSupplement = useCreateSupplement();
  const [name, setName] = useState('');
  const [brand, setBrand] = useState('');
  const [category, setCategory] = useState<SupplementCategory>('other');
  const [dose, setDose] = useState('');
  const [unit, setUnit] = useState<Unit>('mg');
  const [dailyDose, setDailyDose] = useState('');
  const [notes, setNotes] = useState('');

  const reset = () => {
    setName('');
    setBrand('');
    setCategory('other');
    setDose('');
    setUnit('mg');
    setDailyDose('');
    setNotes('');
  };

  const submit = () => {
    if (!name.trim()) return;
    const doseNum = parseFloat(dose);
    const dailyNum = parseFloat(dailyDose);
    createSupplement.mutate(
      {
        name: name.trim(),
        brand: brand.trim() || null,
        category,
        default_dose: isNaN(doseNum) ? null : doseNum,
        default_unit: unit,
        recommended_daily_dose: isNaN(dailyNum) ? null : dailyNum,
        notes: notes.trim() || null,
        created_by_user_id: userId,
      },
      {
        onSuccess: () => {
          reset();
          onClose();
        },
      },
    );
  };

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogTitle>Eigene NEM anlegen</DialogTitle>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="nem-name">Name des Produktes</Label>
            <Input id="nem-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="z. B. Vitamin D3 + K2" className="h-11" autoFocus />
          </div>

          <div className="space-y-2">
            <Label htmlFor="nem-brand">Hersteller <span className="text-muted-foreground font-normal">(optional)</span></Label>
            <Input id="nem-brand" value={brand} onChange={(e) => setBrand(e.target.value)} placeholder="z. B. Sunday Natural, ESN…" className="h-11" />
          </div>

          <div className="space-y-2">
            <Label htmlFor="nem-category">Kategorie</Label>
            <select id="nem-category" className={selectClass} value={category} onChange={(e) => setCategory(e.target.value as SupplementCategory)}>
              {CATEGORY_ORDER.map((c) => (
                <option key={c} value={c}>{CATEGORY_LABELS[c]}</option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="nem-dose">Standard-Dosis <span className="text-muted-foreground font-normal">(optional)</span></Label>
              <Input id="nem-dose" type="number" inputMode="decimal" step="0.01" value={dose} onChange={(e) => setDose(e.target.value)} placeholder="z. B. 5000" className="h-11" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="nem-unit">Einheit</Label>
              <select id="nem-unit" className={selectClass} value={unit} onChange={(e) => setUnit(e.target.value as Unit)}>
                {UNIT_OPTIONS.map((u) => (
                  <option key={u.value} value={u.value}>{u.label}</option>
                ))}
              </select>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="nem-daily">
              Empfohlene Tagesdosis <span className="text-muted-foreground font-normal">(optional, in {unit})</span>
            </Label>
            <Input id="nem-daily" type="number" inputMode="decimal" step="0.01" value={dailyDose} onChange={(e) => setDailyDose(e.target.value)} placeholder="für die Tagesdosis-Anzeige (% heute)" className="h-11" />
          </div>

          <div className="space-y-2">
            <Label htmlFor="nem-notes">Notizen <span className="text-muted-foreground font-normal">(optional)</span></Label>
            <Input id="nem-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Wirkung, Einnahmezeitpunkt…" className="h-11" />
          </div>

          <Button size="lg" className="w-full" onClick={submit} disabled={!name.trim() || createSupplement.isPending}>
            <Plus className="h-5 w-5 mr-2" />
            NEM anlegen
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
