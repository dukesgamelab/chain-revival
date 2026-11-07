/** Cover hit curve — CoverPolicy.cover_multiplier_for_range. */

export const COVER_HIT_MULTIPLIER = 0.005;
export const COVER_RANGE_LIMIT = 5;
export const COVER_NEAR_FLOOR = 0.5;
export const OBJECT_COVER_STRENGTH = 1.0;
// TUNED: a target leaning out of a corner to fire is only half behind it, so at range he
// keeps this much of his hit chance instead of COVER_HIT_MULTIPLIER (corner-to-corner duels).
export const LEAN_COVER_HIT_MULTIPLIER = 0.25;

export function coverMultiplierForRange(combatRange: number): number {
  const limit = Math.max(COVER_RANGE_LIMIT, 1);
  const r = Math.max(combatRange, 1);
  let mult: number;
  if (r >= limit) {
    mult = COVER_HIT_MULTIPLIER;
  } else {
    mult = ((COVER_HIT_MULTIPLIER - 1.0) * (r - 1.0)) / limit + 1.0;
    mult = Math.max(mult, COVER_NEAR_FLOOR);
  }
  return clamp(mult * OBJECT_COVER_STRENGTH, 0, 1);
}

/** Cover curve for a target leaning out of a corner: never stronger than LEAN_COVER_HIT_MULTIPLIER. */
export function leanCoverMultiplierForRange(combatRange: number): number {
  return Math.max(coverMultiplierForRange(combatRange), LEAN_COVER_HIT_MULTIPLIER);
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}
