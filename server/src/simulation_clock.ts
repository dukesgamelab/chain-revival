/**
 * Fixed 20 Hz match SimulationClock — same contract as Godot SimulationClock.
 *
 * Tick rate: 20 Hz (50 ms). Chosen because:
 * - evenly divides auto_fire_scan_interval (0.5 s → 10 ticks per combat scan)
 * - keeps fuse/prep/cooldown on a clean millisecond grid
 * - separates sim from render without changing combat cadence
 *
 * Real elapsed time is accumulated and consumed in fixed steps.
 * After a stall, at most DEFAULT_MAX_CATCHUP_TICKS (10 = 500 ms of sim) run
 * in one pump; leftover accumulator beyond that is discarded (same as Godot
 * Main._step_fixed_simulation). That keeps a long hitch from spiraling, at the
 * cost of dropping excess sim time after the cap.
 *
 * tickId increments once per completed fixed step while running.
 * Do not use Date.now() / client wall-clock as gameplay authority.
 */

export const DEFAULT_TICK_HZ = 20;
export const DEFAULT_MAX_CATCHUP_TICKS = 10;

export type ClockStatus = "running" | "paused" | "stopped";

export interface ClockPumpResult {
  steps: number;
  discardedMsec: number;
  capped: boolean;
}

export class SimulationClock {
  private msec = 0;
  private tickId = 0;
  private accumulatorMsec = 0;
  private status: ClockStatus = "running";
  tickHz = DEFAULT_TICK_HZ;
  maxCatchupTicks = DEFAULT_MAX_CATCHUP_TICKS;

  reset(startMsec = 0): void {
    this.msec = Math.max(startMsec, 0);
    this.tickId = 0;
    this.accumulatorMsec = 0;
  }

  getTicksMsec(): number {
    return this.msec;
  }

  getTickId(): number {
    return this.tickId;
  }

  getStatus(): ClockStatus {
    return this.status;
  }

  isRunning(): boolean {
    return this.status === "running";
  }

  tickMsec(): number {
    return Math.max(Math.round(1000 / Math.max(this.tickHz, 1)), 1);
  }

  tickSec(): number {
    return this.tickMsec() / 1000;
  }

  pause(): void {
    if (this.status !== "stopped") {
      this.status = "paused";
    }
  }

  resume(): void {
    if (this.status === "paused") {
      this.status = "running";
    }
  }

  stop(): void {
    this.status = "stopped";
    this.accumulatorMsec = 0;
  }

  start(): void {
    if (this.status === "stopped" || this.status === "paused") {
      this.status = "running";
    }
  }

  advanceMsec(deltaMsec: number): void {
    if (deltaMsec <= 0 || this.status !== "running") {
      return;
    }
    this.msec += deltaMsec;
  }

  /** Advance exactly one configured simulation tick. Returns step msec (0 if paused/stopped). */
  advanceTick(): number {
    if (this.status !== "running") {
      return 0;
    }
    const step = this.tickMsec();
    this.msec += step;
    this.tickId += 1;
    return step;
  }

  /**
   * Consume measured real elapsed time as zero or more fixed ticks.
   * `onTick` runs after each advanced tick (clock already includes that step).
   */
  consumeRealtime(
    elapsedMsec: number,
    onTick?: (tickId: number, tickMsec: number) => void,
  ): ClockPumpResult {
    const empty: ClockPumpResult = { steps: 0, discardedMsec: 0, capped: false };
    if (this.status !== "running" || elapsedMsec <= 0) {
      return empty;
    }
    this.accumulatorMsec += elapsedMsec;
    const stepMsec = this.tickMsec();
    let steps = 0;
    while (this.accumulatorMsec >= stepMsec && steps < this.maxCatchupTicks) {
      this.accumulatorMsec -= stepMsec;
      const advanced = this.advanceTick();
      if (advanced <= 0) {
        break;
      }
      onTick?.(this.tickId, advanced);
      steps += 1;
    }
    let discardedMsec = 0;
    let capped = false;
    if (steps >= this.maxCatchupTicks && this.accumulatorMsec >= stepMsec) {
      discardedMsec = this.accumulatorMsec - (this.accumulatorMsec % stepMsec);
      this.accumulatorMsec %= stepMsec;
      capped = discardedMsec > 0;
    }
    return { steps, discardedMsec, capped };
  }
}
