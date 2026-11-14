import { Segmented, Stepper } from '@/components/ui'
import { cn, formatMinutes } from '@/lib/utils'

const PRESETS: [string, number][] = [
  ['1h', 60], ['2h', 120], ['6h', 360], ['12h', 720], ['1d', 1440], ['7d', 10080],
]

/**
 * How long until a used barn can be searched again: a delay in minutes, or "once only" (0, it never resets).
 * Laid out on one line: the mode, then the delay and its presets.
 */
export function CooldownField({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const mode = value === 0 ? 'once' : 'delay'
  return (
    <div className="flex items-center gap-2">
      <Segmented
        className="w-[210px] shrink-0"
        value={mode}
        onChange={(m) => onChange(m === 'once' ? 0 : value > 0 ? value : 120)}
        options={[
          { value: 'delay' as const, label: 'Resets after' },
          { value: 'once' as const, label: 'Once only' },
        ]}
      />
      {mode === 'delay' ? (
        <>
          <Stepper value={value} onChange={(v) => onChange(Math.max(1, v))} step={5} min={1} max={43200} format={formatMinutes} />
          <div className="flex gap-1">
            {PRESETS.map(([label, minutes]) => (
              <button
                key={label}
                type="button"
                onClick={() => onChange(minutes)}
                className={cn('h-7 rounded-[4px] px-2 text-[10px] font-extrabold tracking-[0.08em] uppercase transition', value === minutes ? 'bg-white text-ink' : 'bg-white/[0.06] text-white/45 hover:text-white')}
              >
                {label}
              </button>
            ))}
          </div>
        </>
      ) : (
        <p className="text-[11px] text-white/35">Stays used until you reset it from the Overview.</p>
      )}
    </div>
  )
}
