import type { GameState } from "./game_state";
import { effectiveFireCycleSec, weaponFor } from "./hit_resolution";
import type { SoldierState } from "./soldier_state";
import { fireDelayModifier } from "./stress_accuracy";

export function beginFirePrep(state: GameState, shooter: SoldierState, combatRangeTiles = -1): void {
  const weapon = weaponFor(shooter);
  const firstShot = shooter.lastShotMsec <= 0;
  let delay = effectiveFireCycleSec(weapon, firstShot, combatRangeTiles);
  delay *= fireDelayModifier(shooter.stress);
  shooter.fireReadyAfterMsec = state.clock.getTicksMsec() + Math.floor(delay * 1000);
}
