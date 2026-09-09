/** Hit polynomial + situational stack — CombatSystem.hit_chance / _final_hit_chance. */

import { coverMultiplierForRange } from "./cover_policy";
import { euclidean } from "./grid";
import type { LosResult } from "./los";
import { COVER_COMPLETE, COVER_MODERATE } from "./map_objects";
import {
  angleHitMultiplier,
  approachHitMultiplier,
  typeHitMultiplier,
} from "./movement_policy";
import type { SoldierState } from "./soldier_state";
import { accuracyModifierFor } from "./stress_accuracy";
import {
  MOVEMENT_RUN,
  MOVEMENT_WALK,
  POSITION_DOWN,
  type Vec2i,
} from "./types";
import { getWeapon, hitDenominator, hitNumerator, type WeaponData } from "./weapons";

export const HIT_SCALE = 0.06;
export const AIM_TIME = 1.0;
export const RANGE_EPSILON = 0.25;
export const MIN_HIT_CHANCE = 0.0;
export const OPEN_GROUND_HIT_MULT = 1.15;
export const SHOOTER_PRONE_ACCURACY_MULT = 1.15;
export const TARGET_PRONE_HIT_MULT = 0.55;
export const POINT_BLANK_TILES = 2.0;
export const POINT_BLANK_MIN_HIT = 0.92;
export const LETHALITY_MULTIPLIER = 0.9;
export const BASE_FIRE_CYCLE_SEC = 5.0;
export const FIRST_FIRE_CYCLE_SEC = 5.0;

export interface HitBreakdown {
  base: number;
  coverMult: number;
  openGroundMult: number;
  moveTypeMult: number;
  moveAngleMult: number;
  moveApproachMult: number;
  stressMult: number;
  shooterProneMult: number;
  targetProneMult: number;
  pointBlankFloor: number;
  final: number;
  range: number;
  lethality: number;
}

export function combatRange(from: Vec2i, to: Vec2i): number {
  return euclidean(from, to);
}

export function baseHitChance(from: Vec2i, to: Vec2i, weapon: WeaponData, marksman = 0): number {
  const rangeTiles = combatRange(from, to);
  const d = Math.max(RANGE_EPSILON, rangeTiles - marksman);
  const denom = hitDenominator(weapon, d);
  if (denom <= 0) {
    return MIN_HIT_CHANCE;
  }
  return clamp(HIT_SCALE * hitNumerator(weapon, AIM_TIME) / denom, MIN_HIT_CHANCE, 1);
}

export function finalHitChance(
  shooter: SoldierState,
  target: SoldierState,
  weapon: WeaponData,
  los: LosResult,
): { chance: number; breakdown: HitBreakdown } {
  const base = baseHitChance(shooter.gridPosition, target.gridPosition, weapon, shooter.marksman);
  const dist = combatRange(shooter.gridPosition, target.gridPosition);
  let chance = base;
  let coverMult = 1;
  let openGroundMult = 1;
  let moveTypeMult = 1;
  let moveAngleMult = 1;
  let moveApproachMult = 1;
  const inCover = los.coverType === COVER_MODERATE || los.coverType === COVER_COMPLETE;
  if (inCover) {
    coverMult = coverMultiplierForRange(dist);
    chance = base * coverMult;
  } else {
    openGroundMult = OPEN_GROUND_HIT_MULT;
    chance = base * openGroundMult;
    if (target.isMoving) {
      moveTypeMult = typeHitMultiplier(target.movementMode);
      chance *= moveTypeMult;
      if (target.movementMode === MOVEMENT_RUN || target.movementMode === MOVEMENT_WALK) {
        moveAngleMult = angleHitMultiplier(
          shooter.facing,
          target.movementHeading(),
          target.movementMode,
        );
        chance *= moveAngleMult;
      }
      moveApproachMult = approachHitMultiplier(
        shooter.gridPosition,
        target.gridPosition,
        target.movementHeading(),
      );
      chance *= moveApproachMult;
    }
  }
  const stressMult = accuracyModifierFor(shooter.stress, Math.round(dist), weapon.stressAimFactor);
  chance *= stressMult;
  let shooterProneMult = 1;
  let targetProneMult = 1;
  if (shooter.positionState === POSITION_DOWN) {
    shooterProneMult = SHOOTER_PRONE_ACCURACY_MULT;
    chance *= shooterProneMult;
  }
  if (target.positionState === POSITION_DOWN) {
    targetProneMult = TARGET_PRONE_HIT_MULT;
    chance *= targetProneMult;
  }
  let final = clamp(chance, 0, 1);
  let pointBlankFloor = 0;
  if (dist <= POINT_BLANK_TILES) {
    pointBlankFloor = POINT_BLANK_MIN_HIT;
    final = Math.max(final, pointBlankFloor);
  }
  return {
    chance: final,
    breakdown: {
      base,
      coverMult,
      openGroundMult,
      moveTypeMult,
      moveAngleMult,
      moveApproachMult,
      stressMult,
      shooterProneMult,
      targetProneMult,
      pointBlankFloor,
      final,
      range: dist,
      lethality: LETHALITY_MULTIPLIER,
    },
  };
}

export function weaponFor(shooter: SoldierState): WeaponData | null {
  return getWeapon(shooter.weaponId);
}

export function closeRangeCycleMult(_combatRange: number): number {
  return 1;
}

export function effectiveFireCycleSec(
  weapon: WeaponData | null,
  firstShot: boolean,
  rangeTiles: number,
): number {
  let cycle = BASE_FIRE_CYCLE_SEC;
  if (weapon !== null && weapon.fireIntervalSec > 0) {
    cycle = weapon.fireIntervalSec;
  }
  if (firstShot) {
    if (weapon !== null && weapon.fireIntervalSec > 0) {
      cycle *= FIRST_FIRE_CYCLE_SEC / Math.max(BASE_FIRE_CYCLE_SEC, 0.001);
    } else {
      cycle = FIRST_FIRE_CYCLE_SEC;
    }
  }
  cycle *= closeRangeCycleMult(rangeTiles);
  return cycle;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}
