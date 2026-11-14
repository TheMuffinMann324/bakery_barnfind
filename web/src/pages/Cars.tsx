import { useEffect, useMemo, useState } from 'react'
import { Check, Loader2, Plus, Scale, Search, Trash2, X } from 'lucide-react'
import { Badge, Button, Card, Label, ListCard, ListRow, Modal, SaveBar, SectionTitle, Stepper, Switch, Warning } from '@/components/ui'
import { checkModel, ensureLabels, toast, useDraft, useStore } from '@/lib/store'
import type { Car } from '@/lib/types'
import { cn, titleCase } from '@/lib/utils'

const COLS = '36px minmax(0,1.5fr) 122px 128px minmax(0,1.1fr) 92px 44px 36px'

type Rarity = { label: string; tone: 'default' | 'bronze' | 'silver' | 'gold'; bar: string }
// Rarity compares a car's chance with an even split of the pool, so it stays true however many cars there are
// and however the weights are edited: a car twice as likely as average is Common, a tenth as likely is Legendary.
export function rarity(chance: number, cars: number): Rarity {
  const ratio = cars > 0 ? chance / (100 / cars) : 0
  if (ratio >= 1.2) return { label: 'Common', tone: 'default', bar: 'bg-white/30' }
  if (ratio >= 0.75) return { label: 'Uncommon', tone: 'bronze', bar: 'bg-bronze' }
  if (ratio >= 0.35) return { label: 'Rare', tone: 'silver', bar: 'bg-silver' }
  return { label: 'Legendary', tone: 'gold', bar: 'bg-gold' }
}

export function CarsPage() {
  const { draft: cars, dirty, update, save, discard } = useDraft('cars')
  const labels = useStore((s) => s.labels)
  const [query, setQuery] = useState('')
  const [adding, setAdding] = useState(false)

  useEffect(() => { ensureLabels(cars.map((c) => c.model)) }, [cars])

  const total = useMemo(() => cars.reduce((n, c) => n + (c.enabled && c.weight > 0 ? c.weight : 0), 0), [cars])
  const chance = (c: Car) => (c.enabled && c.weight > 0 && total > 0 ? (c.weight / total) * 100 : 0)
  const label = (m: string) => labels[m]?.label ?? titleCase(m)

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return cars.map((c, i) => ({ c, i })).filter(({ c }) => !q || c.model.includes(q) || label(c.model).toLowerCase().includes(q))
  }, [cars, query, labels]) // eslint-disable-line react-hooks/exhaustive-deps

  const live = cars.filter((c) => c.enabled && c.weight > 0)
  const bar = [...live].sort((a, b) => b.weight - a.weight)
  const top = Math.max(1, ...live.map((c) => chance(c)))
  const missing = cars.filter((c) => labels[c.model] && !labels[c.model].ok)

  const set = (i: number, patch: Partial<Car>) => update((d) => { Object.assign(d[i], patch) })

  return (
    <div className="h-full overflow-y-auto p-6">
      {live.length === 0 && <Warning>No car is switched on with a weight above zero, so a barn would be empty.</Warning>}
      {missing.length > 0 && <Warning>{missing.map((c) => c.model).join(', ')} {missing.length === 1 ? 'is' : 'are'} not a vehicle in this game build, so a barn that rolled {missing.length === 1 ? 'it' : 'one'} would show nothing.</Warning>}

      <SectionTitle
        text="Every find is rolled from this pool. A car's chance is its weight divided by the total of the cars that are switched on."
        action={
          <>
            <div className="relative w-56">
              <Search className="pointer-events-none absolute top-1/2 left-3 size-3.5 -translate-y-1/2 text-white/25" />
              <input className="field field-sm pl-8" placeholder="Search cars" value={query} onChange={(e) => setQuery(e.target.value)} />
              {query && <button className="absolute top-1/2 right-2.5 -translate-y-1/2 text-white/30 hover:text-white" onClick={() => setQuery('')}><X className="size-3.5" /></button>}
            </div>
            <Button variant="outline" title="Give every car the same weight" onClick={() => update((d) => d.forEach((c) => { c.weight = 10 }))}><Scale /> Even out</Button>
            <Button variant="primary" onClick={() => setAdding(true)}><Plus /> Add car</Button>
          </>
        }
      >
        The pool
      </SectionTitle>

      <Card className="mb-4 p-4">
        <div className="mb-2.5 flex items-baseline justify-between">
          <span className="text-[10px] font-extrabold tracking-[0.14em] text-white/45 uppercase">The pool at a glance</span>
          <span className="tnum text-[11px] text-white/35">{live.length} cars · total weight {total}</span>
        </div>
        <div className="flex h-3 gap-px overflow-hidden rounded-[3px] bg-white/[0.04]">
          {bar.map((c) => (
            <div key={c.model} title={`${label(c.model)} · ${chance(c).toFixed(1)}%`} className={cn('h-full transition-all', rarity(chance(c), live.length).bar)} style={{ width: `${chance(c)}%` }} />
          ))}
        </div>
        <div className="mt-2.5 flex gap-4 text-[10px] font-extrabold tracking-[0.1em] text-white/40 uppercase">
          {[['Common', 'bg-white/25'], ['Uncommon', 'bg-bronze'], ['Rare', 'bg-silver'], ['Legendary', 'bg-gold']].map(([name, cls]) => (
            <span key={name} className="flex items-center gap-1.5"><span className={cn('size-2 rounded-[2px]', cls)} />{name}</span>
          ))}
        </div>
      </Card>

      <ListCard cols={COLS} head={['#', 'Car', 'Class', 'Weight', 'Chance', 'Rarity', '', '']} count={rows.length} empty={cars.length === 0 ? 'No cars yet. Press Add car.' : 'No car matches that search.'}>
        {rows.map(({ c, i }) => {
          const p = chance(c)
          const r = rarity(p, live.length)
          const info = labels[c.model]
          return (
            <ListRow key={c.model} cols={COLS} className={!c.enabled ? 'opacity-55' : undefined}>
              <span className="tnum flex size-7 items-center justify-center rounded-md bg-white/[0.07] text-[12px] font-black">{i + 1}</span>
              <div className="min-w-0">
                <p className="truncate text-[13px] font-bold">{label(c.model)}</p>
                <p className="truncate font-mono text-[10.5px] text-white/35">{c.model}</p>
              </div>
              <span className="truncate text-[11.5px] text-white/50">{info && !info.ok ? <Badge tone="bad">Not in game</Badge> : info?.class ?? ''}</span>
              <Stepper full value={c.weight} min={0} max={1000} step={1} onChange={(v) => set(i, { weight: v })} />
              <div className="flex items-center gap-2.5">
                <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/[0.06]">
                  <div className={cn('h-full rounded-full transition-all', c.enabled && c.weight > 0 ? r.bar : 'bg-transparent')} style={{ width: `${(p / top) * 100}%` }} />
                </div>
                <span className="tnum w-12 text-right text-[12px] font-bold">{p > 0 ? `${p.toFixed(1)}%` : '—'}</span>
              </div>
              <span>{p > 0 ? <Badge tone={r.tone}>{r.label}</Badge> : <Badge>Off</Badge>}</span>
              <Switch checked={c.enabled} onChange={(v) => set(i, { enabled: v })} />
              <Button size="icon" variant="ghost" className="size-7 hover:text-bad" title="Remove" onClick={() => update((d) => { d.splice(i, 1) })}><Trash2 /></Button>
            </ListRow>
          )
        })}
      </ListCard>

      <SaveBar dirty={dirty} onSave={async () => { if (await save()) toast('Cars saved.', 'success') }} onDiscard={discard} />

      <AddCar open={adding} onClose={() => setAdding(false)} taken={cars.map((c) => c.model)} onAdd={(model, weight) => { update((d) => { d.unshift({ model, weight, enabled: true }) }); setAdding(false) }} />
    </div>
  )
}

function AddCar({ open, onClose, taken, onAdd }: { open: boolean; onClose: () => void; taken: string[]; onAdd: (model: string, weight: number) => void }) {
  const labels = useStore((s) => s.labels)
  const [model, setModel] = useState('')
  const [weight, setWeight] = useState(5)
  const [checking, setChecking] = useState(false)
  useEffect(() => { if (open) { setModel(''); setWeight(5) } }, [open])

  const key = model.trim().toLowerCase().replace(/\s/g, '')
  const info = key ? labels[key] : undefined
  const dupe = taken.includes(key)
  const valid = /^[a-z0-9_]{1,32}$/.test(key)

  async function check() {
    if (!valid) return
    setChecking(true)
    await checkModel(key)
    setChecking(false)
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Add a car"
      subtitle="Any vehicle model in the game, including add-on cars you stream. Check it before you add it."
      footer={<><Button variant="ghost" onClick={onClose}>Cancel</Button><Button variant="primary" disabled={!valid || dupe || info?.ok === false} onClick={() => onAdd(key, weight)}><Check /> Add car</Button></>}
    >
      <div className="space-y-4">
        <div>
          <Label hint={dupe ? <span className="text-warn">Already in the list</span> : info?.ok ? <span className="text-good">{info.label}{info.class ? ` · ${info.class}` : ''}</span> : info && !info.ok ? <span className="text-bad">Not found in this game build</span> : undefined}>Model name</Label>
          <div className="flex gap-2">
            <input autoFocus className="field font-mono text-xs" maxLength={32} placeholder="e.g. btype3" value={model} onChange={(e) => setModel(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') check() }} />
            <Button variant="outline" className="h-9" disabled={!valid || checking} onClick={check}>{checking ? <Loader2 className="animate-spin" /> : <Search />} Check</Button>
          </div>
        </div>
        <div>
          <Label hint="Higher is more common">Weight</Label>
          <Stepper full value={weight} min={0} max={1000} step={1} onChange={setWeight} />
        </div>
      </div>
    </Modal>
  )
}
