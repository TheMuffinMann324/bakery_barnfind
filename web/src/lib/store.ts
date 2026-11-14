import { useSyncExternalStore } from 'react'
import { call, nui, onNui } from './nui'
import type { MinigameState } from '@/components/Minigame'
import type { AdminData, Kind, LiveBarn, PlaceState, Section, Settings, VehicleInfo } from './types'

export interface Toast { id: number; message: string; title?: string; kind: Kind }

export interface AppState {
  open: boolean
  data: AdminData | null
  /** Unsaved edits, one per section. Kept while you move between pages. */
  drafts: Partial<{ [K in Section]: AdminData[K] }>
  /** Vehicle names and classes, asked of the game once per model. */
  labels: Record<string, VehicleInfo>
  /** Set while the placement editor runs in the game world. */
  place: PlaceState | null
  /** When `data.live` was fetched, so countdowns can tick between refreshes. */
  fetchedAt: number
  toasts: Toast[]
  /** A restore minigame running over the game (client/minigame.lua). */
  minigame: MinigameState | null
}

let state: AppState = { open: false, data: null, drafts: {}, labels: {}, place: null, fetchedAt: 0, toasts: [], minigame: null }
const listeners = new Set<() => void>()

export function getState() { return state }

export function setState(patch: Partial<AppState> | ((s: AppState) => Partial<AppState>)) {
  const next = typeof patch === 'function' ? patch(state) : patch
  state = { ...state, ...next }
  listeners.forEach((l) => l())
}

export function useStore<T>(selector: (s: AppState) => T): T {
  return useSyncExternalStore(
    (cb) => { listeners.add(cb); return () => listeners.delete(cb) },
    () => selector(state),
  )
}

let toastId = 0
export function toast(message: string, kind: Kind = 'info', title?: string) {
  const id = ++toastId
  setState((s) => ({ toasts: [...s.toasts.slice(-3), { id, message, kind, title }] }))
  setTimeout(() => setState((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })), kind === 'error' ? 5000 : 3200)
}

// ---- the game talking to the page ------------------------------------------------------------
function list<T>(value?: T[]): T[] {
  return Array.isArray(value) ? value : []
}

function normaliseLive(live?: LiveBarn[]): LiveBarn[] {
  return list(live).map((barn) => ({ ...barn, entries: list(barn.entries) }))
}

function normaliseSettings(settings: Settings): Settings {
  return {
    ...settings,
    restore: { stages: settings.restore.stages.map((stage) => ({ ...stage, items: list(stage.items) })) },
  }
}

onNui('open', (data: AdminData) => setState({
  open: true,
  data: {
    ...data, settings: normaliseSettings(data.settings), cars: list(data.cars), barns: list(data.barns),
    live: normaliseLive(data.live), paints: list(data.paints), items: list(data.items),
  },
  drafts: {},
  fetchedAt: Date.now(),
}))
onNui('close', () => setState({ open: false }))
onNui('place', (d: PlaceState) => setState({ place: d?.active ? d : null }))
onNui('minigame', (d: MinigameState | null) => setState({ minigame: d ?? null }))

// ---- live status -----------------------------------------------------------------------------
export async function refreshLive() {
  const res = await call<{ ok: boolean; live?: AdminData['live']; now?: number }>('admin:live')
  if (res?.ok && res.live) applyLive(res)
}

export function applyLive(res: { live?: AdminData['live']; now?: number }) {
  setState((s) => (s.data ? {
    data: { ...s.data, live: res.live ? normaliseLive(res.live) : s.data.live, now: res.now ?? s.data.now },
    fetchedAt: Date.now(),
  } : {}))
}

// ---- vehicle names ---------------------------------------------------------------------------
const asked = new Set<string>()
export async function ensureLabels(models: string[]) {
  const need = models.filter((m) => !asked.has(m) && !state.labels[m])
  if (need.length === 0) return
  need.forEach((m) => asked.add(m))
  const res = await nui<Record<string, VehicleInfo>>('admin:labels', { models: need })
  if (res && typeof res === 'object') setState((s) => ({ labels: { ...s.labels, ...res } }))
}

/** Ask about one model, even if it was asked before (the Add car dialog's Check button). */
export async function checkModel(model: string) {
  const res = await nui<Record<string, VehicleInfo>>('admin:labels', { models: [model] })
  const info = res?.[model] ?? { ok: false }
  setState((s) => ({ labels: { ...s.labels, [model]: info } }))
  return info
}

// ---- drafts ----------------------------------------------------------------------------------
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

function normaliseSection<K extends Section>(section: K, value: AdminData[K]): AdminData[K] {
  if (section === 'settings') return normaliseSettings(value as Settings) as AdminData[K]
  return list(value as AdminData[Exclude<Section, 'settings'>][number][]) as AdminData[K]
}

function withoutDraft(section: Section) {
  const drafts = { ...state.drafts }
  delete drafts[section]
  return drafts
}

/**
 * One section's data with a local draft on top. Edit through `update`; nothing reaches the server until
 * `save`. Drafts live in the store, so they survive switching pages.
 */
export function useDraft<K extends Section>(section: K) {
  const data = useStore((s) => s.data?.[section]) as AdminData[K]
  const stored = useStore((s) => s.drafts[section]) as AdminData[K] | undefined
  const draft = stored ?? data
  const dirty = stored !== undefined && !same(stored, data)

  return {
    draft, dirty,
    update(fn: (d: AdminData[K]) => void) {
      const base = structuredClone((state.drafts[section] ?? state.data![section]) as AdminData[K])
      fn(base)
      setState((s) => ({ drafts: { ...s.drafts, [section]: base } }))
    },
    discard() { setState({ drafts: withoutDraft(section) }) },
    async save() {
      const res = await call<{ ok: boolean; value?: AdminData[K]; live?: AdminData['live']; error?: string }>('admin:save', { section, value: draft })
      if (!res?.ok) { toast(res?.error ?? 'Could not save.', 'error'); return false }
      const value = normaliseSection(section, res.value ?? draft)
      setState((s) => ({ data: { ...s.data!, [section]: value, live: res.live ? normaliseLive(res.live) : s.data!.live }, drafts: withoutDraft(section) }))
      return true
    },
    async reset() {
      const res = await call<{ ok: boolean; value?: AdminData[K]; error?: string }>('admin:reset', { section })
      if (!res?.ok) { toast(res?.error ?? 'Could not restore the defaults.', 'error'); return false }
      setState((s) => ({ data: { ...s.data!, [section]: normaliseSection(section, res.value ?? draft) }, drafts: withoutDraft(section) }))
      return true
    },
  }
}

/** Sections with unsaved edits, for the sidebar's dots. */
export function useDirty(): Record<Section, boolean> {
  const data = useStore((s) => s.data)
  const drafts = useStore((s) => s.drafts)
  const out = { settings: false, cars: false, paints: false, barns: false }
  if (data) for (const k of Object.keys(out) as Section[]) out[k] = drafts[k] !== undefined && !same(drafts[k], data[k])
  return out
}
