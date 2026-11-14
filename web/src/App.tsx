import { useEffect } from 'react'
import { Minigame } from '@/components/Minigame'
import { Placement } from '@/components/Placement'
import { SkipHint } from '@/components/SkipHint'
import { Toasts } from '@/components/ui'
import { useStore } from '@/lib/store'
import { Tablet } from '@/Tablet'

export default function App() {
  const open = useStore((s) => s.open)
  const place = useStore((s) => s.place)
  const minigame = useStore((s) => s.minigame)

  // Outside the game (npm run dev) a pretend server fills the menu in, so it can be built and clicked through.
  useEffect(() => {
    if (import.meta.env.DEV) import('@/lib/mock').then((m) => m.startPreview())
  }, [])

  return (
    <>
      {import.meta.env.DEV && <div className="fixed inset-0 -z-10 bg-[#0b0c10] bg-[radial-gradient(circle_at_30%_20%,rgba(255,255,255,0.1),transparent_55%),radial-gradient(circle_at_80%_80%,rgba(255,255,255,0.05),transparent_50%)]" />}
      {/* The menu stays mounted (and keeps its unsaved edits) behind the placement editor, hidden. */}
      {open && <Tablet hidden={!!place} />}
      {place && <Placement state={place} />}
      {minigame && <Minigame key={minigame.kind + (minigame.data.title ?? '')} state={minigame} />}
      <SkipHint />
      <Toasts />
    </>
  )
}
