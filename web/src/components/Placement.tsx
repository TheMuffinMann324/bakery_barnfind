import { useEffect, type ReactNode } from 'react'
import { AlertTriangle, ArrowDownToLine, MoveVertical } from 'lucide-react'
import { Logo } from '@/components/Logo'
import { nui } from '@/lib/nui'
import { Badge, Kbd } from '@/components/ui'
import { cn } from '@/lib/utils'
import type { PlaceState } from '@/lib/types'

// Shown over the game while the placement editor runs (client/gizmo.lua). The menu itself is hidden then.
// While the placement editor runs the menu is hidden. Aiming (default): the game has the mouse and the barn follows the
// crosshair. Left Alt gives this page the mouse (NUI focus, as in bakery_racing's editor), so it reports the cursor
// and the keys the game can no longer see, and the barn is positioned with the gizmo.
function useFocusedInput(active: boolean) {
  useEffect(() => {
    if (!active) return
    let last = { x: 0.5, y: 0.5, down: false }
    let dirty = false
    let raf = 0
    const flush = () => { raf = 0; if (dirty) { dirty = false; nui('gizmo:pointer', last, 1500) } }
    const queue = () => { dirty = true; if (!raf) raf = requestAnimationFrame(flush) }
    const at = (e: MouseEvent, down: boolean) => { last = { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight, down }; queue() }
    const move = (e: MouseEvent) => at(e, (e.buttons & 1) === 1)
    const down = (e: MouseEvent) => { if (e.button === 0) at(e, true) }
    const up = (e: MouseEvent) => { if (e.button === 0) at(e, false) }
    const release = () => { last = { ...last, down: false }; queue() }
    const key = (e: KeyboardEvent) => {
      const name = e.key === 'Alt' ? 'alt' : e.key === 'Enter' ? 'enter' : e.key === 'Escape' ? 'escape' : null
      if (!name) return
      e.preventDefault()
      e.stopPropagation()
      if (e.type === 'keydown' && !e.repeat) nui('gizmo:key', { key: name }, 1500)
    }
    window.addEventListener('mousemove', move, true)
    window.addEventListener('mousedown', down, true)
    window.addEventListener('mouseup', up, true)
    window.addEventListener('blur', release)
    window.addEventListener('keydown', key, true)
    window.addEventListener('keyup', key, true)
    return () => {
      window.removeEventListener('mousemove', move, true)
      window.removeEventListener('mousedown', down, true)
      window.removeEventListener('mouseup', up, true)
      window.removeEventListener('blur', release)
      window.removeEventListener('keydown', key, true)
      window.removeEventListener('keyup', key, true)
      if (raf) cancelAnimationFrame(raf)
    }
  }, [active])
}

export function Placement({ state }: { state: PlaceState }) {
  useFocusedInput(!!state.focus)
  const uneven = (state.slope ?? 0) > 1.2
  const read = (label: string, value: number | undefined, unit = '') => (
    <div className="min-w-[68px]">
      <div className="text-[9.5px] font-extrabold tracking-[0.16em] text-white/40 uppercase">{label}</div>
      <div className="tnum text-[17px] leading-tight font-black">{value !== undefined ? value.toFixed(label === 'H' ? 1 : 2) : '–'}<span className="ml-0.5 text-[10px] text-white/35">{unit}</span></div>
    </div>
  )

  return (
    <div className="pointer-events-none fixed inset-0 z-30">
      <div className="absolute top-6 left-1/2 -translate-x-1/2">
        <div className="pop-in flex items-center gap-5 rounded-lg border border-white/[0.07] bg-panel/92 px-5 py-3 shadow-[0_12px_40px_rgba(0,0,0,0.7)] backdrop-blur-md">
          <Logo className="size-9 shrink-0" />
          <div className="min-w-[150px]">
            <div className="text-[10px] font-extrabold tracking-[0.16em] text-white/40 uppercase">Placing a barn</div>
            <div className="text-[20px] leading-tight font-black tracking-tight uppercase">{state.label || 'Barn'}</div>
          </div>
          <div className="flex gap-4 border-l border-white/[0.08] pl-5">
            {read('X', state.x)}
            {read('Y', state.y)}
            {read('Z', state.z)}
            {read('H', state.w, '°')}
          </div>
        </div>
        <div className="mt-2 flex items-center justify-center gap-2">
          <Badge tone={state.focus ? 'solid' : 'default'} className="h-6 bg-panel/92 px-2.5 backdrop-blur-md">
            {state.focus ? 'Gizmo: drag the handles' : 'Aiming: the barn follows the crosshair'}
          </Badge>
          <Badge tone={state.autoGround ? 'good' : 'warn'} className="h-6 bg-panel/92 px-2.5 backdrop-blur-md">
            {state.autoGround ? <><ArrowDownToLine /> Following the ground</> : <><MoveVertical /> Free height</>}
          </Badge>
          {uneven && (
            <Badge tone="warn" className="h-6 bg-panel/92 px-2.5 backdrop-blur-md"><AlertTriangle /> Uneven ground · {(state.slope ?? 0).toFixed(1)} m</Badge>
          )}
        </div>
      </div>

      <div className="absolute bottom-6 left-1/2 flex max-w-[94vw] -translate-x-1/2 flex-wrap items-center justify-center gap-x-4 gap-y-2 rounded-lg border border-white/[0.07] bg-panel/92 px-4 py-2.5 shadow-[0_12px_40px_rgba(0,0,0,0.7)] backdrop-blur-md">
        {state.focus ? (
          <>
            <Keys rows={[[['Drag'], <span key="a">The <i className="text-[#f5555a] not-italic">arrows</i> slide it, the square moves it on the ground, the ring turns it</span>]]} />
            <span className="h-5 w-px bg-white/[0.1]" />
            <Keys rows={[[['Alt'], 'Back to aiming']]} />
          </>
        ) : (
          <>
            <Keys rows={[[['Mouse'], 'Aim'], [['W', 'A', 'S', 'D'], 'Fly'], [['Space', 'Ctrl'], 'Up / down'], [['Shift'], 'Fast'], [['Ctrl', 'Wheel'], `Speed ${(state.speed ?? 1).toFixed(2)}x`]]} />
            <span className="h-5 w-px bg-white/[0.1]" />
            <Keys rows={[[['Alt'], 'Position it with the gizmo']]} />
          </>
        )}
        <span className="h-5 w-px bg-white/[0.1]" />
        <span className="flex items-center gap-1.5 text-[11px] font-bold text-white"><Kbd>Enter</Kbd> Save</span>
        <span className="flex items-center gap-1.5 text-[11px] font-bold text-white/55"><Kbd className="bg-white/40">Esc</Kbd> Cancel</span>
      </div>
    </div>
  )
}

function Keys({ rows }: { rows: [string[], ReactNode][] }) {
  return (
    <>
      {rows.map(([keys, label], i) => (
        <span key={i} className="flex items-center gap-1.5 whitespace-nowrap">
          <span className="flex gap-1">{keys.map((k) => <Kbd key={k} className={cn(k === 'Drag' && 'bg-white/90')}>{k}</Kbd>)}</span>
          <span className="text-[11.5px] font-bold text-white">{label}</span>
        </span>
      ))}
    </>
  )
}
