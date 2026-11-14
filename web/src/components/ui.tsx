import { useEffect, useState, type ButtonHTMLAttributes, type HTMLAttributes, type ReactNode } from 'react'
import { AlertCircle, AlertTriangle, CheckCircle2, Info, Loader2, Minus, Plus, Save, X } from 'lucide-react'
import { cn, clamp } from '@/lib/utils'
import { useStore } from '@/lib/store'

// The Bakery component set, as in bakery_racing / bakery_boosting: black panels, white ink, uppercase labels.

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'outline'

export function Button({
  variant = 'secondary', size = 'md', loading, className, children, ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; size?: 'sm' | 'md' | 'lg' | 'icon'; loading?: boolean }) {
  return (
    <button
      {...props}
      disabled={props.disabled || loading}
      className={cn(
        'relative inline-flex shrink-0 items-center justify-center gap-1.5 rounded-md font-extrabold tracking-[0.06em] whitespace-nowrap uppercase transition-all outline-none select-none active:translate-y-px disabled:opacity-35 [&_svg]:shrink-0',
        size === 'sm' && 'h-7 px-2.5 text-[10.5px] [&_svg]:size-3.5',
        size === 'md' && 'h-8 px-3 text-[11px] [&_svg]:size-4',
        size === 'lg' && 'h-10 px-4 text-[12px] [&_svg]:size-4',
        size === 'icon' && 'size-8 [&_svg]:size-4',
        variant === 'primary' && 'bg-white text-ink hover:bg-white/85',
        variant === 'secondary' && 'bg-white/[0.07] text-white/85 hover:bg-white/[0.12] hover:text-white',
        variant === 'outline' && 'border border-white/[0.1] text-white/75 hover:bg-white/[0.06] hover:text-white',
        variant === 'ghost' && 'text-white/50 hover:bg-white/[0.07] hover:text-white',
        variant === 'danger' && 'bg-bad/12 text-bad hover:bg-bad/20',
        className,
      )}
    >
      {loading && <Loader2 className="animate-spin" />}
      {children}
    </button>
  )
}

type Tone = 'default' | 'good' | 'warn' | 'bad' | 'solid' | 'gold' | 'silver' | 'bronze'

export function Badge({ children, className, tone = 'default' }: { children: ReactNode; className?: string; tone?: Tone }) {
  return (
    <span
      className={cn(
        'inline-flex h-5 items-center gap-1 rounded-[4px] px-1.5 text-[9.5px] font-extrabold tracking-[0.07em] whitespace-nowrap uppercase [&_svg]:size-3',
        tone === 'default' && 'bg-white/[0.06] text-white/60',
        tone === 'good' && 'bg-good/10 text-good',
        tone === 'warn' && 'bg-warn/10 text-warn',
        tone === 'bad' && 'bg-bad/10 text-bad',
        tone === 'solid' && 'bg-white text-ink',
        tone === 'gold' && 'bg-gold/15 text-gold',
        tone === 'silver' && 'bg-silver/15 text-silver',
        tone === 'bronze' && 'bg-bronze/15 text-bronze',
        className,
      )}
    >
      {children}
    </span>
  )
}

export function Switch({ checked, onChange, disabled, title }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean; title?: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      title={title}
      onClick={() => onChange(!checked)}
      className={cn('relative h-5 w-9 shrink-0 rounded-full transition-colors disabled:opacity-40', checked ? 'bg-white' : 'bg-white/[0.1]')}
    >
      <span className={cn('absolute top-0.5 left-0.5 size-4 rounded-full transition-all', checked ? 'translate-x-4 bg-ink' : 'bg-white/60')} />
    </button>
  )
}

export function Segmented<T extends string>({ value, options, onChange, className }: {
  value: T
  options: { value: T; label: ReactNode }[]
  onChange: (v: T) => void
  className?: string
}) {
  return (
    <div className={cn('inline-flex gap-0.5 rounded-md bg-white/[0.05] p-0.5', className)}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          onClick={() => onChange(o.value)}
          className={cn(
            'inline-flex h-7 flex-1 items-center justify-center gap-1.5 rounded-[5px] px-3 text-[10.5px] font-extrabold tracking-[0.07em] whitespace-nowrap uppercase transition-all [&_svg]:size-3.5',
            value === o.value ? 'bg-white text-ink' : 'text-white/50 hover:text-white',
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

export function Label({ children, hint }: { children: ReactNode; hint?: ReactNode }) {
  return (
    <div className="mb-1.5 flex items-baseline justify-between">
      <span className="text-[10px] font-extrabold tracking-[0.14em] text-white/45 uppercase">{children}</span>
      {hint && <span className="text-[11px] text-white/30">{hint}</span>}
    </div>
  )
}

export function SectionTitle({ children, text, action, className }: { children: ReactNode; text?: ReactNode; action?: ReactNode; className?: string }) {
  return (
    <div className={cn('mb-2.5 flex items-end justify-between gap-3', className)}>
      <div className="min-w-0">
        <h2 className="text-[11px] font-black tracking-[0.18em] text-white uppercase">{children}</h2>
        {text && <p className="mt-0.5 text-[11px] text-white/40">{text}</p>}
      </div>
      {action && <div className="flex shrink-0 items-center gap-2">{action}</div>}
    </div>
  )
}

export function Card({ children, className, ...rest }: { children: ReactNode; className?: string } & HTMLAttributes<HTMLDivElement>) {
  return (
    <div {...rest} className={cn('rounded-lg border border-white/[0.06] bg-white/[0.025]', className)}>
      {children}
    </div>
  )
}

export function Stat({ label, value, sub, icon }: { label: string; value: ReactNode; sub?: ReactNode; icon?: ReactNode }) {
  return (
    <Card className="p-4">
      <div className="flex items-center justify-between text-white/35 [&_svg]:size-3.5">
        <span className="text-[10px] font-extrabold tracking-[0.14em] uppercase">{label}</span>
        {icon}
      </div>
      <div className="tnum mt-2.5 text-[26px] leading-none font-black tracking-tight text-white">{value}</div>
      {sub && <div className="mt-1.5 truncate text-[11.5px] text-white/35">{sub}</div>}
    </Card>
  )
}

export function Empty({ title, text, action }: { title: string; text?: string; action?: ReactNode }) {
  return (
    <div className="flex min-h-[200px] flex-col items-center justify-center gap-3 px-8 py-10 text-center">
      <div>
        <p className="text-[12.5px] font-extrabold tracking-[0.06em] text-white/65 uppercase">{title}</p>
        {text && <p className="mt-1 text-xs text-white/30">{text}</p>}
      </div>
      {action}
    </div>
  )
}

export function Modal({ open, onClose, title, subtitle, children, footer, width = 'max-w-md' }: {
  open: boolean
  onClose: () => void
  title: string
  subtitle?: string
  children?: ReactNode
  footer?: ReactNode
  width?: string
}) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); onClose() } }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [open, onClose])

  if (!open) return null
  return (
    <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/55 p-6 backdrop-blur-[2px]" onMouseDown={onClose}>
      <div onMouseDown={(e) => e.stopPropagation()} className={cn('pop-in w-full overflow-hidden rounded-lg border border-white/[0.07] bg-panel shadow-[0_24px_64px_rgba(0,0,0,0.8)]', width)}>
        <div className="flex items-start justify-between border-b border-white/[0.05] px-5 py-4">
          <div>
            <h3 className="text-[18px] leading-tight font-black tracking-tight uppercase">{title}</h3>
            {subtitle && <p className="mt-0.5 text-xs text-white/40">{subtitle}</p>}
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} className="-mt-1 -mr-2"><X /></Button>
        </div>
        {children && <div className="max-h-[60vh] overflow-y-auto px-5 py-4">{children}</div>}
        {footer && <div className="flex justify-end gap-2 border-t border-white/[0.05] bg-panel-2 px-5 py-3">{footer}</div>}
      </div>
    </div>
  )
}

export function Confirm({ open, onClose, title, text, confirm, onConfirm, danger = true }: {
  open: boolean; onClose: () => void; title: string; text: string; confirm: string; onConfirm: () => void; danger?: boolean
}) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      subtitle={text}
      footer={<><Button variant="ghost" onClick={onClose}>Cancel</Button><Button variant={danger ? 'danger' : 'primary'} onClick={() => { onClose(); onConfirm() }}>{confirm}</Button></>}
    />
  )
}

export function Kbd({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <kbd className={cn('inline-flex h-5 min-w-5 items-center justify-center rounded-[4px] bg-[#f2f2f2] px-1.5 font-sans text-[10px] font-black tracking-[0.04em] text-ink uppercase shadow-[inset_0_-2px_0_rgba(0,0,0,0.2)]', className)}>
      {children}
    </kbd>
  )
}

/** Amber notice for a setup that will stop something working. */
export function Warning({ children }: { children: ReactNode }) {
  return (
    <div className="mb-3 flex items-center gap-2.5 rounded-lg border border-warn/20 bg-warn/[0.06] px-4 py-2.5 text-[11.5px] text-warn">
      <AlertTriangle className="size-4 shrink-0" /> <span>{children}</span>
    </div>
  )
}

// ---- settings layout (as in bakery_racing's Features and bakery_boosting's Settings) ----------------

/** A titled card of two columns of Rows. An odd last row spans the full width. */
export function Grid({ title, text, children, action }: { title?: string; text?: string; children: ReactNode; action?: ReactNode }) {
  return (
    <section className="mb-6 last:mb-0">
      {(title || action) && (
        <div className="mb-2.5 flex items-end justify-between gap-3">
          <div>
            {title && <h4 className="text-[11px] font-black tracking-[0.16em] text-white uppercase">{title}</h4>}
            {text && <p className="mt-0.5 text-[11px] text-white/40">{text}</p>}
          </div>
          {action}
        </div>
      )}
      <div className="grid grid-cols-2 overflow-hidden rounded-lg border border-white/[0.06] bg-white/[0.025] [&>*:last-child:nth-child(odd)]:col-span-2 [&>*:last-child:nth-child(odd)]:border-r-0 [&>*:nth-child(n+3)]:border-t [&>*:nth-child(n+3)]:border-white/[0.04] [&>*:nth-child(odd)]:border-r [&>*:nth-child(odd)]:border-white/[0.04]">
        {children}
      </div>
    </section>
  )
}

/** Label and description on the left, the control on the right. `full` makes the row span both columns. */
export function Row({ icon, title, text, children, full, wide, control }: { icon?: ReactNode; title: string; text?: string; children: ReactNode; full?: boolean; wide?: boolean; control?: 'auto' }) {
  return (
    <div className={cn('flex min-w-0 items-center justify-between gap-4 px-4 py-3.5', full && 'col-span-2 !border-r-0 border-t border-white/[0.04]')}>
      <div className="flex min-w-0 items-center gap-3">
        {icon && <span className="flex size-4 shrink-0 items-center justify-center text-white/35 [&_svg]:size-4">{icon}</span>}
        <div className="min-w-0">
          <p className="text-[13px] font-medium">{title}</p>
          {text && <p className="truncate text-[11px] text-white/35" title={text}>{text}</p>}
        </div>
      </div>
      <div className={cn('flex shrink-0 items-center justify-end gap-2', control === 'auto' ? 'w-auto' : wide ? 'w-[300px]' : 'w-[168px]')}>{children}</div>
    </div>
  )
}

/** Number field with − and + either side of the value. Clamps to min / max and keeps the unit beside the number. */
export function Stepper({ value, onChange, step = 1, min, max, unit, full, disabled, format }: {
  value: number; onChange: (v: number) => void; step?: number; min: number; max: number; unit?: string; full?: boolean; disabled?: boolean; format?: (v: number) => string
}) {
  const fix = (v: number) => Math.round(clamp(v, min, max) * 100) / 100
  const [text, setText] = useState(String(value))
  const [editing, setEditing] = useState(false)
  useEffect(() => { if (!editing) setText(String(value)) }, [value, editing])
  const btn = 'flex h-full w-8 shrink-0 items-center justify-center text-white/40 transition hover:bg-white/[0.07] hover:text-white disabled:pointer-events-none disabled:opacity-25'
  return (
    <div className={cn('flex h-8 items-center overflow-hidden rounded-[5px] border border-white/[0.06] bg-black/40', full ? 'w-full' : 'w-[168px]', disabled && 'pointer-events-none opacity-40')}>
      <button type="button" className={btn} disabled={value <= min} onClick={() => onChange(fix(value - step))}><Minus className="size-3.5" /></button>
      <div className="flex min-w-0 flex-1 items-baseline justify-center gap-1 px-1">
        {format && !editing
          ? <button type="button" className="tnum text-[12.5px] font-bold" onClick={() => setEditing(true)}>{format(value)}</button>
          : (
            <input
              autoFocus={editing}
              className="tnum h-6 w-16 border-0 bg-transparent p-0 text-center text-[12.5px] font-bold outline-none"
              type="number"
              step={step}
              min={min}
              max={max}
              value={text}
              onFocus={() => setEditing(true)}
              onBlur={() => { setEditing(false); const n = parseFloat(text); onChange(Number.isNaN(n) ? value : fix(n)) }}
              onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur() }}
              onChange={(e) => { setText(e.target.value); const n = parseFloat(e.target.value); if (!Number.isNaN(n)) onChange(fix(n)) }}
            />
          )}
        {unit && !format && <span className="text-[9.5px] font-extrabold tracking-[0.12em] text-white/35 uppercase">{unit}</span>}
      </div>
      <button type="button" className={btn} disabled={value >= max} onClick={() => onChange(fix(value + step))}><Plus className="size-3.5" /></button>
    </div>
  )
}

/** A text box sized for a Row. */
export function TextField({ value, onChange, placeholder, maxLength, mono, className, align = 'right' }: {
  value: string; onChange: (v: string) => void; placeholder?: string; maxLength?: number; mono?: boolean; className?: string; align?: 'left' | 'right'
}) {
  return (
    <input
      className={cn('field field-sm', align === 'right' && 'text-right', mono && 'font-mono text-[12px] font-medium', className)}
      value={value}
      placeholder={placeholder}
      maxLength={maxLength}
      onChange={(e) => onChange(e.target.value)}
    />
  )
}

/** Pinned to the bottom of the page while there are unsaved changes. */
export function SaveBar({ dirty, onSave, onDiscard }: { dirty: boolean; onSave: () => Promise<unknown> | void; onDiscard: () => void }) {
  const [busy, setBusy] = useState(false)
  if (!dirty) return null
  return (
    <div className="pointer-events-none sticky bottom-0 z-20 flex justify-center pt-5">
      <div className="fade-up pointer-events-auto flex items-center gap-3 rounded-lg border border-warn/25 bg-raised py-1.5 pr-1.5 pl-4 shadow-[0_14px_40px_rgba(0,0,0,0.75)]">
        <span className="pulse-dot size-1.5 rounded-full bg-warn" />
        <span className="text-[10.5px] font-extrabold tracking-[0.12em] text-white/80 uppercase">Unsaved changes</span>
        <span className="text-[11px] text-white/35">Nothing changes in game until you save</span>
        <div className="ml-2 flex gap-1.5">
          <Button size="sm" variant="ghost" onClick={onDiscard}>Discard</Button>
          <Button size="sm" variant="primary" loading={busy} onClick={async () => { setBusy(true); try { await onSave() } finally { setBusy(false) } }}><Save /> Save changes</Button>
        </div>
      </div>
    </div>
  )
}

/** Overview-style list: column headings, then rows. `cols` is a CSS grid template shared by the head and the rows. */
export function ListCard({ cols, head, children, empty, count }: { cols: string; head: ReactNode[]; children: ReactNode; empty?: ReactNode; count: number }) {
  return (
    <div className="overflow-hidden rounded-lg border border-white/[0.06] bg-white/[0.025]">
      <div className="grid items-center gap-3 border-b border-white/[0.06] px-4 py-2 text-[9.5px] font-extrabold tracking-[0.14em] text-white/35 uppercase" style={{ gridTemplateColumns: cols }}>
        {head.map((h, i) => <span key={i}>{h}</span>)}
      </div>
      {children}
      {count === 0 && <div className="px-4 py-10 text-center text-[11.5px] text-white/35">{empty ?? 'Nothing here yet.'}</div>}
    </div>
  )
}

export function ListRow({ cols, className, children, ...rest }: { cols: string; className?: string; children: ReactNode } & HTMLAttributes<HTMLDivElement>) {
  return (
    <div {...rest} style={{ gridTemplateColumns: cols }} className={cn('group grid items-center gap-3 border-b border-white/[0.04] px-4 py-3 last:border-0', className)}>
      {children}
    </div>
  )
}

export function Toasts() {
  const toasts = useStore((s) => s.toasts)
  return (
    <div className="pointer-events-none fixed top-6 left-1/2 z-50 flex w-[360px] -translate-x-1/2 flex-col items-center gap-2">
      {toasts.map((t) => {
        const Icon = t.kind === 'success' ? CheckCircle2 : t.kind === 'error' ? AlertCircle : t.kind === 'warning' ? AlertTriangle : Info
        const light = t.kind === 'success'
        return (
          <div key={t.id} className={cn('pop-in flex w-full items-stretch overflow-hidden rounded-md shadow-[0_14px_40px_rgba(0,0,0,0.5)] backdrop-blur-md', light ? 'bg-[linear-gradient(to_right,#0b0c0f_2.5rem,#fff_2.5rem)] text-ink' : 'bg-ink/90')}>
            <div className={cn('flex w-10 shrink-0 items-center justify-center', light ? 'bg-ink text-white' : 'bg-white/[0.06]')}>
              <Icon className={cn('size-4', t.kind === 'error' && 'text-bad', t.kind === 'warning' && 'text-warn', t.kind === 'success' && 'text-good', t.kind === 'info' && 'text-white/70')} />
            </div>
            <div className="min-w-0 px-3.5 py-2.5">
              {t.title && <p className="text-[10px] font-black tracking-[0.14em] uppercase opacity-60">{t.title}</p>}
              <p className="text-[12px] leading-snug font-extrabold tracking-[0.02em] uppercase">{t.message}</p>
            </div>
          </div>
        )
      })}
    </div>
  )
}
