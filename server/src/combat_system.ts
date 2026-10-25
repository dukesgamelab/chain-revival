/**
 * Authoritative aim / fire / kill + suppression gain/decay.
 * Port of CombatSystem resolve_shot, apply_suppression_from_shot, recover_stress_tick.
 */

import type { GameState } from "./game_state";
import { towardCell } from "./facing";
import { beginFirePrep } from "./fire_prep";
import {
  combatRange,
  effectiveFireCycleSec,
  finalHitChance,
  LETHALITY_MULTIPLIER,
  weaponFor,
} from "./hit_resolution";
import { evaluate, LOS_BLOCKED, type LosResult } from "./los";
import { COVER_COMPLETE, COVER_MODERATE } from "./map_objects";
import {
  COMBAT_SCAN_TICKS,
  findBestAutoTarget,
  isAutoTargetValid,
  isPriorityTrackable,
  TARGET_LOST_GRACE_MSEC,
} from "./perception";
import type { SoldierState } from "./soldier_state";
import {
  applyStressDecay,
  fireDelayModifier,
  MAX_STRESS,
  MODERATE_COVER_SUPPRESSION_MULT,
  PRONE_SUPPRESSION_MULT,
  rangeSuppressionGainRuntime,
} from "./stress_accuracy";
import { FIRE_AT_WILL, POSITION_DOWN, type CombatShotPayload, type Vec2i } from "./types";
import { ammoCost, effectiveWeaponRange } from "./weapons";

export interface CombatTickResult {
  shots: CombatShotPayload[];
}

export { beginFirePrep } from "./fire_prep";

export function isFirePrepComplete(state: GameState, shooter: SoldierState): boolean {
  if (shooter.fireReadyAfterMsec <= 0) {
    return false;
  }
  return state.clock.getTicksMsec() >= shooter.fireReadyAfterMsec;
}

export function canFireYet(state: GameState, shooter: SoldierState, rangeTiles: number): boolean {
  if (shooter.lastShotMsec <= 0) {
    return true;
  }
  const weapon = weaponFor(shooter);
  const interval = effectiveFireCycleSec(weapon, false, rangeTiles) * fireDelayModifier(shooter.stress);
  const elapsed = (state.clock.getTicksMsec() - shooter.lastShotMsec) / 1000;
  return elapsed >= interval;
}

export function isFacingTarget(shooter: SoldierState, target: SoldierState): boolean {
  const aim = towardCell(shooter.gridPosition, target.gridPosition);
  return aim.x === shooter.facing.x && aim.y === shooter.facing.y;
}

export function resolveShot(
  state: GameState,
  shooter: SoldierState,
  target: SoldierState,
  autoEngagement: boolean,
): CombatShotPayload {
  const shot = emptyShot(state, shooter, target);
  if (shooter.isDead || shooter.isMoving) {
    return shot;
  }
  if (!isFirePrepComplete(state, shooter)) {
    shot.onCooldown = true;
    return shot;
  }
  if (target.isDead || shooter.teamId === target.teamId) {
    return shot;
  }
  const weapon = weaponFor(shooter);
  if (weapon === null) {
    return shot;
  }
  shot.weaponId = weapon.weaponId;
  shot.weaponName = weapon.weaponName;
  if (shooter.ammoCurrent <= 0) {
    shot.noAmmo = true;
    return shot;
  }
  const distance = combatRange(shooter.gridPosition, target.gridPosition);
  if (distance > effectiveWeaponRange(weapon)) {
    shot.outOfRange = true;
    return shot;
  }

  const facing = towardCell(shooter.gridPosition, target.gridPosition);
  if (facing.x !== 0 || facing.y !== 0) {
    shooter.facing = facing;
    shot.facing = { ...facing };
  }

  const los = evaluate(shooter.gridPosition, target.gridPosition, state.map, state.losOccupants());
  shot.coverType = los.coverType;
  shot.cornerPeek = los.cornerPeek;
  shot.peekSide = los.peekSide;
  shot.cornerCell = { ...los.cornerCell };
  if (los.status === LOS_BLOCKED) {
    shot.blocked = true;
    return shot;
  }
  if (!canFireYet(state, shooter, distance)) {
    shot.onCooldown = true;
    return shot;
  }

  const cost = ammoCost(weapon, shooter.ammoCurrent);
  shooter.ammoCurrent -= cost;
  const now = state.clock.getTicksMsec();
  shooter.lastShotMsec = now;
  shooter.lastFiredMsec = now;
  beginFirePrep(state, shooter, distance);
  shot.fired = true;
  state.nextShotId += 1;
  shot.shotId = state.nextShotId;
  shot.tracerCount = weapon.tracerCount;
  shot.ammoCurrent = shooter.ammoCurrent;
  shot.fireReadyAfterMsec = shooter.fireReadyAfterMsec;

  if (los.targetUsingWallCover) {
    shot.hadCover = true;
    return shot;
  }

  const { chance, breakdown } = finalHitChance(shooter, target, weapon, los);
  shot.hitFinal = chance;
  shot.hitBreakdown = breakdown;
  if (los.coverType === COVER_MODERATE || los.coverType === COVER_COMPLETE) {
    shot.hadCover = true;
  }
  const perRoundKill = clamp(chance * LETHALITY_MULTIPLIER, 0, 1);
  const rounds = Math.max(cost, 0);
  shot.killChance = rounds > 0 ? 1 - (1 - perRoundKill) ** rounds : 0;
  let scored = false;
  for (let i = 0; i < rounds; i += 1) {
    if (state.rng.chance(perRoundKill)) {
      scored = true;
      break;
    }
  }
  if (scored) {
    shot.hit = true;
    applyKill(state, shooter, target, shot);
  }

  // Apply suppression to target from this shot (hit or miss).
  if (!target.isDead) {
    applySuppressionFromShot(state, shooter, target, los);
  }

  shot.targetStress = target.stress;
  void autoEngagement;
  return shot;
}

export function tryEngagedFire(state: GameState, shooter: SoldierState): CombatShotPayload | null {
  if (shooter.isDead || shooter.isMoving || shooter.isStunned(state.clock.getTicksMsec())) {
    return null;
  }
  if (!shooter.sustainedFire) {
    return null;
  }
  const target = resolveEngagedTarget(state, shooter, true);
  if (target === null) {
    return null;
  }
  if (shooter.engagedTargetLostMsec > 0) {
    return null;
  }
  if (!isFacingTarget(shooter, target)) {
    shooter.facing = towardCell(shooter.gridPosition, target.gridPosition);
    return null;
  }
  const weapon = weaponFor(shooter);
  if (weapon === null || shooter.ammoCurrent <= 0) {
    return null;
  }
  if (!isFirePrepComplete(state, shooter)) {
    return null;
  }
  const range = combatRange(shooter.gridPosition, target.gridPosition);
  if (!canFireYet(state, shooter, range)) {
    return null;
  }
  return resolveShot(state, shooter, target, true);
}

export function tryAutoEngagement(state: GameState, shooter: SoldierState): CombatShotPayload | null {
  if (shooter.isDead || shooter.isMoving || shooter.isStunned(state.clock.getTicksMsec())) {
    return null;
  }
  if (shooter.sustainedFire) {
    return null;
  }
  if (shooter.fireControlState !== FIRE_AT_WILL) {
    return null;
  }
  if (shooter.ammoCurrent <= 0) {
    return null;
  }
  const target = resolveEngagedTarget(state, shooter, false);
  if (target === null) {
    return null;
  }
  if (shooter.engagedTargetLostMsec > 0) {
    return null;
  }
  if (!isFacingTarget(shooter, target)) {
    shooter.facing = towardCell(shooter.gridPosition, target.gridPosition);
    return null;
  }
  const weapon = weaponFor(shooter);
  if (weapon === null) {
    return null;
  }
  if (!isFirePrepComplete(state, shooter)) {
    return null;
  }
  const range = combatRange(shooter.gridPosition, target.gridPosition);
  if (!canFireYet(state, shooter, range)) {
    return null;
  }
  return resolveShot(state, shooter, target, true);
}

/** Combat scan interval in seconds (COMBAT_SCAN_TICKS * 50ms per tick). */
const COMBAT_SCAN_SEC = (COMBAT_SCAN_TICKS * 50) / 1000;

export function processCombatTick(state: GameState): CombatTickResult {
  // Clear per-tick suppression flags before this scan.
  for (const s of state.soldiers) {
    s.receivedSuppressionThisTick = false;
  }

  const shots: CombatShotPayload[] = [];
  for (const shooter of state.soldiers) {
    if (!shooter.sustainedFire) {
      continue;
    }
    const shot = tryEngagedFire(state, shooter);
    if (shot !== null && shot.fired) {
      shots.push(shot);
    }
  }
  for (const shooter of state.soldiers) {
    if (shooter.sustainedFire) {
      continue;
    }
    const shot = tryAutoEngagement(state, shooter);
    if (shot !== null && shot.fired) {
      shots.push(shot);
    }
  }

  // Recover stress for soldiers who did not receive suppression this tick.
  recoverStressTick(state, COMBAT_SCAN_SEC);

  return { shots };
}

/**
 * Apply suppression stress to the target from an incoming shot.
 * Port of CombatSystem.apply_suppression_from_shot.
 * Gain = (stressLimitTiles - range) * stressFactor * STRESS_SCALE * coverMult * stanceMult.
 */
function applySuppressionFromShot(
  state: GameState,
  shooter: SoldierState,
  target: SoldierState,
  los: LosResult,
): void {
  if (target.isDead || shooter.isDead) {
    return;
  }
  if (los.status === LOS_BLOCKED) {
    return;
  }
  const weapon = weaponFor(shooter);
  if (weapon === null) {
    return;
  }
  const rangeTiles = Math.round(combatRange(shooter.gridPosition, target.gridPosition));
  const gain = rangeSuppressionGainRuntime(
    weapon.suppressionGenerated,
    weapon.stressLimitTiles,
    rangeTiles,
  );
  if (gain <= 0) {
    return;
  }
  let coverMult = 1.0;
  if (los.coverType === COVER_MODERATE) {
    coverMult = MODERATE_COVER_SUPPRESSION_MULT;
  }
  let stanceMult = 1.0;
  if (target.positionState === POSITION_DOWN) {
    stanceMult = PRONE_SUPPRESSION_MULT;
  }
  const finalGain = gain * coverMult * stanceMult;
  if (finalGain <= 0) {
    return;
  }
  target.stress = Math.min(target.stress + finalGain, MAX_STRESS);
  target.receivedSuppressionThisTick = true;
}

/**
 * Exponential stress decay for all living soldiers who were not suppressed this tick.
 * Port of CombatSystem.recover_stress_tick.
 */
function recoverStressTick(state: GameState, deltaSec: number): void {
  for (const soldier of state.soldiers) {
    if (soldier.isDead || soldier.stress <= 0) {
      continue;
    }
    if (soldier.receivedSuppressionThisTick) {
      continue;
    }
    const prone = soldier.positionState === POSITION_DOWN;
    soldier.stress = applyStressDecay(soldier.stress, prone, deltaSec);
  }
}

function resolveEngagedTarget(
  state: GameState,
  shooter: SoldierState,
  sustained: boolean,
): SoldierState | null {
  const now = state.clock.getTicksMsec();
  const current = shooter.isEngaged()
    ? state.getSoldier(shooter.engagedTargetTeamId, shooter.engagedTargetSoldierId)
    : null;
  if (sustained) {
    if (current !== null && !current.isDead && isPriorityTrackable(shooter, current, state)) {
      shooter.engagedTargetLostMsec = 0;
      return current;
    }
    if (current !== null && !targetLostGrace(shooter, now)) {
      return current;
    }
    shooter.clearEngagedTarget();
    return null;
  }
  if (current !== null && !current.isDead && isAutoTargetValid(shooter, current, state)) {
    shooter.engagedTargetLostMsec = 0;
    return current;
  }
  if (current !== null && !targetLostGrace(shooter, now)) {
    return current;
  }
  const next = findBestAutoTarget(state, shooter);
  if (next === null) {
    shooter.clearEngagedTarget();
    shooter.resetFirePrep();
    return null;
  }
  if (shooter.setEngagedTarget(next.teamId, next.soldierId)) {
    beginFirePrep(state, shooter, combatRange(shooter.gridPosition, next.gridPosition));
  }
  return next;
}

function targetLostGrace(shooter: SoldierState, now: number): boolean {
  if (shooter.engagedTargetLostMsec <= 0) {
    shooter.engagedTargetLostMsec = now;
    return false;
  }
  return now - shooter.engagedTargetLostMsec >= TARGET_LOST_GRACE_MSEC;
}

function applyKill(
  state: GameState,
  shooter: SoldierState,
  target: SoldierState,
  shot: CombatShotPayload,
): void {
  target.markKilled(state.rng);
  state.markPerceptionDirty();
  shot.killed = true;
  shot.deathSpriteFamily = target.deathSpriteFamily;
  shot.stanceAtDeath = target.stanceAtDeath;
  shot.movementHalt = target.gridPosition;
  for (const other of state.soldiers) {
    if (other.engagedTargetTeamId === target.teamId && other.engagedTargetSoldierId === target.soldierId) {
      other.clearEngagedTarget();
      other.resetFirePrep();
      if (other !== shooter) {
        other.endSustainedFire();
      }
    }
  }
}

function emptyShot(state: GameState, shooter: SoldierState, target: SoldierState): CombatShotPayload {
  return {
    shotId: 0,
    shooterTeamId: shooter.teamId,
    shooterId: shooter.soldierId,
    targetTeamId: target.teamId,
    targetId: target.soldierId,
    fired: false,
    hit: false,
    killed: false,
    blocked: false,
    noAmmo: false,
    outOfRange: false,
    onCooldown: false,
    hadCover: false,
    coverType: 0,
    weaponId: shooter.weaponId,
    weaponName: "",
    tracerCount: 0,
    cornerPeek: false,
    peekSide: 0,
    cornerCell: { x: -999, y: -999 },
    hitFinal: 0,
    killChance: 0,
    ammoCurrent: shooter.ammoCurrent,
    fireReadyAfterMsec: shooter.fireReadyAfterMsec,
    facing: { ...shooter.facing },
    messages: [],
  };
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

export function faceToward(from: Vec2i, to: Vec2i): Vec2i {
  return towardCell(from, to);
}
