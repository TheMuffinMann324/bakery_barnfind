import { useEffect, useMemo, useState } from 'react'
import { Car, Hourglass, MapPinned, Navigation, RotateCcw, Warehouse } from 'lucide-react'
import { Badge, Button, Card, Confirm, ListCard, ListRow, SectionTitle, Stat, Warning } from '@/components/ui'
import { call, nui } from '@/lib/nui'
import { applyLive, ensureLabels, refreshLive, toast, useStore } from '@/lib/store'
import type { AdminData, Barn, LiveBarn } from '@/lib/types'
import { coords, formatDuration, formatMinutes, isPlaced, titleCase } from '@/lib/utils'

const COLS = '36px minmax(0,1.4fr) 112px minmax(0,1.5fr) 100px 148px'

function useTick() {
  const [, set] = useState(0)
  useEffect(() => { const t = setInterval(() => set((n) => n + 1), 1000); return () => clearInterval(t) }, [])
}

function status(b: Barn, l?: LiveBarn): { label: string; tone: 'good' | 'warn' | 'solid' | 'default' } {
  if (!isPlaced(b)) return { label: 'Not placed', tone: 'warn' }
  if (!b.enabled) return { label: 'Disabled', tone: 'default' }
  if (l && l.count > 0) return { label: l.scope === 'player' && l.count > 1 ? `${l.count} found` : 'Found', tone: 'solid' }
  return { label: 'Ready', tone: 'good' }
}

export function OverviewPage({ go }: { go: (page: 'cars' | 'locations' | 'settings') => void }) {
  const data = useStore((s) => s.data) as AdminData
  const labels = useStore((s) => s.labels)
  const fetchedAt = useStore((s) => s.fetchedAt)
  const [resetting, setResetting] = useState<Barn | 'all' | null>(null)
  useTick()

  // Status refreshes every few seconds while this page is open.
  useEffect(() => {
    refreshLive()
    const t = setInterval(refreshLive, 5000)
    return () => clearInterval(t)
  }, [])
  useEffect(() => { ensureLabels(data.live.flatMap((l) => l.entries.map((e) => e.car))) }, [data.live])

  const liveById = useMemo(() => new Map(data.live.map((l) => [l.id, l])), [data.live])
  const elapsed = (Date.now() - fetchedAt) / 1000
  const left = (s: number | null) => (s === null ? null : Math.max(0, s - elapsed))

  const placed = data.barns.filter((b) => b.enabled && isPlaced(b))
  const found = data.barns.filter((b) => (liveById.get(b.id)?.count ?? 0) > 0)
  const pool = data.cars.filter((c) => c.enabled && c.weight > 0)
  const emptyPools = data.barns.filter((b) => b.enabled && b.pool?.length && !b.pool.some((m) => pool.some((c) => c.model === m)))

  async function reset(target: Barn | 'all') {
    const res = await call<{ ok: boolean; cleared?: number; live?: AdminData['live']; error?: string }>('admin:resetBarn', target === 'all' ? {} : { id: target.id })
    if (!res?.ok) return toast(res?.error ?? 'Could not reset.', 'error')
    applyLive(res)
    toast(target === 'all' ? 'Every barn is ready again.' : `${target.name} is ready again.`, 'success')
  }

  const label = (model: string) => labels[model]?.label ?? titleCase(model)

  return (
    <div className="h-full overflow-y-auto p-6">
      <div className="grid grid-cols-4 gap-3">
        <Stat label="Barns" value={`${placed.length}/${data.barns.length}`} sub="Placed and switched on" icon={<Warehouse />} />
        <Stat label="Found now" value={found.length} sub={found.length === 1 ? 'Barn in use' : 'Barns in use'} icon={<MapPinned />} />
        <Stat label="Cars in the pool" value={pool.length} sub={`${data.cars.length} listed`} icon={<Car />} />
        <Stat label="Barns reset" value={data.settings.cooldownMinutes > 0 ? formatMinutes(data.settings.cooldownMinutes) : 'Never'} sub={data.settings.scope === 'global' ? 'One find for everyone' : 'Every player finds their own'} icon={<Hourglass />} />
      </div>

      <div className="mt-5">
        {pool.length === 0 && <Warning>No car is switched on, so nothing can be found. <button className="underline underline-offset-2" onClick={() => go('cars')}>Open Cars</button></Warning>}
        {data.barns.length === 0 && <Warning>There are no barns yet. <button className="underline underline-offset-2" onClick={() => go('locations')}>Place the first one</button></Warning>}
        {data.barns.length > 0 && placed.length === 0 && <Warning>None of your barns is placed and switched on, so none will appear in the world.</Warning>}
        {emptyPools.length > 0 && <Warning>{emptyPools.map((b) => b.name).join(', ')} only {emptyPools.length === 1 ? 'holds' : 'hold'} cars that are switched off, so {emptyPools.length === 1 ? 'it is' : 'they are'} empty.</Warning>}
      </div>

      <SectionTitle
        className="mt-2"
        text="Who has searched what, and when each barn can be searched again."
        action={<Button size="sm" variant="outline" disabled={found.length === 0} onClick={() => setResetting('all')}><RotateCcw /> Reset all</Button>}
      >
        Barns
      </SectionTitle>
      <ListCard cols={COLS} head={['#', 'Barn', 'Status', 'Latest find', 'Resets in', '']} count={data.barns.length} empty="No barns yet.">
        {data.barns.map((b, n) => {
          const l = liveById.get(b.id)
          const st = status(b, l)
          const latest = l?.entries[0]
          const remaining = latest ? left(latest.left) : null
          return (
            <ListRow key={b.id} cols={COLS} className={!b.enabled || !isPlaced(b) ? 'opacity-60' : undefined}>
              <span className="tnum flex size-7 items-center justify-center rounded-md bg-white/[0.07] text-[12px] font-black">{n + 1}</span>
              <div className="min-w-0">
                <p className="truncate text-[13px] font-bold">{b.name}</p>
                <p className="tnum truncate text-[10.5px] text-white/35">{isPlaced(b) ? coords(b) : 'No position yet'}</p>
              </div>
              <span><Badge tone={st.tone}>{st.label}</Badge></span>
              <div className="min-w-0">
                {latest ? (
                  <>
                    <p className="truncate text-[12.5px] font-medium">{label(latest.car)}</p>
                    <p className="truncate text-[10.5px] text-white/35">
                      {latest.name}{(l?.count ?? 0) > 1 ? ` and ${(l?.count ?? 1) - 1} more` : ''} · {l?.scope === 'player' ? 'own find' : 'shared find'}
                    </p>
                  </>
                ) : <span className="text-[12px] text-white/30">Nothing found yet</span>}
              </div>
              <span className="tnum text-[12px] text-white/60">
                {!latest ? '—' : remaining === null ? 'Never' : formatDuration(remaining)}
              </span>
              <div className="flex justify-end gap-1">
                <Button size="sm" variant="ghost" title="Teleport there" disabled={!isPlaced(b)} onClick={() => nui('admin:teleport', b)}><Navigation /></Button>
                <Button size="sm" variant="outline" disabled={!l || l.count === 0} onClick={() => setResetting(b)}><RotateCcw /> Reset</Button>
              </div>
            </ListRow>
          )
        })}
      </ListCard>

      <Card className="mt-5 flex items-center gap-3 px-4 py-3 text-[11.5px] text-white/40">
        Resetting a barn puts it back as it was: doors shut, nothing inside, and ready to be searched. Players near it see it close.
      </Card>

      <Confirm
        open={!!resetting}
        onClose={() => setResetting(null)}
        title={resetting === 'all' ? 'Reset every barn?' : `Reset ${resetting ? resetting.name : ''}?`}
        text={resetting === 'all' ? 'Every find is cleared, for every player. Each barn can be searched again straight away.' : 'Its find is cleared and it can be searched again straight away.'}
        confirm="Reset"
        onConfirm={() => resetting && reset(resetting)}
      />
    </div>
  )
}
