/**
 * Hit-formula stress read only. Does not apply suppression gain/decay.
 * Port of SuppressionPolicy.accuracy_modifier_for + fire_delay_modifier.
 */

const STRESS_SCALE = 100 / 7;
const DEFAULT_EXPERIENCE = 4.0;
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

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}
