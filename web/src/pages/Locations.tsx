import { useEffect, useState, type ReactNode } from 'react'
import { ChevronDown, MapPinned, Navigation, Plus, Settings2, Trash2, Warehouse } from 'lucide-react'
import { Badge, Button, Confirm, SaveBar, SectionTitle, Segmented, Switch, Warning } from '@/components/ui'
import { nui } from '@/lib/nui'
import { ensureLabels, toast, useDraft, useStore } from '@/lib/store'
import type { Barn, Placement } from '@/lib/types'
import { cn, isPlaced, titleCase, uid } from '@/lib/utils'

export function LocationsPage() {
  const { draft: barns, dirty, update, save, discard } = useDraft('barns')
  const { draft: cars } = useDraft('cars')
  const labels = useStore((s) => s.labels)
  const [open, setOpen] = useState<string | null>(null)
  const [removing, setRemoving] = useState<Barn | null>(null)

  useEffect(() => { ensureLabels(cars.map((c) => c.model)) }, [cars])

  const set = (id: string, fn: (b: Barn) => void) => update((d) => { const b = d.find((x) => x.id === id); if (b) fn(b) })
  const label = (m: string) => labels[m]?.label ?? titleCase(m)
  const unique = (name: string) => {
    const taken = new Set(barns.map((b) => b.name))
    let out = name
    for (let n = 2; taken.has(out); n++) out = `${name} ${n}`
    return out
  }

  // A new barn starts in the placement editor, in front of you. Cancel it and nothing is added.
  async function newBarn() {
    const area = await nui<{ label?: string }>('admin:area')
    const res = await nui<Placement>('admin:place', { label: 'New barn' }, 0)
    if (!res || res.cancelled) return
    const id = uid('barn')
    update((d) => { d.push({ id, name: unique(area?.label || `Barn ${d.length + 1}`), x: res.x, y: res.y, z: res.z, w: res.w, enabled: true }) })
    setOpen(id)
  }

  async function place(b: Barn) {
    const res = await nui<Placement>('admin:place', { start: isPlaced(b) ? { x: b.x, y: b.y, z: b.z, w: b.w } : undefined, label: b.name }, 0)
    if (!res || res.cancelled) return
    set(b.id, (x) => { x.x = res.x; x.y = res.y; x.z = res.z; x.w = res.w })
  }

  const live = barns.filter((b) => b.enabled && isPlaced(b)).length

  return (
    <div className="h-full overflow-y-auto p-6">
      {barns.length > 0 && live === 0 && <Warning>None of your barns is placed and switched on, so none will appear in the world.</Warning>}

      <SectionTitle
        text="Each barn is placed in a free cam: it follows your crosshair, and Left Alt gives you the gizmo to position it. Save to put them in the world."
        action={<Button variant="primary" onClick={newBarn}><Plus /> New barn</Button>}
      >
        Barns <span className="tnum ml-1 text-white/35">{barns.length}</span>
      </SectionTitle>

      <div className="space-y-2">
        {barns.map((b, n) => {
          const expanded = open === b.id
          return (
            <Entry
              key={b.id}
              expanded={expanded}
              off={!b.enabled}
              head={
                <>
                  <span className="tnum flex size-8 shrink-0 items-center justify-center rounded-md bg-white/[0.07] text-[13px] font-black">{n + 1}</span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[13.5px] font-black tracking-tight uppercase">{b.name}</p>
                    <p className="tnum mt-1 text-[11px] text-white/40">{isPlaced(b) ? `${b.x.toFixed(1)}, ${b.y.toFixed(1)}, ${b.z.toFixed(1)} · ${Math.round(b.w)}°` : 'No position yet'}</p>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <Badge tone={isPlaced(b) ? 'good' : 'warn'}>{isPlaced(b) ? 'Placed' : 'Not placed'}</Badge>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <Switch checked={b.enabled} title={b.enabled ? 'Switched on' : 'Switched off'} onChange={(v) => set(b.id, (x) => { x.enabled = v })} />
                    <Button size="sm" variant={isPlaced(b) ? 'outline' : 'primary'} onClick={() => place(b)}><MapPinned /> {isPlaced(b) ? 'Move' : 'Place'}</Button>
                    <Button size="sm" variant="ghost" title="Teleport there" disabled={!isPlaced(b)} onClick={() => nui('admin:teleport', b)}><Navigation /></Button>
                    <Button size="sm" variant={expanded ? 'primary' : 'outline'} onClick={() => setOpen(expanded ? null : b.id)}><Settings2 /><ChevronDown className={cn('transition-transform', expanded && 'rotate-180')} /></Button>
                  </div>
                </>
              }
            >
              <div className="grid grid-cols-2 gap-x-6 gap-y-4">
                <div className="space-y-4">
                  <F label="Name">
                    <input className="field field-sm" maxLength={48} value={b.name} onChange={(e) => set(b.id, (x) => { x.name = e.target.value })} />
                  </F>
                  <F label="Position" hint="Move: aim the barn where you want it, then press Left Alt and use the gizmo to place it and turn the doors">
                    <p className="tnum flex h-8 items-center rounded-[5px] border border-white/[0.06] bg-black/40 px-3 text-[12px] text-white/70">
                      {isPlaced(b) ? `${b.x.toFixed(2)}, ${b.y.toFixed(2)}, ${b.z.toFixed(2)} · ${Math.round(b.w)}°` : 'Not placed yet'}
                    </p>
                  </F>
                </div>

                <div className="space-y-4">
                  <F label="Car pool" hint={b.pool?.length ? `${b.pool.length} picked. Only these cars can turn up here` : 'Every car that is switched on in Cars can turn up here'}>
                    <Segmented
                      value={b.pool ? 'some' : 'all'}
                      onChange={(v) => set(b.id, (x) => { x.pool = v === 'all' ? undefined : (x.pool ?? []) })}
                      options={[{ value: 'all', label: 'All cars' }, { value: 'some', label: 'Only these' }]}
                    />
                    {b.pool && (
                      <div className="mt-2.5 flex max-h-36 flex-wrap gap-1 overflow-y-auto">
                        {cars.map((c) => {
                          const on = b.pool!.includes(c.model)
                          return (
                            <button
                              key={c.model}
                              type="button"
                              onClick={() => set(b.id, (x) => { x.pool = on ? x.pool!.filter((m) => m !== c.model) : [...x.pool!, c.model] })}
                              className={cn('h-6 rounded-[4px] px-2 text-[10px] font-extrabold tracking-[0.06em] uppercase transition', on ? 'bg-white text-ink' : 'bg-white/[0.06] text-white/45 hover:text-white', !c.enabled && 'opacity-50')}
                            >
                              {label(c.model)}
                            </button>
                          )
                        })}
                      </div>
                    )}
                  </F>
                </div>
              </div>

              <div className="mt-4 flex items-center justify-end border-t border-white/[0.06] pt-3">
                <Button size="sm" variant="ghost" className="hover:text-bad" onClick={() => setRemoving(b)}><Trash2 /> Delete barn</Button>
              </div>
            </Entry>
          )
        })}
        {barns.length === 0 && (
          <div className="flex flex-col items-center gap-3 rounded-lg border border-dashed border-white/[0.08] py-14 text-center">
            <Warehouse className="size-6 text-white/25" />
            <div>
              <p className="text-[12.5px] font-extrabold tracking-[0.06em] text-white/65 uppercase">No barns yet</p>
              <p className="mt-1 text-xs text-white/30">Press New barn, then drag the gizmo to put it where you want it.</p>
            </div>
          </div>
        )}
      </div>

      <SaveBar dirty={dirty} onSave={async () => { if (await save()) toast('Barns saved.', 'success') }} onDiscard={discard} />

      <Confirm
        open={!!removing}
        onClose={() => setRemoving(null)}
        title={`Delete ${removing?.name ?? 'this barn'}?`}
        text="Its find history goes with it. Save afterwards to make it stick."
        confirm="Delete"
        onConfirm={() => removing && update((d) => { const i = d.findIndex((x) => x.id === removing.id); if (i >= 0) d.splice(i, 1) })}
      />
    </div>
  )
}

function Entry({ head, expanded, off, children }: { head: ReactNode; expanded: boolean; off: boolean; children: ReactNode }) {
  return (
    <div className={cn('overflow-hidden rounded-lg border bg-white/[0.025] transition-colors', expanded ? 'border-white/[0.16]' : 'border-white/[0.06]')}>
      <div className={cn('flex items-center gap-3 px-4 py-3', off && 'opacity-55')}>{head}</div>
      {expanded && <div className="fade-up border-t border-white/[0.06] bg-black/20 p-4">{children}</div>}
    </div>
  )
}

function F({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="min-w-0 space-y-1.5">
      <p className="text-[9.5px] font-extrabold tracking-[0.14em] text-white/45 uppercase">{label}</p>
      {children}
      {hint && <p className="text-[10.5px] text-white/35">{hint}</p>}
    </div>
  )
}
