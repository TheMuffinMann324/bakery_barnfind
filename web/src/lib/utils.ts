import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function uid(prefix: string) {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}`
}

export function clamp(n: number, lo: number, hi: number) {
  return Math.min(hi, Math.max(lo, n))
}

/** "2h 5m", "45m", "30s": how long until something is ready. */
export function formatDuration(seconds: number) {
  const s = Math.max(0, Math.floor(seconds))
  const d = Math.floor(s / 86400)
  const h = Math.floor((s % 86400) / 3600)
  const m = Math.floor((s % 3600) / 60)
  if (d > 0) return h > 0 ? `${d}d ${h}h` : `${d}d`
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`
  if (m > 0) return `${m}m`
  return `${s}s`
}

/** A cooldown in minutes, as people say it: "Once only", "45 min", "2 h", "1 d 4 h". */
export function formatMinutes(minutes: number) {
  if (minutes <= 0) return 'Once only'
  if (minutes < 60) return `${minutes} min`
  const d = Math.floor(minutes / 1440)
  const h = Math.floor((minutes % 1440) / 60)
  const m = minutes % 60
  if (d > 0) return h > 0 ? `${d} d ${h} h` : `${d} d`
  return m > 0 ? `${h} h ${m} min` : `${h} h`
}

export function formatNumber(n?: number) {
  return (n ?? 0).toLocaleString('en-US')
}

export function formatMoney(n?: number) {
  return `$${formatNumber(n)}`
}

export function titleCase(model: string) {
  return model.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}

export function coords(b: { x: number; y: number; z: number }) {
  return `${Math.round(b.x)}, ${Math.round(b.y)}, ${Math.round(b.z)}`
}

export const isPlaced = (b: { x: number; y: number }) => !!(b.x || b.y)
