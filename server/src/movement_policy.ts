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
