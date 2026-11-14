import { useEffect, useRef } from 'react'

declare global {
  interface Window {
    GetParentResourceName?: () => string
  }
}

const resource = window.GetParentResourceName?.()

/** A client callback (client/admin.lua). timeoutMs 0 waits forever: the placement editor runs until you finish it. */
export async function nui<T = unknown>(event: string, data?: unknown, timeoutMs = 30000): Promise<T> {
  if (import.meta.env.DEV && !resource) return (await import('./mock')).mockNui(event, data) as T
  if (!resource) return { ok: false, error: 'The game connection is unavailable.' } as T
  const controller = new AbortController()
  const timer = timeoutMs > 0 ? window.setTimeout(() => controller.abort(), timeoutMs) : 0
  try {
    const res = await fetch(`https://${resource}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data ?? {}),
      signal: controller.signal,
    })
    return (await res.json()) as T
  } catch {
    return { ok: false, error: 'No response from the game.' } as T
  } finally {
    if (timer) window.clearTimeout(timer)
  }
}

/** A server callback, proxied through the client (see PROXY in client/admin.lua). */
export function call<T = unknown>(name: string, arg?: unknown): Promise<T> {
  return nui<T>('call', { name, arg })
}

type Handler = (data: any) => void
const handlers = new Map<string, Set<Handler>>()

if (typeof window !== 'undefined') {
  window.addEventListener('message', (event) => {
    // FiveM's root UI forwards SendNUIMessage into the resource iframe.
    if (event.source && event.source !== window && event.source !== window.parent) return
    const { action, data } = event.data ?? {}
    if (typeof action !== 'string') return
    handlers.get(action)?.forEach((h) => h(data))
  })
}

export function onNui(action: string, handler: Handler) {
  if (!handlers.has(action)) handlers.set(action, new Set())
  handlers.get(action)!.add(handler)
  return () => { handlers.get(action)!.delete(handler) }
}

export function useNui<T = any>(action: string, handler: (data: T) => void) {
  const ref = useRef(handler)
  ref.current = handler
  useEffect(() => onNui(action, (d) => ref.current(d)), [action])
}

/** Browser preview helper: pretend the game sent a message. */
export function emit(action: string, data?: unknown) {
  window.postMessage({ action, data }, window.location.origin)
}
