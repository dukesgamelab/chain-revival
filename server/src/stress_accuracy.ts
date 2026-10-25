/**
 * Stress/suppression system: accuracy read + suppression gain/decay.
 * Port of SuppressionPolicy (accuracy_modifier_for, fire_delay_modifier,
 * range_suppression_gain_runtime, apply_stress_decay).
 */

const ORIGINAL_MAX_STRESS = 7.0;
const STRESS_SCALE = 100 / ORIGINAL_MAX_STRESS;
const DEFAULT_EXPERIENCE = 4.0;
const MAX_STRESS = 100;
const STRESS_MULTIPLIER_GLOBAL = 1.0;

/** Retain fraction over one decay_reference_sec period of no incoming fire. */
const STRESS_FALL_MULTIPLIER = 0.3;
/** Seconds over which STRESS_FALL_MULTIPLIER is applied once. Matches base fire cycle. */
const DECAY_REFERENCE_SEC = 5.5;

/** Cover/stance multipliers for suppression gain. */
export const MODERATE_COVER_SUPPRESSION_MULT = 0.65;
export const PRONE_SUPPRESSION_MULT = 0.75;

const TIER_KEYS = [-8, -4, 0, 4, 8];
const TIER_ROWS: number[][] = [
  [0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0],
  [1.0, 1.5, 1.5, 2.0, 2.5, 3.0, 3.0],
  [1.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0],
  [1.0, 4.0, 4.5, 4.5, 5.0, 5.0, 5.0],
  [1.0, 4.0, 4.5, 4.5, 5.0, 5.0, 5.0],
];
const FIRE_DELAY_BY_BAND = [1.0, 1.05, 1.15, 1.3, 1.5];
const BAND_NERVOUS = 10;
const BAND_SUPPRESSED = 25;
const BAND_PINNED = 45;
const BAND_PANICKED = 70;

export function fireDelayModifier(stress: number): number {
  const band = stressBand(stress);
  return FIRE_DELAY_BY_BAND[band] ?? 1;
}

export function accuracyModifierFor(
  runtimeStress: number,
  distanceTiles: number,
  stressAimFactor = 1.0,
): number {
  const tier = DEFAULT_EXPERIENCE - runtimeStress / STRESS_SCALE;
  const band = Math.max(0, Math.min(6, Math.round(distanceTiles)));
  const tableMult = accuracyMultiplier(tier, band);
  return applyStressAimFactor(tableMult, stressAimFactor);
}

function stressBand(stress: number): number {
  if (stress < BAND_NERVOUS) {
    return 0;
  }
  if (stress < BAND_SUPPRESSED) {
    return 1;
  }
  if (stress < BAND_PINNED) {
    return 2;
  }
  if (stress < BAND_PANICKED) {
    return 3;
  }
  return 4;
}

function accuracyMultiplier(effectiveTier: number, rangeBand: number): number {
  const raw = rawWeight(effectiveTier, rangeBand);
  const ref = rawWeight(TIER_KEYS[TIER_KEYS.length - 1], rangeBand);
  if (ref <= 0.0001) {
    return 1;
  }
  return clamp(raw / ref, 0, 2);
}

function applyStressAimFactor(tableMultiplier: number, stressAimFactor: number): number {
  const degradation = 1 - clamp(tableMultiplier, 0, 1);
  return clamp(1 - degradation * Math.max(stressAimFactor, 0), 0.05, 1);
}

function rawWeight(effectiveTier: number, band: number): number {
  const b = Math.max(0, Math.min(6, band));
  if (effectiveTier <= TIER_KEYS[0]) {
    return TIER_ROWS[0][b];
  }
  if (effectiveTier >= TIER_KEYS[TIER_KEYS.length - 1]) {
    return TIER_ROWS[TIER_ROWS.length - 1][b];
  }
  for (let i = 0; i < TIER_KEYS.length - 1; i += 1) {
    const lo = TIER_KEYS[i];
    const hi = TIER_KEYS[i + 1];
    if (effectiveTier >= lo && effectiveTier <= hi) {
      const t = hi === lo ? 0 : (effectiveTier - lo) / (hi - lo);
      return TIER_ROWS[i][b] + (TIER_ROWS[i + 1][b] - TIER_ROWS[i][b]) * t;
    }
  }
  return 1;
}

/**
 * RECOVERED: (stressLimitTiles - range) * stressFactor -> runtime 0-100.
 * No gain at or beyond the weapon's range cutoff.
 */
export function rangeSuppressionGainRuntime(
  stressFactor: number,
  stressLimitTiles: number,
  rangeTiles: number,
): number {
  if (stressLimitTiles <= 0 || rangeTiles >= stressLimitTiles) {
    return 0;
  }
  const original = (stressLimitTiles - rangeTiles) * stressFactor;
  if (original <= 0) {
    return 0;
  }
  return original * STRESS_MULTIPLIER_GLOBAL * STRESS_SCALE;
}

/**
 * Exponential stress decay toward 0 when not taking fire.
 * Prone recovers 2x faster (retain^0.5 per period).
 */
export function applyStressDecay(
  runtimeStress: number,
  prone: boolean,
  deltaSec: number,
): number {
  if (runtimeStress <= 0) {
    return 0;
  }
  const dt = Math.max(deltaSec, 0);
  if (dt <= 0) {
    return runtimeStress;
  }
  let retainPeriod = STRESS_FALL_MULTIPLIER;
  if (prone) {
    retainPeriod *= 0.5;
  }
  retainPeriod = clamp(retainPeriod, 0, 1);
  const period = Math.max(DECAY_REFERENCE_SEC, 0.001);
  const retain = retainPeriod ** (dt / period);
  return Math.max(0, runtimeStress * retain);
}

export { MAX_STRESS };

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}
