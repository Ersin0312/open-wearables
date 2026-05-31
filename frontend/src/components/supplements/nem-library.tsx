import { useEffect, useMemo, useState } from 'react';
import { Pencil, Search, Trash2, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { useSupplements, useUpdateSupplement, useDeleteSupplement } from '@/hooks/api/use-supplements';
import { CATEGORY_LABELS, CATEGORY_ORDER, UNIT_OPTIONS } from '@/lib/supplements/shared';
import type {
  Supplement,
  SupplementCategory,
  Unit,
} from '@/lib/api/services/supplements.service';

const selectClass =
  'h-11 w-full rounded-md border border-input bg-background px-3 text-sm focus:outline-none focus:ring-2 focus:ring-ring';

// NEM library: search + grouped list. Click a NEM name to edit
// name / brand / category / dose / unit / daily dose. Works for seeded and
// custom entries (edits are persisted; a re-seed never overwrites them).
// Rendered inside a dialog, so no Card wrapper / collapse toggle here.
export function NemLibrarySection({ userId }: { userId: string }) {
  const [search, setSearch] = useState('');
  const [editTarget, setEditTarget] = useState<Supplement | null>(null);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const { data: supplements } = useSupplements(userId);
  const deleteSupplement = useDeleteSupplement();

  const grouped = useMemo(() => {
    const tokens = search.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const filtered = (supplements ?? []).filter((s) => {
      if (tokens.length === 0) return true;
      const hay = `${s.name} ${s.brand ?? ''}`.toLowerCase();
      return tokens.every((t) => hay.includes(t));
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
    <div className="space-y-3">
      <p className="text-xs text-muted-foreground">
        Auf einen NEM tippen, um Name, Hersteller oder Dosis zu bearbeiten.
      </p>
      <>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              type="text"
              className="h-11 text-base pl-9"
              placeholder="Suche (Name oder Hersteller)…"
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
                aria-label="Suche löschen"
              >
                <X className="h-4 w-4" />
              </button>
            )}
          </div>

          <div className="border border-border/40 rounded-md max-h-80 overflow-y-auto bg-background">
            {grouped.length === 0 ? (
              <p className="text-sm text-muted-foreground text-center p-6">Keine NEMs gefunden</p>
            ) : (
              grouped.map(({ category, label, items }) => (
                <div key={category}>
                  <div className="sticky top-0 text-[10px] font-semibold uppercase tracking-wider text-muted-foreground px-3 py-1.5 bg-card/80 backdrop-blur border-b border-border/30">
                    {label}
                  </div>
                  {items.map((s) => {
                    const confirming = confirmDeleteId === s.id;
                    return (
                      <div
                        key={s.id}
                        className="px-3 py-2.5 text-sm border-b border-border/10 last:border-b-0 flex items-center justify-between gap-2"
                      >
                        <button
                          type="button"
                          onClick={() => setEditTarget(s)}
                          className="min-w-0 flex-1 text-left hover:opacity-80"
                        >
                          <span className="font-medium truncate block">{s.name}</span>
                          <span className="text-xs text-muted-foreground">
                            {s.brand ? `${s.brand} · ` : ''}
                            {s.default_dose ? `${parseFloat(s.default_dose)} ${s.default_unit}` : 'keine Standarddosis'}
                            {s.recommended_daily_dose
                              ? ` · Ziel ${parseFloat(s.recommended_daily_dose)} ${s.default_unit}/Tag`
                              : ''}
                          </span>
                        </button>

                        {confirming ? (
                          <div className="flex items-center gap-1 shrink-0">
                            <Button
                              variant="ghost"
                              size="sm"
                              className="text-[hsl(var(--destructive-muted))]"
                              disabled={deleteSupplement.isPending}
                              onClick={() =>
                                deleteSupplement.mutate(s.id, {
                                  onSuccess: () => setConfirmDeleteId(null),
                                  onError: () => setConfirmDeleteId(null),
                                })
                              }
                            >
                              Löschen?
                            </Button>
                            <Button variant="ghost" size="sm" onClick={() => setConfirmDeleteId(null)} aria-label="Abbrechen">
                              <X className="h-3.5 w-3.5" />
                            </Button>
                          </div>
                        ) : (
                          <div className="flex items-center gap-0.5 shrink-0">
                            <Button variant="ghost" size="sm" onClick={() => setEditTarget(s)} aria-label="NEM bearbeiten">
                              <Pencil className="h-3.5 w-3.5 text-muted-foreground" />
                            </Button>
                            <Button variant="ghost" size="sm" onClick={() => setConfirmDeleteId(s.id)} aria-label="NEM löschen">
                              <Trash2 className="h-3.5 w-3.5 text-muted-foreground" />
                            </Button>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              ))
            )}
          </div>
      </>

      <EditSupplementDialog supplement={editTarget} onClose={() => setEditTarget(null)} />
    </div>
  );
}

function EditSupplementDialog({
  supplement,
  onClose,
}: {
  supplement: Supplement | null;
  onClose: () => void;
}) {
  const updateSupplement = useUpdateSupplement();
  const [name, setName] = useState('');
  const [brand, setBrand] = useState('');
  const [category, setCategory] = useState<SupplementCategory>('other');
  const [dose, setDose] = useState('');
  const [unit, setUnit] = useState<Unit>('mg');
  const [dailyDose, setDailyDose] = useState('');
  const [notes, setNotes] = useState('');

  // Sync form whenever a different NEM is selected.
  useEffect(() => {
    if (supplement) {
      setName(supplement.name);
      setBrand(supplement.brand ?? '');
      setCategory(supplement.category);
      setDose(supplement.default_dose ? String(parseFloat(supplement.default_dose)) : '');
      setUnit(supplement.default_unit);
      setDailyDose(
        supplement.recommended_daily_dose ? String(parseFloat(supplement.recommended_daily_dose)) : '',
      );
      setNotes(supplement.notes ?? '');
    }
  }, [supplement]);

  if (!supplement) return null;

  const submit = () => {
    if (!name.trim()) return;
    const doseNum = parseFloat(dose);
    const dailyNum = parseFloat(dailyDose);
    updateSupplement.mutate(
      {
        supplementId: supplement.id,
        payload: {
          name: name.trim(),
          brand: brand.trim() || null,
          category,
          default_dose: isNaN(doseNum) ? null : doseNum,
          default_unit: unit,
          recommended_daily_dose: isNaN(dailyNum) ? null : dailyNum,
          notes: notes.trim() || null,
        },
      },
      { onSuccess: onClose },
    );
  };

  return (
    <Dialog open={!!supplement} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogTitle>NEM bearbeiten</DialogTitle>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="edit-name">Name des Produktes</Label>
            <Input id="edit-name" value={name} onChange={(e) => setName(e.target.value)} className="h-11" autoFocus />
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-brand">Hersteller <span className="text-muted-foreground font-normal">(optional)</span></Label>
            <Input id="edit-brand" value={brand} onChange={(e) => setBrand(e.target.value)} placeholder="z. B. Sunday Natural" className="h-11" />
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-category">Kategorie</Label>
            <select id="edit-category" className={selectClass} value={category} onChange={(e) => setCategory(e.target.value as SupplementCategory)}>
              {CATEGORY_ORDER.map((c) => (
                <option key={c} value={c}>{CATEGORY_LABELS[c]}</option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="edit-dose">Standard-Dosis</Label>
              <Input id="edit-dose" type="number" inputMode="decimal" step="0.01" value={dose} onChange={(e) => setDose(e.target.value)} className="h-11" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-unit">Einheit</Label>
              <select id="edit-unit" className={selectClass} value={unit} onChange={(e) => setUnit(e.target.value as Unit)}>
                {UNIT_OPTIONS.map((u) => (
                  <option key={u.value} value={u.value}>{u.label}</option>
                ))}
              </select>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-daily">
              Empfohlene Tagesdosis <span className="text-muted-foreground font-normal">(optional, in {unit})</span>
            </Label>
            <Input id="edit-daily" type="number" inputMode="decimal" step="0.01" value={dailyDose} onChange={(e) => setDailyDose(e.target.value)} className="h-11" />
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-notes">Notizen <span className="text-muted-foreground font-normal">(optional)</span></Label>
            <Input id="edit-notes" value={notes} onChange={(e) => setNotes(e.target.value)} className="h-11" />
          </div>

          <Button size="lg" className="w-full" onClick={submit} disabled={!name.trim() || updateSupplement.isPending}>
            Änderungen speichern
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
