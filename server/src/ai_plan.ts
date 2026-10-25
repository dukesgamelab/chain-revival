/**
 * AI plan types and resolution — port of ai_plan.gd.
 * Pre-game plan selection; Random resolves to a concrete plan via GameRandom.
 */

import type { GameRandom } from "./game_random";

export const PLAN_ATTACK_LEFT = "attack_left";
export const PLAN_ATTACK_CENTER = "attack_center";
export const PLAN_ATTACK_RIGHT = "attack_right";
export const PLAN_DEFEND = "defend";
export const PLAN_FLANK = "flank";
export const PLAN_RANDOM = "random";

/** Concrete plans Random may resolve to (never Random itself). */
export const CONCRETE_IDS: readonly string[] = [
  PLAN_ATTACK_LEFT,
  PLAN_ATTACK_CENTER,
  PLAN_ATTACK_RIGHT,
  PLAN_DEFEND,
  PLAN_FLANK,
];

export const ALL_IDS: readonly string[] = [
  PLAN_ATTACK_LEFT,
  PLAN_ATTACK_CENTER,
  PLAN_ATTACK_RIGHT,
  PLAN_DEFEND,
  PLAN_FLANK,
  PLAN_RANDOM,
];

export function normalizeId(planId: string): string {
  return planId.trim().toLowerCase();
}

export function isValidId(planId: string): boolean {
  return (ALL_IDS as string[]).includes(normalizeId(planId));
}

export function isConcreteId(planId: string): boolean {
  return (CONCRETE_IDS as string[]).includes(normalizeId(planId));
}

export function isRandomId(planId: string): boolean {
  return normalizeId(planId) === PLAN_RANDOM;
}

/**
 * Resolve Random to one concrete plan using GameRandom (deterministic per match seed).
 * Concrete ids pass through unchanged. Invalid/empty falls back to ATTACK_CENTER.
 */
export function resolveToConcrete(planId: string, rng: GameRandom): string {
  const normalized = normalizeId(planId);
  if (isConcreteId(normalized)) {
    return normalized;
  }
  if (!isRandomId(normalized) && normalized.length > 0) {
    return PLAN_ATTACK_CENTER;
  }
  const index = rng.randiRange(0, CONCRETE_IDS.length - 1);
  return CONCRETE_IDS[index];
}

/** Default selected plan for an AI slot (pre-game). Germany -> Defend; USA -> Attack Center. */
export function defaultSelectedForTeam(teamId: number): string {
  return teamId === 2 ? PLAN_DEFEND : PLAN_ATTACK_CENTER;
}

export function displayName(planId: string): string {
  switch (normalizeId(planId)) {
    case PLAN_ATTACK_LEFT:
      return "Attack Left";
    case PLAN_ATTACK_CENTER:
      return "Attack Center";
    case PLAN_ATTACK_RIGHT:
      return "Attack Right";
    case PLAN_DEFEND:
      return "Defend";
    case PLAN_FLANK:
      return "Flank";
    case PLAN_RANDOM:
      return "Random";
    default:
      return "Unknown";
  }
}
