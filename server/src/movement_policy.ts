/**
 * Movement speeds + isometric step cost.
 * Port of scripts/gameplay_policies/movement_policy.gd (defaults only).
 */

import { MOVEMENT_CRAWL, MOVEMENT_WALK, type Vec2i } from "./types";

export const SPEED_RUN = 2.0;
export const SPEED_WALK = 0.6;
export const SPEED_CRAWL = 0.3;
/** World units per second at multiplier 1.0 — matches Soldier presentation. */
export const BASE_WORLD_SPEED = 95.0 / 3.0;
const TILE_WIDTH = 80;
const TILE_HEIGHT = 40;

export function speedMultiplier(mode: number): number {
  if (mode === MOVEMENT_WALK) {
    return SPEED_WALK;
  }
  if (mode === MOVEMENT_CRAWL) {
    return SPEED_CRAWL;
  }
  return SPEED_RUN;
}

/** Unrotated isometric tile center — same as IsometricGrid at view rotation 0. */
export function gridToWorld(cell: Vec2i): { x: number; y: number } {
  const halfW = TILE_WIDTH * 0.5;
  const halfH = TILE_HEIGHT * 0.5;
  return {
    x: (cell.x - cell.y) * halfW,
    y: (cell.x + cell.y) * halfH,
  };
}

export const TYPE_MULT_RUN = 1.05;
export const TYPE_MULT_WALK = 1.15;
export const TYPE_MULT_CRAWL = 0.4;
export const MOVE_MULT_RUN = 0.8;
export const MOVE_MULT_WALK = 0.9;
export const MOVE_MULT_CRAWL = 1.0;
export const APPROACH_HIT_BONUS = 1.35;
const DEG_TO_RAD_OG = 0.0174533;

export function typeHitMultiplier(mode: number): number {
  if (mode === MOVEMENT_WALK) {
    return TYPE_MULT_WALK;
  }
  if (mode === MOVEMENT_CRAWL) {
    return TYPE_MULT_CRAWL;
  }
  return TYPE_MULT_RUN;
}

function moveMultiplier(mode: number): number {
  if (mode === MOVEMENT_WALK) {
    return MOVE_MULT_WALK;
  }
  if (mode === MOVEMENT_CRAWL) {
    return MOVE_MULT_CRAWL;
  }
  return MOVE_MULT_RUN;
}

export function facingToDegrees(facing: Vec2i): number {
  const x = facing.x === 0 && facing.y === 0 ? 0 : facing.x;
  const y = facing.x === 0 && facing.y === 0 ? -1 : facing.y;
  return (Math.atan2(y, x) * 180) / Math.PI;
}

export function angleHitMultiplier(shooterFacing: Vec2i, targetHeading: Vec2i, mode: number): number {
  const moveM = moveMultiplier(mode);
  const deltaDeg = facingToDegrees(shooterFacing) - facingToDegrees(targetHeading);
  const deltaRad = deltaDeg * DEG_TO_RAD_OG;
  return clamp(1 - moveM * Math.abs(Math.sin(deltaRad)), 0, 1);
}

export function approachHitMultiplier(
  shooter: Vec2i,
  target: Vec2i,
  targetHeading: Vec2i,
): number {
  const toSx = shooter.x - target.x;
  const toSy = shooter.y - target.y;
  if (toSx * toSx + toSy * toSy < 0.0001) {
    return 1;
  }
  if (targetHeading.x === 0 && targetHeading.y === 0) {
    return 1;
  }
  const tLen = Math.hypot(toSx, toSy);
  const hLen = Math.hypot(targetHeading.x, targetHeading.y);
  const alignment = (targetHeading.x / hLen) * (toSx / tLen) + (targetHeading.y / hLen) * (toSy / tLen);
  if (alignment <= 0) {
    return 1;
  }
  if (alignment >= 0.7) {
    return APPROACH_HIT_BONUS;
  }
  return 1 + (APPROACH_HIT_BONUS - 1) * (alignment / 0.7);
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

export function stepCostMsec(from: Vec2i, to: Vec2i, speedMult: number): number {
  const a = gridToWorld(from);
  const b = gridToWorld(to);
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const dist = Math.hypot(dx, dy);
  const speed = BASE_WORLD_SPEED * Math.max(speedMult, 0.0001);
  const sec = dist / speed;
  return Math.max(1, Math.round(sec * 1000));
}
