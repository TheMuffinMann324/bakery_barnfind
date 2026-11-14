import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Check } from 'lucide-react'
import { Kbd } from '@/components/ui'
import { nui, useNui } from '@/lib/nui'
import { grinder, rattle, sfx } from '@/lib/sfx'
import { cn } from '@/lib/utils'

// The hands-on part of restoring (client/minigame.lua runs these). The game renders the car behind this page and
// sends where the parts are on screen: wheel nuts, studs, the new wheel's holes, an oil filter, rust
// on the bodywork. The page has the mouse.

export interface MinigameState {
  kind: 'pump' | 'loosen' | 'tighten' | 'fit' | 'spin' | 'sweep' | 'skill'
  data: {
    title?: string; hint?: string
    pumps?: number
    nuts?: number; ms?: number; band?: [number, number]
    spacing?: number; start?: number; tolerance?: number
    turns?: number; dir?: 'cw' | 'ccw'
    mode?: 'grind' | 'buff'
    hits?: number; speed?: number; speedUp?: number; zone?: number
    progress?: number
  }
}

interface Points { points: { x: number; y: number }[]; radius: number; w: number; h: number }

const event = (name: string, value?: unknown) => nui('mg:event', { name, value }, 1500)
const finish = (result: 'done' | 'cancel') => nui('mg:done', { result }, 1500)

export function Minigame({ state }: { state: MinigameState }) {
  const [pts, setPts] = useState<Points | null>(null)
  useNui<Points>('minigame:points', setPts)

  useEffect(() => {
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); finish('cancel') } }
    window.addEventListener('keydown', key)
    return () => window.removeEventListener('keydown', key)
  }, [])

  // game pixels to page pixels
  const scale = pts ? window.innerHeight / pts.h : 1
  const screen = (i: number) => pts && pts.points[i] && pts.points[i].x >= 0 ? { x: pts.points[i].x * window.innerWidth, y: pts.points[i].y * window.innerHeight } : null
  const radius = Math.max(16, Math.min(46, (pts?.radius ?? 20) * scale))

  return (
    <div className="fixed inset-0 select-none">
      {state.kind === 'pump' && <Pump state={state} />}
      {(state.kind === 'loosen' || state.kind === 'tighten') && <Nuts key={state.kind} state={state} at={screen} radius={radius} />}
      {state.kind === 'fit' && <Fit state={state} at={screen} radius={radius} />}
      {state.kind === 'spin' && <Spin state={state} at={screen} />}
      {state.kind === 'skill' && <Skill state={state} />}
      {state.kind === 'sweep' && <Sweep key={state.data.mode} state={state} />}
    </div>
  )
}

/** The instruction card along the bottom. */
function Card({ title, hint, children, progress }: { title?: string; hint?: string; children?: ReactNode; progress?: string }) {
  return (
    <div className="pointer-events-none fixed bottom-10 left-1/2 w-[440px] -translate-x-1/2 fade-up">
      <div className="rounded-lg border border-white/[0.08] bg-panel/95 px-4 py-3 shadow-[0_18px_48px_rgba(0,0,0,0.6)]">
        <div className="flex items-center gap-3">
          <p className="mr-auto text-[12.5px] font-black tracking-[0.12em] uppercase">{title}</p>
          {progress && <span className="tnum text-[11px] font-extrabold text-white/55">{progress}</span>}
        </div>
        {hint && <p className="mt-1 text-[11px] leading-snug text-white/45">{hint}</p>}
        {children}
        <div className="mt-2.5 flex items-center gap-1.5 text-[10px] font-bold tracking-[0.08em] text-white/35 uppercase">
          <Kbd>Esc</Kbd> Stop
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------- jack
function Pump({ state }: { state: MinigameState }) {
  const total = state.data.pumps ?? 7
  const [n, setN] = useState(0)
  const [down, setDown] = useState(false)
  const nRef = useRef(0)

  useEffect(() => {
    const pump = () => {
      if (nRef.current >= total) return
      nRef.current += 1
      setN(nRef.current)
      setDown(true)
      setTimeout(() => setDown(false), 120)
      sfx.pump()
      // ease the car up a little per stroke
      const from = (nRef.current - 1) / total, to = nRef.current / total
      const t0 = performance.now()
      const tick = () => {
        const k = Math.min(1, (performance.now() - t0) / 260)
        event('progress', from + (to - from) * (1 - (1 - k) ** 3))
        if (k < 1) requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
      if (nRef.current >= total) setTimeout(() => finish('done'), 450)
    }
    const mouse = (e: MouseEvent) => { if (e.button === 0) pump() }
    const key = (e: KeyboardEvent) => { if (e.code === 'Space' && !e.repeat) { e.preventDefault(); pump() } }
    window.addEventListener('mousedown', mouse)
    window.addEventListener('keydown', key)
    return () => { window.removeEventListener('mousedown', mouse); window.removeEventListener('keydown', key) }
  }, [total])

  return (
    <>
      <div className="fixed top-1/2 right-16 -translate-y-1/2 fade-up">
        <div className="flex flex-col items-center gap-3 rounded-lg border border-white/[0.08] bg-panel/95 px-5 py-5">
          <p className="text-[9.5px] font-extrabold tracking-[0.16em] text-white/45 uppercase">Lift</p>
          <div className="relative h-56 w-4 overflow-hidden rounded-full bg-white/[0.08]">
            <div className="absolute inset-x-0 bottom-0 rounded-full bg-white transition-[height] duration-300 ease-out" style={{ height: `${(n / total) * 100}%` }} />
          </div>
          <div className={cn('flex size-14 items-center justify-center rounded-full border-2 border-white/25 bg-white/[0.04] text-[10px] font-black tracking-[0.1em] uppercase transition-transform duration-100', down && 'translate-y-1.5 scale-95 border-white/70')}>Pump</div>
        </div>
      </div>
      <Card title={state.data.title} hint={state.data.hint} progress={`${n} / ${total}`} />
    </>
  )
}

// ---------------------------------------------------------------- wheel nuts
type NutState = { value: number; done: boolean; flying?: boolean }

/** Star pattern: from the first nut picked, every next one is across the wheel. */
function starOrder(first: number, n: number) {
  const out: number[] = []
  if (n % 2 === 1) {
    for (let i = 0; i < n; i++) out.push((first + i * 2) % n)
  } else {
    const half = n / 2
    for (let i = 0; i < half; i++) { out.push((first + i) % n); out.push((first + i + half) % n) }
  }
  return out
}

function Nuts({ state, at, radius }: { state: MinigameState; at: (i: number) => { x: number; y: number } | null; radius: number }) {
  const n = state.data.nuts ?? 5
  const ms = state.data.ms ?? 800
  const tighten = state.kind === 'tighten'
  const band = state.data.band ?? [0.74, 0.9]
  const [nuts, setNuts] = useState<NutState[]>(() => Array.from({ length: n }, () => ({ value: 0, done: false })))
  const [holding, setHolding] = useState<number | null>(null)
  const [order, setOrder] = useState<number[] | null>(null)
  const [message, setMessage] = useState<{ text: string; tone: 'bad' | 'good' } | null>(null)
  const [shake, setShake] = useState<number | null>(null)
  const [hintNext, setHintNext] = useState(false)
  const nutsRef = useRef(nuts)
  nutsRef.current = nuts
  const finished = useRef(false)

  const done = nuts.filter((x) => x.done).length
  const next = order ? order.find((i) => !nuts[i].done) : undefined

  const sayTimer = useRef(0)
  const say = (text: string, tone: 'bad' | 'good' = 'bad') => {
    setMessage({ text, tone })
    window.clearTimeout(sayTimer.current)
    sayTimer.current = window.setTimeout(() => setMessage(null), 1600)
  }

  // run the gun while the mouse is held on a nut
  useEffect(() => {
    if (holding === null) return
    const i = holding
    const r = rattle()
    let last = performance.now()
    let raf = 0
    const tick = (now: number) => {
      const dt = now - last
      last = now
      const cur = nutsRef.current[i]
      let v = Math.min(1, cur.value + dt / ms)
      r.pitch(v)
      if (tighten && v >= 1) {
        // past the band and the gun hammered it too far
        sfx.wrong()
        say('Too tight. Backed it off, try again')
        v = 0.35
        setNuts((s) => s.map((x, k) => (k === i ? { ...x, value: v } : x)))
        setHolding(null)
        return
      }
      setNuts((s) => s.map((x, k) => (k === i ? { ...x, value: v } : x)))
      if (!tighten && v >= 1) {
        sfx.nutOff()
        setNuts((s) => s.map((x, k) => (k === i ? { ...x, value: 1, done: true, flying: true } : x)))
        event('nut', i)
        setHolding(null)
        return
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => { cancelAnimationFrame(raf); r.stop() }
  }, [holding, ms, tighten])

  // let go: on tightening, did the needle stop in the band?
  useEffect(() => {
    const up = () => {
      setHolding((h) => {
        if (h !== null && tighten) {
          const v = nutsRef.current[h].value
          if (v >= band[0] && v <= band[1]) {
            sfx.torqued()
            setNuts((s) => s.map((x, k) => (k === h ? { ...x, done: true } : x)))
            event('nut', h)
          } else if (v < band[0]) {
            say('Not tight yet. Keep going')
          }
        }
        return null
      })
    }
    window.addEventListener('mouseup', up)
    return () => window.removeEventListener('mouseup', up)
  }, [tighten, band])

  useEffect(() => {
    if (done === n && !finished.current) {
      finished.current = true
      setTimeout(() => finish('done'), 650)
    }
  }, [done, n])

  const press = (i: number) => {
    if (nuts[i].done) return
    if (tighten) {
      if (!order) {
        setOrder(starOrder(i, n))
      } else if (i !== next) {
        sfx.wrong()
        setShake(i)
        setTimeout(() => setShake(null), 380)
        say('Go across the wheel, in a star')
        setHintNext(true)
        return
      }
      setHintNext(false)
    }
    setHolding(i)
  }

  return (
    <>
      {Array.from({ length: n }, (_, i) => {
        const p = at(i)
        if (!p) return null
        const s = nuts[i]
        return (
          <Nut
            key={i}
            x={p.x} y={p.y} r={radius}
            value={s.value} done={s.done} flying={s.flying}
            tighten={tighten} band={band}
            active={holding === i}
            hint={tighten && hintNext && next === i}
            shake={shake === i}
            onDown={() => press(i)}
          />
        )
      })}
      {message && (
        <div className={cn('pop-in fixed top-[18%] left-1/2 -translate-x-1/2 rounded-md px-3 py-1.5 text-[11px] font-black tracking-[0.1em] uppercase', message.tone === 'bad' ? 'bg-bad/15 text-bad' : 'bg-good/15 text-good')}>{message.text}</div>
      )}
      <Card title={state.data.title} hint={state.data.hint} progress={`${done} / ${n}`}>
        {tighten && (
          <div className="mt-2.5 flex items-center gap-2 text-[10px] font-bold text-white/40">
            <span className="h-1.5 w-8 rounded-full bg-good/80" /> Let go here
          </div>
        )}
      </Card>
    </>
  )
}

/** One wheel nut over the game: a hex nut with a ring. Loosening fills the ring; tightening sweeps a torque needle. */
function Nut({ x, y, r, value, done, flying, tighten, band, active, hint, shake, onDown }: {
  x: number; y: number; r: number; value: number; done: boolean; flying?: boolean; tighten: boolean; band: [number, number]
  active: boolean; hint: boolean; shake: boolean; onDown: () => void
}) {
  const size = r * 2.6
  const c = size / 2
  const ringR = r * 1.15
  const circ = 2 * Math.PI * ringR
  const arc = (from: number, to: number) => {
    const a0 = -Math.PI / 2 + from * Math.PI * 2, a1 = -Math.PI / 2 + to * Math.PI * 2
    const large = to - from > 0.5 ? 1 : 0
    return `M ${c + Math.cos(a0) * ringR} ${c + Math.sin(a0) * ringR} A ${ringR} ${ringR} 0 ${large} 1 ${c + Math.cos(a1) * ringR} ${c + Math.sin(a1) * ringR}`
  }
  const hex = Array.from({ length: 6 }, (_, k) => {
    const a = (Math.PI / 3) * k + Math.PI / 6
    return `${c + Math.cos(a) * r * 0.62},${c + Math.sin(a) * r * 0.62}`
  }).join(' ')
  // the nut turns as the gun runs: anticlockwise off, clockwise on
  const spin = (tighten ? 1 : -1) * value * 900
  const inBand = tighten && value >= band[0] && value <= band[1]

  if (flying) {
    return (
      <div className="pointer-events-none fixed" style={{ left: x - c, top: y - c, width: size, height: size, animation: 'nut-fly 0.6s cubic-bezier(.3,0,.8,.4) forwards' }}>
        <svg width={size} height={size}><polygon points={hex} fill="rgba(255,255,255,0.85)" /></svg>
      </div>
    )
  }

  return (
    <div
      className={cn('fixed cursor-pointer', shake && 'animate-[nut-shake_0.35s_ease-in-out]')}
      style={{ left: x - c, top: y - c, width: size, height: size }}
      onMouseDown={(e) => { if (e.button === 0) { e.preventDefault(); onDown() } }}
    >
      <svg width={size} height={size} className="overflow-visible">
        <circle cx={c} cy={c} r={ringR} fill={active ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.22)'} stroke="rgba(255,255,255,0.14)" strokeWidth={2.5} />
        {tighten && <path d={arc(band[0], band[1])} stroke="#4ade80" strokeOpacity={done ? 0.25 : 0.9} strokeWidth={4} fill="none" strokeLinecap="round" />}
        {!done && value > 0 && (
          tighten
            ? <path d={arc(0, Math.max(0.001, value))} stroke={inBand ? '#4ade80' : '#fff'} strokeWidth={2.5} fill="none" strokeLinecap="round" />
            : <circle cx={c} cy={c} r={ringR} fill="none" stroke="#fff" strokeWidth={3} strokeDasharray={`${circ * value} ${circ}`} transform={`rotate(-90 ${c} ${c})`} strokeLinecap="round" />
        )}
        {tighten && !done && value > 0 && (() => {
          const a = -Math.PI / 2 + value * Math.PI * 2
          return <line x1={c + Math.cos(a) * (ringR - 6)} y1={c + Math.sin(a) * (ringR - 6)} x2={c + Math.cos(a) * (ringR + 6)} y2={c + Math.sin(a) * (ringR + 6)} stroke="#fff" strokeWidth={2.5} strokeLinecap="round" />
        })()}
        <g transform={`rotate(${spin} ${c} ${c})`}>
          <polygon
            points={hex}
            fill={done ? 'rgba(74,222,128,0.18)' : tighten && value === 0 ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.12)'}
            stroke={done ? '#4ade80' : hint ? '#fbbf24' : active ? '#fff' : 'rgba(255,255,255,0.75)'}
            strokeWidth={hint ? 2.5 : 1.8}
            strokeDasharray={tighten && !done && value === 0 ? '4 3' : undefined}
          />
          <circle cx={c} cy={c} r={r * 0.22} fill="rgba(0,0,0,0.45)" />
        </g>
        {done && tighten && <foreignObject x={c - 7} y={c - 7} width={14} height={14}><Check className="size-3.5 text-good" strokeWidth={3} /></foreignObject>}
      </svg>
    </div>
  )
}

// ---------------------------------------------------------------- fitting the wheel
function Fit({ state, at, radius }: { state: MinigameState; at: (i: number) => { x: number; y: number } | null; radius: number }) {
  const n = state.data.nuts ?? 5
  const spacing = state.data.spacing ?? 360 / n
  const tolerance = state.data.tolerance ?? 7
  const [angle, setAngle] = useState(state.data.start ?? 30)
  const [message, setMessage] = useState<string | null>(null)
  const [seating, setSeating] = useState(false)
  const angleRef = useRef(angle)
  const drag = useRef<number | null>(null)
  const wasAligned = useRef(false)

  const off = ((angle % spacing) + spacing) % spacing
  const miss = Math.min(off, spacing - off)
  const aligned = miss <= tolerance

  useEffect(() => {
    if (aligned && !wasAligned.current) sfx.click()
    wasAligned.current = aligned
  }, [aligned])

  // send the angle to the game at most once a frame
  useEffect(() => {
    let raf = 0
    let sent = angleRef.current
    const loop = () => {
      if (angleRef.current !== sent) { sent = angleRef.current; event('angle', sent) }
      raf = requestAnimationFrame(loop)
    }
    raf = requestAnimationFrame(loop)
    return () => cancelAnimationFrame(raf)
  }, [])

  useEffect(() => {
    const turn = (d: number) => { angleRef.current = angleRef.current + d; setAngle(angleRef.current) }
    const down = (e: MouseEvent) => { if (e.button === 0) drag.current = e.clientX }
    const move = (e: MouseEvent) => {
      if (drag.current === null || seating) return
      turn((e.clientX - drag.current) * 0.35)
      drag.current = e.clientX
    }
    const up = (e: MouseEvent) => { if (e.button === 0) drag.current = null }
    const wheel = (e: WheelEvent) => { if (!seating) turn(e.deltaY > 0 ? 2.5 : -2.5) }
    window.addEventListener('mousedown', down)
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
    window.addEventListener('wheel', wheel, { passive: true })
    return () => {
      window.removeEventListener('mousedown', down)
      window.removeEventListener('mousemove', move)
      window.removeEventListener('mouseup', up)
      window.removeEventListener('wheel', wheel)
    }
  }, [seating])

  const push = () => {
    if (seating) return
    if (!aligned) {
      sfx.wrong()
      setMessage('Line the holes up with the studs first')
      setTimeout(() => setMessage(null), 1500)
      return
    }
    // snap onto the nearest stud position, then slide it home
    const snapped = Math.round(angleRef.current / spacing) * spacing
    angleRef.current = snapped
    setAngle(snapped)
    setSeating(true)
    setTimeout(() => { sfx.seat(); finish('done') }, 160)
  }

  const studs = Array.from({ length: n }, (_, i) => at(i))
  const holes = Array.from({ length: n }, (_, i) => at(n + i))
  const r = Math.max(12, radius * 0.75)

  return (
    <>
      {studs.map((p, i) => p && (
        <div key={`s${i}`} className="pointer-events-none fixed rounded-full" style={{ left: p.x - r * 0.45, top: p.y - r * 0.45, width: r * 0.9, height: r * 0.9, background: 'radial-gradient(circle at 35% 35%, #fff, #9aa0aa 60%, #555 100%)', boxShadow: '0 0 10px rgba(255,255,255,0.35)' }} />
      ))}
      {holes.map((p, i) => p && (
        <div key={`h${i}`} className={cn('pointer-events-none fixed rounded-full border-[3px] transition-colors duration-150', aligned ? 'border-good' : 'border-white/80')} style={{ left: p.x - r, top: p.y - r, width: r * 2, height: r * 2, boxShadow: aligned ? '0 0 14px rgba(74,222,128,0.55)' : '0 0 8px rgba(0,0,0,0.6)' }} />
      ))}
      {/* the whole screen is the drag surface; a click without much drag pushes the wheel on */}
      <ClickSurface onClick={push} />
      {message && <div className="pop-in fixed top-[18%] left-1/2 -translate-x-1/2 rounded-md bg-bad/15 px-3 py-1.5 text-[11px] font-black tracking-[0.1em] text-bad uppercase">{message}</div>}
      <Card title={state.data.title} hint={state.data.hint} progress={aligned ? 'Lined up' : `${Math.round(miss)}° off`} />
    </>
  )
}

/** Fires onClick for a press that did not travel (a drag turns the wheel instead). */
function ClickSurface({ onClick }: { onClick: () => void }) {
  const start = useRef<{ x: number; y: number } | null>(null)
  return (
    <div
      className="fixed inset-0 cursor-grab active:cursor-grabbing"
      onMouseDown={(e) => { if (e.button === 0) start.current = { x: e.clientX, y: e.clientY } }}
      onMouseUp={(e) => {
        const s = start.current
        start.current = null
        if (s && Math.hypot(e.clientX - s.x, e.clientY - s.y) < 5) onClick()
      }}
    />
  )
}

// ---------------------------------------------------------------- spinning a filter off / on
/** Circle the mouse round the filter (held down) in the right direction. Points: the filter's face, a point on its rim. */
function Spin({ state, at }: { state: MinigameState; at: (i: number) => { x: number; y: number } | null }) {
  const turns = state.data.turns ?? 3
  const sign = state.data.dir === 'ccw' ? -1 : 1   // screen angles grow clockwise
  const [p, setP] = useState(0)
  const [message, setMessage] = useState<string | null>(null)
  const [held, setHeld] = useState(false)
  const pRef = useRef(0)
  const last = useRef<number | null>(null)
  const ticks = useRef(0)
  const wrong = useRef(0)
  const finished = useRef(false)
  const atRef = useRef(at)
  atRef.current = at

  const centre = at(0)
  const rim = at(1)
  const faceR = centre && rim ? Math.hypot(rim.x - centre.x, rim.y - centre.y) : 40
  const ringR = Math.max(70, faceR * 1.9)

  useEffect(() => {
    const angleOf = (e: MouseEvent) => {
      const c = atRef.current(0)
      return c ? Math.atan2(e.clientY - c.y, e.clientX - c.x) : null
    }
    const down = (e: MouseEvent) => { if (e.button === 0 && !finished.current) { setHeld(true); last.current = angleOf(e) } }
    const up = () => { setHeld(false); last.current = null }
    const move = (e: MouseEvent) => {
      if (last.current === null || finished.current) return
      const c = atRef.current(0)
      const a = angleOf(e)
      if (a === null || !c) return
      // too close to the middle and the angle jumps about
      if (Math.hypot(e.clientX - c.x, e.clientY - c.y) < 18) { last.current = a; return }
      let d = a - last.current
      if (d > Math.PI) d -= Math.PI * 2
      if (d < -Math.PI) d += Math.PI * 2
      last.current = a
      const step = d * sign
      if (step <= 0) {
        wrong.current += -step
        if (wrong.current > Math.PI * 0.6) {
          wrong.current = 0
          sfx.wrong()
          setMessage(sign < 0 ? 'Other way: anticlockwise' : 'Other way: clockwise')
          window.setTimeout(() => setMessage(null), 1400)
        }
        return
      }
      wrong.current = 0
      const next = Math.min(1, pRef.current + step / (Math.PI * 2 * turns))
      pRef.current = next
      setP(next)
      event('progress', next)
      // a click of the thread every quarter turn
      const t = Math.floor(next * turns * 4)
      if (t > ticks.current) { ticks.current = t; sfx.click() }
      if (next >= 1 && !finished.current) {
        finished.current = true
        setHeld(false)
        sfx.seat()
        window.setTimeout(() => finish('done'), 450)
      }
    }
    window.addEventListener('mousedown', down)
    window.addEventListener('mouseup', up)
    window.addEventListener('mousemove', move)
    return () => {
      window.removeEventListener('mousedown', down)
      window.removeEventListener('mouseup', up)
      window.removeEventListener('mousemove', move)
    }
  }, [sign, turns])

  // the ring: a track, the progress so far, and arrows showing which way
  const arc = (from: number, to: number) => {
    if (!centre) return ''
    const a0 = -Math.PI / 2 + sign * from * Math.PI * 2, a1 = -Math.PI / 2 + sign * to * Math.PI * 2
    const large = to - from > 0.5 ? 1 : 0
    return `M ${centre.x + Math.cos(a0) * ringR} ${centre.y + Math.sin(a0) * ringR} A ${ringR} ${ringR} 0 ${large} ${sign > 0 ? 1 : 0} ${centre.x + Math.cos(a1) * ringR} ${centre.y + Math.sin(a1) * ringR}`
  }
  const turnP = (p * turns) % 1 || (p >= 1 ? 1 : 0)
  const arrows = centre ? [0, 1, 2].map((k) => {
    const a = -Math.PI / 2 + (k / 3) * Math.PI * 2 + p * turns * Math.PI * 2 * sign
    const x = centre.x + Math.cos(a) * ringR, y = centre.y + Math.sin(a) * ringR
    const deg = (a * 180) / Math.PI + (sign > 0 ? 90 : -90)
    return <path key={k} d="M -7 -6 L 7 0 L -7 6 Z" fill="rgba(255,255,255,0.75)" transform={`translate(${x} ${y}) rotate(${deg})`} />
  }) : null

  return (
    <>
      <svg className={cn('fixed inset-0 h-full w-full', held ? 'cursor-grabbing' : 'cursor-grab')}>
        {centre && (
          <>
            <circle cx={centre.x} cy={centre.y} r={ringR} fill="none" stroke="rgba(255,255,255,0.14)" strokeWidth={10} />
            {turnP > 0 && <path d={arc(0, Math.min(0.9999, turnP))} fill="none" stroke={p >= 1 ? '#4ade80' : '#fff'} strokeWidth={6} strokeLinecap="round" />}
            {arrows}
            <circle cx={centre.x} cy={centre.y} r={Math.max(14, faceR)} fill="none" stroke={held ? '#fff' : 'rgba(255,255,255,0.45)'} strokeWidth={2} strokeDasharray="5 4" />
          </>
        )}
      </svg>
      {message && <div className="pop-in pointer-events-none fixed top-[18%] left-1/2 -translate-x-1/2 rounded-md bg-bad/15 px-3 py-1.5 text-[11px] font-black tracking-[0.1em] text-bad uppercase">{message}</div>}
      <Card title={state.data.title} hint={state.data.hint} progress={`${Math.min(turns, Math.floor(p * turns + 0.0001))} / ${turns} turns`} />
    </>
  )
}

// ---------------------------------------------------------------- grinding / buffing a whole side
/** Sweep the grinder or the polisher over the side. No spots: the game works out how much of the side the real tool
 * has covered (it is under the cursor in the game) and sends the percentage back ('minigame:update'). */
function Sweep({ state }: { state: MinigameState }) {
  const [progress, setProgress] = useState(state.data.progress ?? 0)
  const [busy, setBusy] = useState(false)
  const [cursor, setCursor] = useState<{ x: number; y: number } | null>(null)
  const [held, setHeld] = useState(false)
  const heldRef = useRef(false)
  const busyRef = useRef(false)
  const mouse = useRef({ x: -1, y: -1, moved: 0 })
  useNui<{ progress?: number; busy?: boolean }>('minigame:update', (d) => {
    if (typeof d?.progress === 'number') setProgress(d.progress)
    busyRef.current = !!d?.busy
    setBusy(!!d?.busy)
  })

  useEffect(() => {
    const down = (e: MouseEvent) => { if (e.button === 0) { heldRef.current = true; setHeld(true) } }
    const up = () => { heldRef.current = false; setHeld(false) }
    const move = (e: MouseEvent) => {
      const m = mouse.current
      if (Math.hypot(e.clientX - m.x, e.clientY - m.y) > 1.5) m.moved = performance.now()
      m.x = e.clientX; m.y = e.clientY
      setCursor({ x: e.clientX, y: e.clientY })
    }
    window.addEventListener('mousedown', down)
    window.addEventListener('mouseup', up)
    window.addEventListener('mousemove', move)
    return () => { window.removeEventListener('mousedown', down); window.removeEventListener('mouseup', up); window.removeEventListener('mousemove', move) }
  }, [])

  // send the cursor to the game (it places the polisher there) and run the polisher's sound
  useEffect(() => {
    const tool = grinder(state.data.mode === 'grind' ? 'grind' : 'buff')
    const sent = { x: -1, y: -1, held: false }
    let raf = 0
    const tick = (now: number) => {
      const m = mouse.current
      tool.run(heldRef.current)
      tool.load(busyRef.current ? (now - m.moved < 120 ? 1 : 0.4) : 0)
      if (m.x >= 0 && (m.x !== sent.x || m.y !== sent.y || heldRef.current !== sent.held)) {
        sent.x = m.x; sent.y = m.y; sent.held = heldRef.current
        event('cursor', { x: m.x / window.innerWidth, y: m.y / window.innerHeight, held: heldRef.current })
      }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => { cancelAnimationFrame(raf); tool.stop() }
  }, [state.data.mode])

  const pct = Math.min(100, Math.round(progress * 100))

  return (
    <>
      <svg className="fixed inset-0 h-full w-full cursor-none">
        {cursor && (
          <g transform={`translate(${cursor.x} ${cursor.y})`} pointerEvents="none">
            <circle r={9} fill="none" stroke={busy ? '#fbbf24' : held ? '#fff' : 'rgba(255,255,255,0.7)'} strokeWidth={1.5} />
            <circle r={2} fill="#fff" />
          </g>
        )}
      </svg>
      <Card title={state.data.title} hint={state.data.hint} progress={`${pct}%`}>
        <div className="mt-2.5 h-1.5 overflow-hidden rounded-full bg-white/[0.08]">
          <div className={cn('h-full rounded-full transition-[width] duration-150', pct >= 100 ? 'bg-good' : 'bg-white')} style={{ width: `${pct}%` }} />
        </div>
      </Card>
    </>
  )
}

// ---------------------------------------------------------------- starting it: the skill check
/** A needle sweeps round the ring while the starter cranks. Tap Space (or click) as it crosses the white mark. `hits`
 * in a row and it catches; tapping off the mark, or letting the needle sweep past it, is a cough and the count
 * starts again. Each hit moves the mark on and speeds the needle up. */
function Skill({ state }: { state: MinigameState }) {
  const need = state.data.hits ?? 3
  const baseSpeed = state.data.speed ?? 0.85      // turns a second
  const speedUp = state.data.speedUp ?? 0.18
  const zoneDeg = state.data.zone ?? 34
  const [angle, setAngle] = useState(0)             // needle, degrees clockwise from the top
  const [zone, setZone] = useState(() => 150 + Math.random() * 150)   // start of the mark
  const [streak, setStreak] = useState(0)
  const [flash, setFlash] = useState<'hit' | 'miss' | null>(null)
  const [started, setStarted] = useState(false)
  const [message, setMessage] = useState<{ text: string; tone: 'bad' | 'good' } | null>(null)
  const s = useRef({ angle: 0, zone: 0, streak: 0, speed: baseSpeed, paused: 0, armed: false, done: false })
  s.current.zone = zone

  const say = (text: string, tone: 'bad' | 'good' = 'bad') => { setMessage({ text, tone }); window.setTimeout(() => setMessage(null), 1300) }

  // a new mark somewhere ahead of the needle (not right on top of it)
  const placeZone = (from: number) => {
    const z = (from + 90 + Math.random() * 180) % 360
    s.current.zone = z
    s.current.armed = false
    setZone(z)
  }

  const inZone = (a: number) => {
    const d = (((a - s.current.zone) % 360) + 360) % 360
    return d <= zoneDeg
  }

  const miss = (why: string) => {
    const st = s.current
    st.streak = 0
    st.speed = baseSpeed
    st.paused = performance.now() + 700
    setStreak(0)
    setFlash('miss')
    window.setTimeout(() => setFlash(null), 350)
    sfx.cough()
    event('cough')
    say(why)
    placeZone(st.angle)
  }

  const hit = () => {
    const st = s.current
    st.streak += 1
    setStreak(st.streak)
    setFlash('hit')
    window.setTimeout(() => setFlash(null), 250)
    if (st.streak >= need) {
      st.done = true
      setStarted(true)
      sfx.start()
      event('catch')
      say('It caught', 'good')
      window.setTimeout(() => finish('done'), 1400)
      return
    }
    sfx.click()
    st.speed += speedUp
    placeZone(st.angle)
  }

  const press = () => {
    const st = s.current
    if (st.done || performance.now() < st.paused) return
    if (inZone(st.angle)) hit()
    else miss('It coughed. Too ' + ((((st.zone - st.angle) % 360) + 360) % 360 < 180 ? 'early' : 'late'))
  }

  useEffect(() => {
    const key = (e: KeyboardEvent) => { if (e.code === 'Space' && !e.repeat) { e.preventDefault(); press() } }
    const mouse = (e: MouseEvent) => { if (e.button === 0) press() }
    window.addEventListener('keydown', key)
    window.addEventListener('mousedown', mouse)
    return () => { window.removeEventListener('keydown', key); window.removeEventListener('mousedown', mouse) }
  })

  // the needle turns while the starter cranks; sweeping right past the mark is a miss too
  useEffect(() => {
    const r = rattle(9)
    let last = performance.now(), raf = 0
    const tick = (now: number) => {
      const st = s.current
      const dt = (now - last) / 1000
      last = now
      if (st.done) { r.stop(); return }
      if (now >= st.paused) {
        st.angle = (st.angle + st.speed * 360 * dt) % 360
        r.pitch(0.4 + 0.2 * st.streak)
        if (inZone(st.angle)) st.armed = true
        else if (st.armed) miss('Missed it')   // swept right past the mark
      }
      setAngle(st.angle)
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => { cancelAnimationFrame(raf); r.stop() }
  }, [])

  const size = 240, c = size / 2, R = 92
  const pt = (deg: number, r: number) => {
    const a = ((deg - 90) * Math.PI) / 180
    return [c + Math.cos(a) * r, c + Math.sin(a) * r]
  }
  const arc = (from: number, to: number, r: number) => {
    const [x0, y0] = pt(from, r), [x1, y1] = pt(to, r)
    return `M ${x0} ${y0} A ${r} ${r} 0 ${to - from > 180 ? 1 : 0} 1 ${x1} ${y1}`
  }
  const [nx, ny] = pt(angle, R + 10)
  const [ix, iy] = pt(angle, R - 22)

  return (
    <>
      <div className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-[60%] fade-up">
        <svg width={size} height={size}>
          <circle cx={c} cy={c} r={R + 22} fill="rgba(10,10,12,0.78)" />
          <circle cx={c} cy={c} r={R} fill="none" stroke={flash === 'miss' ? 'rgba(248,113,113,0.6)' : 'rgba(255,255,255,0.16)'} strokeWidth={4} />
          {!started && <path d={arc(zone, zone + zoneDeg, R)} stroke="#fff" strokeWidth={12} fill="none" />}
          <line x1={ix} y1={iy} x2={nx} y2={ny} stroke={started ? '#4ade80' : flash === 'hit' ? '#4ade80' : '#ef4444'} strokeWidth={4} strokeLinecap="round" />
          {Array.from({ length: need }, (_, i) => (
            <circle key={i} cx={c + (i - (need - 1) / 2) * 22} cy={c} r={7} fill={i < streak || started ? '#4ade80' : 'rgba(255,255,255,0.12)'} stroke="rgba(255,255,255,0.25)" />
          ))}
          <text x={c} y={c + 30} textAnchor="middle" fontSize="10" fontWeight="900" letterSpacing="2" fill={started ? '#4ade80' : 'rgba(255,255,255,0.5)'}>{started ? 'RUNNING' : 'CRANKING'}</text>
        </svg>
      </div>
      {message && <div className={cn('pop-in pointer-events-none fixed top-[16%] left-1/2 -translate-x-1/2 rounded-md px-3 py-1.5 text-[11px] font-black tracking-[0.1em] uppercase', message.tone === 'bad' ? 'bg-bad/15 text-bad' : 'bg-good/15 text-good')}>{message.text}</div>}
      <Card title={state.data.title} hint={state.data.hint} progress={`${streak} / ${need}`} />
    </>
  )
}
