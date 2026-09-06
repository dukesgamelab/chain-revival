/** Fixed 20 Hz clock — same contract as Godot SimulationClock. */

export const DEFAULT_TICK_HZ = 20;

export class SimulationClock {
  private msec = 0;
  readonly tickHz = DEFAULT_TICK_HZ;

  reset(startMsec = 0): void {
    this.msec = Math.max(startMsec, 0);
  }

  getTicksMsec(): number {
    return this.msec;
  }

  tickMsec(): number {
    return Math.max(Math.round(1000 / this.tickHz), 1);
  }

  advanceTick(): number {
    const step = this.tickMsec();
    this.msec += step;
    return step;
  }
}
