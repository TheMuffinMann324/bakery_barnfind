import { useState } from 'react'
import { Kbd } from '@/components/ui'
import { useNui } from '@/lib/nui'

// The "skip" hint shown over the reveal cutscene (client/cutscene.lua sends it). It is a hint, not a button: the
// game keeps the controls during the scene, so the key does the skipping.
interface SkipState { show: boolean; label?: string; key?: string }

export function SkipHint() {
  const [state, setState] = useState<SkipState>({ show: false })
  useNui<SkipState>('skipHint', (d) => setState(d ?? { show: false }))

  if (!state.show) return null

  return (
    <div className="pointer-events-none fixed right-10 bottom-10 fade-up">
      <div className="flex items-center gap-2.5 rounded-lg border border-white/[0.08] bg-panel/95 px-3.5 py-2 shadow-[0_18px_48px_rgba(0,0,0,0.6)]">
        <Kbd>{state.key ?? 'Backspace'}</Kbd>
        <span className="text-[11px] font-black tracking-[0.12em] text-white/70 uppercase">{state.label ?? 'Skip'}</span>
      </div>
    </div>
  )
}
