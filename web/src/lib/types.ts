export type Scope = 'global' | 'player'
export type Kind = 'info' | 'success' | 'error' | 'warning'

export interface StageItem { name: string; count: number }
export interface RestoreStage { id: string; label: string; enabled: boolean; items: StageItem[] }

export interface Settings {
  scope: Scope
  cooldownMinutes: number
  spawnDistance: number
  interactDistance: number
  cutscene: { enabled: boolean; skippable: boolean }
  dressing: boolean
  condition: {
    dirt: number; rust: number; bodyHealth: number; engineHealth: number
    burstTyres: number; smashedWindows: number; hoodAjar: number; plate: string
  }
  restore: {
    stages: RestoreStage[]
  }
}

export interface Car { model: string; weight: number; enabled: boolean }
export interface Paint { name: string; color: string }

export interface Barn {
  id: string
  name: string
  x: number; y: number; z: number; w: number
  enabled: boolean
  pool?: string[]            // omitted = every enabled car
}

export interface LiveEntry { owner: string; name: string; car: string; at: number; left: number | null }
export interface LiveBarn { id: string; count: number; entries: LiveEntry[]; scope: Scope; cooldown: number | null }

export interface AdminData {
  settings: Settings
  cars: Car[]
  paints: Paint[]
  barns: Barn[]
  live: LiveBarn[]
  /** Every item the inventory knows, for suggestions. Empty when the server can't tell. */
  items?: { name: string; label: string }[]
  now: number
  me?: { name: string }
}

export type Section = 'settings' | 'cars' | 'paints' | 'barns'

export interface VehicleInfo { ok: boolean; label?: string; class?: string }

// What the game tells the page while the placement editor is running (client/gizmo.lua).
export interface PlaceState {
  active: boolean
  /** Left Alt: the page has the mouse and the gizmo is live. Otherwise the barn follows the crosshair. */
  focus?: boolean
  label?: string
  x?: number; y?: number; z?: number; w?: number
  autoGround?: boolean
  slope?: number
  hover?: string | null
  dragging?: boolean
  speed?: number
  moved?: boolean
}

export interface Placement { x: number; y: number; z: number; w: number; cancelled?: boolean }
