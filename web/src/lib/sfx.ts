// Workshop sounds made with WebAudio, so the resource ships no audio files: the impact gun's rattle, a nut
// coming off, the jack handle, a wheel seating. Quiet by design; the game's own audio carries on underneath.

let ctx: AudioContext | null = null
let noise: AudioBuffer | null = null
const VOLUME = 0.22

function audio() {
  if (!ctx) {
    ctx = new AudioContext()
    noise = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate)
    const d = noise.getChannelData(0)
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1
  }
  if (ctx.state === 'suspended') ctx.resume()
  return ctx
}

function noiseSource(a: AudioContext) {
  const src = a.createBufferSource()
  src.buffer = noise
  src.loop = true
  return src
}

/** The impact gun, running until the returned stop() is called. `rate` is hammer blows per second. */
export function rattle(rate = 24) {
  const a = audio()
  const src = noiseSource(a)
  const band = a.createBiquadFilter()
  band.type = 'bandpass'
  band.frequency.value = 1500
  band.Q.value = 1.4
  const amp = a.createGain()
  amp.gain.value = 0
  // the hammer: a square wave gating the noise
  const lfo = a.createOscillator()
  lfo.type = 'square'
  lfo.frequency.value = rate
  const depth = a.createGain()
  depth.gain.value = VOLUME * 0.5
  lfo.connect(depth).connect(amp.gain)
  const motor = a.createOscillator()
  motor.type = 'sawtooth'
  motor.frequency.value = 140
  const motorGain = a.createGain()
  motorGain.gain.value = VOLUME * 0.08
  const out = a.createGain()
  out.gain.setValueAtTime(0, a.currentTime)
  out.gain.linearRampToValueAtTime(1, a.currentTime + 0.04)
  src.connect(band).connect(amp).connect(out)
  motor.connect(motorGain).connect(out)
  out.connect(a.destination)
  src.start()
  lfo.start()
  motor.start()
  let stopped = false
  return {
    pitch(v: number) { motor.frequency.value = 120 + v * 90; lfo.frequency.value = rate * (0.8 + v * 0.5) },
    stop() {
      if (stopped) return
      stopped = true
      const t = a.currentTime
      out.gain.cancelScheduledValues(t)
      out.gain.setValueAtTime(out.gain.value, t)
      out.gain.linearRampToValueAtTime(0, t + 0.06)
      src.stop(t + 0.08); lfo.stop(t + 0.08); motor.stop(t + 0.08)
    },
  }
}

function ping(freq: number, length: number, volume: number, type: OscillatorType = 'sine', drop = 0.6) {
  const a = audio()
  const o = a.createOscillator()
  o.type = type
  const g = a.createGain()
  const t = a.currentTime
  o.frequency.setValueAtTime(freq, t)
  o.frequency.exponentialRampToValueAtTime(freq * drop, t + length)
  g.gain.setValueAtTime(volume * VOLUME, t)
  g.gain.exponentialRampToValueAtTime(0.0001, t + length)
  o.connect(g).connect(a.destination)
  o.start(t)
  o.stop(t + length + 0.02)
}

function thud(freq: number, length: number, volume: number) {
  const a = audio()
  const src = noiseSource(a)
  const lp = a.createBiquadFilter()
  lp.type = 'lowpass'
  lp.frequency.value = freq
  const g = a.createGain()
  const t = a.currentTime
  g.gain.setValueAtTime(volume * VOLUME, t)
  g.gain.exponentialRampToValueAtTime(0.0001, t + length)
  src.connect(lp).connect(g).connect(a.destination)
  src.start(t)
  src.stop(t + length + 0.02)
}

/** An angle grinder (or a polisher, softer): spins up while run(true), and bites harder as load(0..1) goes up. */
export function grinder(kind: 'grind' | 'buff') {
  const a = audio()
  const grind = kind === 'grind'
  const motor = a.createOscillator()
  motor.type = 'sawtooth'
  motor.frequency.value = 0
  const mg = a.createGain()
  mg.gain.value = 0
  const src = noiseSource(a)
  const band = a.createBiquadFilter()
  band.type = 'bandpass'
  band.frequency.value = grind ? 3800 : 1400
  band.Q.value = grind ? 1.2 : 0.8
  const ng = a.createGain()
  ng.gain.value = 0
  motor.connect(mg).connect(a.destination)
  src.connect(band).connect(ng).connect(a.destination)
  motor.start(); src.start()
  let on = false, stopped = false
  const top = grind ? 260 : 150
  return {
    run(v: boolean) {
      if (v === on || stopped) return
      on = v
      const t = a.currentTime
      motor.frequency.setTargetAtTime(v ? top : 0, t, v ? 0.12 : 0.35)
      mg.gain.setTargetAtTime(v ? VOLUME * (grind ? 0.10 : 0.07) : 0, t, v ? 0.05 : 0.3)
      if (!v) ng.gain.setTargetAtTime(0, t, 0.05)
    },
    load(v: number) {
      if (!on || stopped) return
      ng.gain.setTargetAtTime(v * VOLUME * (grind ? 0.55 : 0.25), a.currentTime, 0.04)
      motor.frequency.setTargetAtTime(top * (1 - v * 0.12), a.currentTime, 0.08)
    },
    stop() {
      if (stopped) return
      stopped = true
      const t = a.currentTime
      mg.gain.setTargetAtTime(0, t, 0.05); ng.gain.setTargetAtTime(0, t, 0.05)
      motor.stop(t + 0.3); src.stop(t + 0.3)
    },
  }
}

export const sfx = {
  /** The engine catching: a deep thump and a rising note. */
  start() { thud(180, 0.5, 2.4); ping(60, 0.9, 1.2, 'sawtooth', 1.6); setTimeout(() => ping(95, 0.7, 0.8, 'sawtooth', 1.3), 250) },
  /** It turned over and died. */
  cough() { thud(240, 0.25, 1.6); setTimeout(() => thud(200, 0.2, 1.0), 180) },
  /** A patch buffed up to a shine. */
  shine() { ping(2200, 0.25, 0.3, 'sine', 1.2); setTimeout(() => ping(3300, 0.2, 0.2, 'sine', 1.1), 90) },
  /** A nut spinning free and dropping. */
  nutOff() { ping(2600, 0.18, 0.5, 'triangle', 0.8); setTimeout(() => ping(1900, 0.12, 0.35, 'triangle', 0.9), 140) },
  /** A nut reaching torque: the gun's last hard knock. */
  torqued() { thud(900, 0.12, 1.4); ping(320, 0.12, 0.6, 'square', 0.5) },
  /** Wrong: over-tightened, or the wrong nut. */
  wrong() { ping(180, 0.22, 0.7, 'square', 0.7) },
  /** One stroke of the jack handle. */
  pump() { thud(420, 0.1, 1.2); ping(110, 0.16, 0.9, 'sine', 0.6) },
  /** The wheel sliding home on the studs. */
  seat() { thud(300, 0.3, 2.2); ping(70, 0.3, 1.0, 'sine', 0.7) },
  /** The holes lining up with the studs. */
  click() { ping(1400, 0.05, 0.4, 'square', 1) },
}
