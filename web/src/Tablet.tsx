import { useEffect, useState, type ReactNode } from 'react'
import { Activity, Car, MapPinned, Settings, Warehouse, X } from 'lucide-react'
import { Logo } from '@/components/Logo'
import { Button } from '@/components/ui'
import { nui } from '@/lib/nui'
import { getState, useDirty, useStore } from '@/lib/store'
import { cn } from '@/lib/utils'
import { OverviewPage } from '@/pages/Overview'
import { CarsPage } from '@/pages/Cars'
import { LocationsPage } from '@/pages/Locations'
import { SettingsPage } from '@/pages/Settings'

export type Page = 'overview' | 'cars' | 'locations' | 'settings'

const PAGES: { id: Page; label: string; subtitle: string; icon: ReactNode; section?: 'cars' | 'barns' | 'settings' }[] = [
  { id: 'overview', label: 'Overview', subtitle: 'Every barn and what is in it', icon: <Activity /> },
  { id: 'cars', label: 'Cars', subtitle: 'What can be found, and how likely', icon: <Car />, section: 'cars' },
  { id: 'locations', label: 'Locations', subtitle: 'Where the barns stand', icon: <MapPinned />, section: 'barns' },
  { id: 'settings', label: 'Settings', subtitle: 'Resets, scope, condition and restore steps', icon: <Settings />, section: 'settings' },
]

// Same shell as bakery_racing and bakery_boosting: icon sidebar with the B-snap on top, a draggable header,
// and the page below it.
export function Tablet({ hidden }: { hidden: boolean }) {
  const data = useStore((s) => s.data)
  const dirty = useDirty()
  const [page, setPage] = useState<Page>('overview')
  const [drag, setDrag] = useState({ x: 0, y: 0 })
  const [dragStart, setDragStart] = useState<{ x: number; y: number } | null>(null)

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && !e.defaultPrevented && !getState().place) nui('close') }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  useEffect(() => {
    if (!dragStart) return
    const move = (e: MouseEvent) => setDrag({ x: e.clientX - dragStart.x, y: e.clientY - dragStart.y })
    const up = () => setDragStart(null)
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
    return () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up) }
  }, [dragStart])

  if (!data) return null
  const current = PAGES.find((p) => p.id === page)!
  const dot = (p: (typeof PAGES)[number]) => !!p.section && (p.section === 'settings' ? dirty.settings || dirty.paints : dirty[p.section])

  return (
    <div className={cn('fixed inset-0 flex items-center justify-center p-6', hidden && 'invisible')}>
      <div
        className="fade-up relative flex h-full max-h-[780px] w-full max-w-[1240px] overflow-hidden rounded-lg border border-white/[0.07] bg-panel shadow-[0_24px_64px_rgba(0,0,0,0.85)]"
        style={{ transform: `translate(${drag.x}px, ${drag.y}px)` }}
      >
        <nav className="flex w-16 shrink-0 flex-col items-center gap-1 border-r border-white/[0.06] bg-panel pb-4">
          {/* same height as the header, so the two divider lines sit level */}
          <div className="mb-2 flex h-[69px] w-full shrink-0 items-center justify-center border-b border-white/[0.05]"><Logo className="size-9" /></div>
          {PAGES.filter((p) => p.id !== 'settings').map((p) => (
            <NavButton key={p.id} active={page === p.id} dirty={dot(p)} label={p.label} onClick={() => setPage(p.id)}>{p.icon}</NavButton>
          ))}
          <div className="flex-1" />
          <NavButton active={page === 'settings'} dirty={dot(PAGES[3])} label="Settings" onClick={() => setPage('settings')}><Settings /></NavButton>
        </nav>

        <div className="flex min-w-0 flex-1 flex-col">
          <header
            onMouseDown={(e) => setDragStart({ x: e.clientX - drag.x, y: e.clientY - drag.y })}
            className={cn('flex h-[69px] shrink-0 items-center justify-between border-b border-white/[0.05] bg-panel px-6', dragStart ? 'cursor-grabbing' : 'cursor-grab')}
          >
            <div>
              <h1 className="text-[20px] leading-none font-black tracking-tight uppercase">{current.label}</h1>
              <p className="mt-1.5 text-[10.5px] font-bold tracking-[0.14em] text-white/45 uppercase">{current.subtitle}</p>
            </div>
            <div className="flex items-center gap-2" onMouseDown={(e) => e.stopPropagation()}>
              <div className="flex h-8 items-center gap-2 rounded-md bg-white/[0.06] pr-3 pl-2.5">
                <Warehouse className="size-3.5 text-white/60" />
                <span className="tnum text-[13px] font-black">{data.barns.length}</span>
                <span className="text-[10px] font-extrabold tracking-[0.08em] text-white/40 uppercase">{data.barns.length === 1 ? 'barn' : 'barns'}</span>
              </div>
              <div className="flex h-8 items-center gap-2 rounded-md bg-white/[0.06] px-3">
                <span className="size-1.5 rounded-full bg-good" />
                <span className="text-[12px] font-extrabold tracking-[0.04em] uppercase">{data.me?.name ?? 'Admin'}</span>
              </div>
              <Button variant="ghost" size="icon" title="Close" onClick={() => nui('close')}><X /></Button>
            </div>
          </header>

          <main key={page} className="fade-up relative min-h-0 flex-1 overflow-hidden bg-panel-2">
            {page === 'overview' && <OverviewPage go={setPage} />}
            {page === 'cars' && <CarsPage />}
            {page === 'locations' && <LocationsPage />}
            {page === 'settings' && <SettingsPage />}
          </main>
        </div>
      </div>
    </div>
  )
}

function NavButton({ active, dirty, label, onClick, children }: { active: boolean; dirty?: boolean; label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'group relative flex size-10 items-center justify-center rounded-md transition-all duration-150 [&_svg]:size-[18px]',
        active ? 'bg-white text-ink' : 'text-white/45 hover:bg-white/[0.07] hover:text-white',
      )}
    >
      {children}
      {dirty && <span className="pulse-dot absolute top-1.5 right-1.5 size-1.5 rounded-full bg-warn" />}
      <span className="pointer-events-none absolute left-full z-50 ml-3 rounded-[5px] bg-white px-2 py-1 text-[10.5px] font-extrabold tracking-[0.07em] whitespace-nowrap text-ink uppercase opacity-0 shadow-lg transition-opacity group-hover:opacity-100">
        {label}
      </span>
    </button>
  )
}
