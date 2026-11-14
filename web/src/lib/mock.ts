// Browser preview only: a pretend game and server so the menu can be built and clicked through outside FiveM.
// (`npm run dev`, then open the page.) None of this is loaded in game.
import { emit } from './nui'
import type { AdminData, Car, LiveBarn, Settings } from './types'

const settings: Settings = {
  scope: 'global', cooldownMinutes: 120, spawnDistance: 150, interactDistance: 2.2,
  cutscene: { enabled: true, skippable: true }, dressing: true,
  condition: { dirt: 15, rust: 1, bodyHealth: 250, engineHealth: 150, burstTyres: 2, smashedWindows: 3, hoodAjar: 25, plate: '' },
  restore: {
    stages: [
      { id: 'tyres', label: 'Tyres and wheels', enabled: true, items: [{ name: 'tyre', count: 4 }] },
      { id: 'glass', label: 'Windows', enabled: true, items: [] },
      { id: 'oil', label: 'Oil and filter', enabled: true, items: [{ name: 'oil_filter', count: 1 }, { name: 'engine_oil', count: 1 }] },
      { id: 'body', label: 'Bodywork', enabled: true, items: [] },
      { id: 'start', label: 'Start it up', enabled: true, items: [{ name: 'car_battery', count: 1 }] },
    ],
  },
}

const carList: [string, number][] = [
  ['ztype', 4], ['btype', 6], ['stinger', 5], ['jb700', 4], ['mamba', 5], ['cheetah2', 6], ['infernus2', 5], ['michelli', 8],
  ['gt500', 7], ['monroe', 6], ['tornado', 10], ['peyote', 10], ['savestra', 8], ['viseris', 6], ['fagaloa', 10], ['hermes', 8],
]
const cars: Car[] = carList.map(([model, weight]) => ({ model, weight, enabled: true }))

const NAMES: Record<string, [string, string]> = {
  ztype: ['Truffade Z-Type', 'Sports Classics'], btype: ['Albany Roosevelt', 'Sports Classics'], stinger: ['Grotti Stinger', 'Sports Classics'],
  jb700: ['Dewbauchee JB 700', 'Sports Classics'], mamba: ['Declasse Mamba', 'Sports Classics'], cheetah2: ['Grotti Cheetah Classic', 'Sports Classics'],
  infernus2: ['Pegassi Infernus Classic', 'Sports Classics'], michelli: ['Lampadati Michelli GT', 'Sports Classics'], gt500: ['Grotti GT500', 'Sports Classics'],
  monroe: ['Pegassi Monroe', 'Sports Classics'], tornado: ['Declasse Tornado', 'Sports Classics'], peyote: ['Vapid Peyote', 'Sports Classics'],
  savestra: ['Annis Savestra', 'Sports Classics'], viseris: ['Lampadati Viseris', 'Sports Classics'], fagaloa: ['Vulcar Fagaloa', 'Sports Classics'],
  hermes: ['Albany Hermes', 'Sports Classics'], sultan: ['Karin Sultan', 'Sports'],
}

let data: AdminData = {
  settings, cars,
  paints: [
    { name: 'Oxblood', color: '#5c2622' }, { name: 'Sage', color: '#606e58' }, { name: 'Cream', color: '#b0a486' }, { name: 'Faded blue', color: '#405468' },
    { name: 'Burnt orange', color: '#764828' }, { name: 'Graphite', color: '#3a3e3a' }, { name: 'Mustard', color: '#827046' }, { name: 'Racing green', color: '#283a2e' },
  ],
  barns: [
    { id: 'barn_a1', name: 'Grapeseed Field', x: 2030.4, y: 4980.1, z: 41.2, w: 132.5, enabled: true },
    { id: 'barn_b2', name: 'Sandy Shores Yard', x: 1450.0, y: 3097.2, z: 39.6, w: 0, enabled: true },
    { id: 'barn_c3', name: 'Paleto Farm', x: -312.8, y: 6320.4, z: 31.2, w: 270, enabled: true, pool: ['ztype', 'btype', 'jb700'] },
    { id: 'barn_d4', name: 'Chiliad Ranch', x: 0, y: 0, z: 0, w: 0, enabled: false },
  ],
  live: [],
  now: Math.floor(Date.now() / 1000),
  me: { name: 'Muffin' },
}

const live = (): LiveBarn[] => [
  { id: 'barn_a1', count: 0, entries: [], scope: 'global', cooldown: 120 },
  { id: 'barn_b2', count: 2, scope: 'player', cooldown: 45, entries: [
    { owner: 'abc', name: 'Jordan Hale', car: 'btype', at: Date.now() / 1000 - 600, left: 45 * 60 - 600 },
    { owner: 'def', name: 'Maya Ortiz', car: 'monroe', at: Date.now() / 1000 - 1500, left: 45 * 60 - 1500 },
  ] },
  { id: 'barn_c3', count: 1, scope: 'global', cooldown: null, entries: [{ owner: '', name: 'Everyone', car: 'jb700', at: Date.now() / 1000 - 90000, left: null }] },
  { id: 'barn_d4', count: 0, entries: [], scope: 'global', cooldown: 120 },
]

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v))

export async function mockNui(event: string, payload?: any): Promise<any> {
  await new Promise((r) => setTimeout(r, 60))
  if (event === 'close') return true
  if (event === 'admin:area') return { label: 'Route 68' }
  if (event === 'admin:teleport') return { ok: true }
  if (event === 'admin:labels') {
    const out: Record<string, unknown> = {}
    for (const m of payload?.models ?? []) out[m] = NAMES[m] ? { ok: true, label: NAMES[m][0], class: NAMES[m][1] } : { ok: false }
    return out
  }
  if (event === 'admin:place') {
    // pretend the placement editor ran for a few seconds
    const start = payload?.start ?? { x: 1520.31, y: 3203.4, z: 40.1, w: 87.2 }
    emit('place', { active: true, focus: false, label: payload?.label, ...start, autoGround: true, slope: 0.4, hover: 'x', dragging: false, speed: 1, moved: true })
    await new Promise((r) => setTimeout(r, 4500))
    emit('place', { active: false })
    return { x: start.x + 6.5, y: start.y - 3.2, z: start.z, w: (start.w + 40) % 360 }
  }
  if (event === 'call') {
    const { name, arg } = payload
    if (name === 'admin:live') return { ok: true, live: live(), now: Math.floor(Date.now() / 1000) }
    if (name === 'admin:save') {
      ;(data as any)[arg.section] = arg.value
      return { ok: true, value: clone(arg.value), live: live() }
    }
    if (name === 'admin:reset') return { ok: true, value: clone((data as any)[arg.section]) }
    if (name === 'admin:resetBarn') return { ok: true, cleared: 1, live: live() }
  }
  return { ok: false, error: 'Not in the preview.' }
}

export function startPreview() {
  data = { ...data, live: live() }
  emit('open', clone(data))
}
