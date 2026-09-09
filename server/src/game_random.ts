/**
 * Server-authoritative gameplay RNG.
 * Same role as GameRandom: hit rolls only — not tracers/audio.
 * Tests inject nextFloat / forceChance.
 */

export class GameRandom {
  private seed: number;
  private state: number;
  callCount = 0;
  /** When set, chance() uses this instead of the stream (tests). */
  forceChance: boolean | null = null;
  nextFloat: (() => number) | null = null;

  constructor(seed = 1) {
    this.seed = seed >>> 0 || 1;
    this.state = this.seed;
  }

  reseed(seed: number): void {
    this.seed = seed >>> 0 || 1;
    this.state = this.seed;
    this.callCount = 0;
    this.forceChance = null;
    this.nextFloat = null;
  }

  getSeed(): number {
    return this.seed;
  }

  randf(): number {
    this.callCount += 1;
    if (this.nextFloat !== null) {
      return this.nextFloat();
    }
    this.state = mulberry32(this.state);
    return (this.state >>> 0) / 4294967296;
  }

  chance(probability: number): boolean {
    if (this.forceChance !== null) {
      this.callCount += 1;
      return this.forceChance;
    }
    return this.randf() <= probability;
  }

  randiRange(from: number, to: number): number {
    if (to < from) {
      return from;
    }
    const span = to - from + 1;
    return from + Math.floor(this.randf() * span);
  }
}

function mulberry32(state: number): number {
  let t = (state + 0x6d2b79f5) >>> 0;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return (t ^ (t >>> 14)) >>> 0;
}
