import { useState } from 'react'
import { KeyRound, Clapperboard, Clock, Disc3, Droplets, Eye, Gauge, HeartPulse, Layers, Package, PanelTop, Plus, Ruler, SkipForward, Trash2, Users, Wrench, Hash, Wind, Car as CarIcon, RotateCcw, Hand, Flame, Hammer, Fuel } from 'lucide-react'
import { Button, Card, Confirm, Grid, Row, SaveBar, SectionTitle, Segmented, Stepper, Switch, TextField } from '@/components/ui'
import { CooldownField } from '@/components/Cooldown'
import { toast, useDraft, useStore } from '@/lib/store'
import type { Settings } from '@/lib/types'
import { cn } from '@/lib/utils'

export function SettingsPage() {
  const items = useStore((st) => st.data?.items)
  const itemLabel = (name: string) => items?.find((k) => k.name === name)?.label ?? (name || '?')
  const s = useDraft('settings')
  const p = useDraft('paints')
  const [resetting, setResetting] = useState(false)
  const d = s.draft
  const set = (fn: (x: Settings) => void) => s.update(fn)
  const dirty = s.dirty || p.dirty

  async function saveAll() {
    const results = await Promise.all([s.dirty ? s.save() : true, p.dirty ? p.save() : true])
    if (results.every(Boolean)) toast('Settings saved.', 'success')
  }

  return (
    <div className="h-full overflow-y-auto p-6">
      <div className="mb-5 flex min-h-8 items-center gap-2">
        <p className="mr-auto max-w-[620px] text-[11.5px] leading-relaxed text-white/45">Rules for every barn.</p>
        <Button variant="ghost" onClick={() => setResetting(true)}><RotateCcw /> Defaults</Button>
      </div>

      <Grid title="Barns">
        <Row wide icon={<Users />} title="Who finds a barn" text={d.scope === 'global' ? 'One find for the whole server' : 'Every player finds their own'}>
          <Segmented className="w-full" value={d.scope} onChange={(v) => set((x) => { x.scope = v })} options={[{ value: 'global', label: 'Global' }, { value: 'player', label: 'Per player' }]} />
        </Row>
        <Row icon={<Layers />} title="Barn clutter" text="The tyres, toolboxes, hay and shelves inside">
          <Switch checked={d.dressing} onChange={(v) => set((x) => { x.dressing = v })} />
        </Row>
        <Row icon={<Ruler />} title="Spawn distance" text="Barns appear for a player inside this range">
          <Stepper value={d.spawnDistance} onChange={(v) => set((x) => { x.spawnDistance = v })} step={10} min={60} max={500} unit="m" />
        </Row>
        <Row icon={<Hand />} title="Prompt distance" text="How close to the doors the prompt shows">
          <Stepper value={d.interactDistance} onChange={(v) => set((x) => { x.interactDistance = v })} step={0.1} min={1} max={6} unit="m" />
        </Row>
        <Row icon={<Clapperboard />} title="Reveal cutscene" text="Off opens the barn at once">
          <Switch checked={d.cutscene.enabled} onChange={(v) => set((x) => { x.cutscene.enabled = v })} />
        </Row>
        <Row icon={<SkipForward />} title="Cutscene can be skipped" text="Backspace skips it">
          <Switch checked={d.cutscene.skippable} disabled={!d.cutscene.enabled} onChange={(v) => set((x) => { x.cutscene.skippable = v })} />
        </Row>
        <Row full icon={<Clock />} title="Barn resets" text="How long until a used barn shuts, empties and can be searched again" control="auto">
          <CooldownField value={d.cooldownMinutes} onChange={(v) => set((x) => { x.cooldownMinutes = v })} />
        </Row>
      </Grid>

      <Grid title="Condition of finds" text="How rough the car looks when the doors open. Which tyres and windows are wrecked is rolled for every find.">
        <Row icon={<Droplets />} title="Dirt" text="0 spotless, 15 caked on">
          <Stepper value={d.condition.dirt} onChange={(v) => set((x) => { x.condition.dirt = v })} step={1} min={0} max={15} />
        </Row>
        <Row icon={<Flame />} title="Rust" text="How weathered the paint looks, on cars that support it">
          <Stepper value={d.condition.rust} onChange={(v) => set((x) => { x.condition.rust = v })} step={0.05} min={0} max={1} />
        </Row>
        <Row icon={<Gauge />} title="Body health" text="Lower looks more dented">
          <Stepper value={d.condition.bodyHealth} onChange={(v) => set((x) => { x.condition.bodyHealth = v })} step={25} min={0} max={1000} />
        </Row>
        <Row icon={<HeartPulse />} title="Engine health" text="Lower and it smokes">
          <Stepper value={d.condition.engineHealth} onChange={(v) => set((x) => { x.condition.engineHealth = v })} step={25} min={0} max={1000} />
        </Row>
        <Row icon={<CarIcon />} title="Flat tyres" text="Out of four">
          <Stepper value={d.condition.burstTyres} onChange={(v) => set((x) => { x.condition.burstTyres = v })} step={1} min={0} max={4} />
        </Row>
        <Row icon={<Eye />} title="Smashed windows" text="Out of six panes">
          <Stepper value={d.condition.smashedWindows} onChange={(v) => set((x) => { x.condition.smashedWindows = v })} step={1} min={0} max={6} />
        </Row>
        <Row icon={<Wind />} title="Bonnet ajar" text="How far it is propped open, 0 is shut">
          <Stepper value={d.condition.hoodAjar} onChange={(v) => set((x) => { x.condition.hoodAjar = v })} step={5} min={0} max={100} unit="%" />
        </Row>
        <Row icon={<Hash />} title="Number plate" text="Blank is a blank plate">
          <TextField maxLength={8} placeholder="Blank" value={d.condition.plate} onChange={(v) => set((x) => { x.condition.plate = v.toUpperCase() })} />
        </Row>
      </Grid>

      <section className="mb-6">
        <SectionTitle
          text="The faded paint colours a find can wear. One is picked for each find, matt."
          action={<Button size="sm" variant="secondary" disabled={p.draft.length >= 24} onClick={() => p.update((x) => { x.push({ name: `Paint ${x.length + 1}`, color: '#7a7a72' }) })}><Plus /> Add colour</Button>}
        >
          Paint colours
        </SectionTitle>
        <div className="grid grid-cols-3 gap-2">
          {p.draft.map((c, i) => (
            <Card key={i} className="flex items-center gap-2.5 p-2">
              <label className="relative size-9 shrink-0 cursor-pointer overflow-hidden rounded-md border border-white/[0.1]" style={{ background: c.color }}>
                <input type="color" className="absolute inset-0 size-full cursor-pointer opacity-0" value={c.color} onChange={(e) => p.update((x) => { x[i].color = e.target.value })} />
              </label>
              <input className="field field-sm min-w-0 flex-1" maxLength={24} value={c.name} onChange={(e) => p.update((x) => { x[i].name = e.target.value })} />
              <Button size="icon" variant="ghost" className="size-7 hover:text-bad" title="Remove" onClick={() => p.update((x) => { x.splice(i, 1) })}><Trash2 /></Button>
            </Card>
          ))}
          {p.draft.length === 0 && <p className="col-span-3 rounded-lg border border-dashed border-white/[0.08] py-6 text-center text-[11.5px] text-white/35">No colours, so finds keep their factory paint.</p>}
        </div>
      </section>

      <section className="mb-6">
        <SectionTitle text="Done in this order. A step that is off is skipped. Each step needs the items listed, and uses them up when it is done.">Restore steps</SectionTitle>
        <datalist id="bk-items">
          {(items ?? []).map((it) => <option key={it.name} value={it.name}>{it.label}</option>)}
        </datalist>
        <div className="flex flex-col gap-2">
          {d.restore.stages.map((st, i) => (
            <Card key={st.id} className={cn('p-3', !st.enabled && 'opacity-50')}>
              <div className="flex items-center gap-3">
                <span className="tnum flex size-6 items-center justify-center rounded-md bg-white/[0.06] text-[11px] font-black text-white/55">{i + 1}</span>
                <span className="flex items-center gap-2 text-[13px] font-medium"><StageIcon id={st.id} />{st.label}</span>
                <span className="mr-auto text-[11px] text-white/35">{st.items.length === 0 ? 'No items needed' : st.items.map((it) => `${it.count}x ${itemLabel(it.name)}`).join(', ')}</span>
                <Button size="sm" variant="secondary" disabled={!st.enabled || st.items.length >= 12} onClick={() => set((x) => { x.restore.stages[i].items.push({ name: '', count: 1 }) })}><Plus /> Item</Button>
                <Switch checked={st.enabled} onChange={(v) => set((x) => { x.restore.stages[i].enabled = v })} />
              </div>
              {st.items.length > 0 && (
                <div className="mt-2.5 flex flex-col gap-1.5 border-t border-white/[0.05] pt-2.5 pl-9">
                  {st.items.map((it, j) => {
                    const known = !items?.length || items.some((k) => k.name === it.name)
                    return (
                      <div key={j} className="flex items-center gap-2">
                        <Package className="size-3.5 shrink-0 text-white/30" />
                        <input
                          className={cn('field field-sm min-w-0 flex-1 font-mono', it.name && !known && 'border-warn/60')}
                          list="bk-items" placeholder="item name" maxLength={60} value={it.name}
                          onChange={(e) => set((x) => { x.restore.stages[i].items[j].name = e.target.value.replace(/\s/g, '') })}
                        />
                        {it.name && !known && <span className="text-[10.5px] text-warn">Not an item</span>}
                        <Stepper value={it.count} onChange={(v) => set((x) => { x.restore.stages[i].items[j].count = v })} step={1} min={1} max={1000} unit="x" />
                        <Button size="icon" variant="ghost" className="size-7 hover:text-bad" title="Remove" onClick={() => set((x) => { x.restore.stages[i].items.splice(j, 1) })}><Trash2 /></Button>
                      </div>
                    )
                  })}
                </div>
              )}
            </Card>
          ))}
        </div>
      </section>

      <SaveBar dirty={dirty} onSave={saveAll} onDiscard={() => { s.discard(); p.discard() }} />

      <Confirm
        open={resetting}
        onClose={() => setResetting(false)}
        title="Restore the default settings?"
        text="Restore the built-in gameplay settings and paint colours."
        confirm="Restore"
        onConfirm={async () => { const a = await s.reset(); const b = await p.reset(); if (a && b) toast('Defaults restored.', 'success') }}
      />
    </div>
  )
}

/** The icon for each restore step. */
function StageIcon({ id }: { id: string }) {
  const cls = 'size-4 text-white/30'
  if (id === 'tyres') return <Disc3 className={cls} />
  if (id === 'glass') return <PanelTop className={cls} />
  if (id === 'oil') return <Fuel className={cls} />
  if (id === 'body') return <Hammer className={cls} />
  if (id === 'start') return <KeyRound className={cls} />
  return <Wrench className={cls} />
}
