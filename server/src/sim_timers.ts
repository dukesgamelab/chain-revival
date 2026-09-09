/**
 * Authoritative gameplay timers keyed to SimulationClock time.
 *
 * Do not use setTimeout / Date.now() for gameplay (fuses, cooldowns, recovery).
 * Schedule a deadline in simulation msec; LocalMatch.polls due timers each tick.
 *
 * Presentation (anims, particles, UI) must not use this.
 */

import type { SimulationClock } from "./simulation_clock";

export type SimTimerHandler = (id: string, clock: SimulationClock) => void;

interface SimTimerEntry {
  dueMsec: number;
  handler?: SimTimerHandler;
}

export class SimTimers {
  private readonly items = new Map<string, SimTimerEntry>();

  schedule(id: string, dueSimMsec: number, handler?: SimTimerHandler): void {
    this.items.set(id, { dueMsec: Math.max(0, dueSimMsec), handler });
  }

  scheduleAfter(
    id: string,
    delayMsec: number,
    clock: SimulationClock,
    handler?: SimTimerHandler,
  ): void {
    this.schedule(id, clock.getTicksMsec() + Math.max(0, delayMsec), handler);
  }

  cancel(id: string): void {
    this.items.delete(id);
  }

  has(id: string): boolean {
    return this.items.has(id);
  }

  remainingMsec(id: string, clock: SimulationClock): number {
    const entry = this.items.get(id);
    if (entry === undefined) {
      return 0;
    }
    return Math.max(0, entry.dueMsec - clock.getTicksMsec());
  }

  /** Fire and remove every timer whose deadline is at or before current sim time. */
  pollDue(clock: SimulationClock): string[] {
    const due: string[] = [];
    for (const [id, entry] of this.items) {
      if (clock.getTicksMsec() >= entry.dueMsec) {
        due.push(id);
        this.items.delete(id);
        entry.handler?.(id, clock);
      }
    }
    return due;
  }

  clear(): void {
    this.items.clear();
  }

  get size(): number {
    return this.items.size;
  }
}
