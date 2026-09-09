/** Bresenham + compass helpers — same geometry as IsometricGrid / CoverPolicy. */

import { type Vec2i, vec } from "./types";

export const DIR8: Vec2i[] = [
  vec(0, -1),
  vec(1, -1),
  vec(1, 0),
  vec(1, 1),
  vec(0, 1),
  vec(-1, 1),
  vec(-1, 0),
  vec(-1, -1),
];

export function manhattan(a: Vec2i, b: Vec2i): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

export function chebyshev(a: Vec2i, b: Vec2i): number {
  return Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
}

export function euclidean(a: Vec2i, b: Vec2i): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function signi(n: number): number {
  if (n > 0) {
    return 1;
  }
  if (n < 0) {
    return -1;
  }
  return 0;
}

export function normalizeFacing(facing: Vec2i): Vec2i {
  return vec(signi(facing.x), signi(facing.y));
}

/** Inclusive Bresenham — IsometricGrid.grid_line. */
export function gridLine(from: Vec2i, to: Vec2i): Vec2i[] {
  const points: Vec2i[] = [];
  let x0 = from.x;
  let y0 = from.y;
  const x1 = to.x;
  const y1 = to.y;
  const dx = Math.abs(x1 - x0);
  const dy = Math.abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1;
  const sy = y0 < y1 ? 1 : -1;
  let err = dx - dy;
  while (true) {
    points.push(vec(x0, y0));
    if (x0 === x1 && y0 === y1) {
      break;
    }
    const e2 = 2 * err;
    if (e2 > -dy) {
      err -= dy;
      x0 += sx;
    }
    if (e2 < dx) {
      err += dx;
      y0 += sy;
    }
  }
  return points;
}

export function lineCellsBetween(from: Vec2i, to: Vec2i): Vec2i[] {
  return gridLine(from, to).filter((cell) => !(cell.x === from.x && cell.y === from.y) && !(cell.x === to.x && cell.y === to.y));
}

export function snapToCoverOffset(towardShooter: Vec2i): Vec2i {
  const len = Math.hypot(towardShooter.x, towardShooter.y);
  if (len <= 0.0001) {
    return DIR8[0];
  }
  const dirX = towardShooter.x / len;
  const dirY = towardShooter.y / len;
  let best = DIR8[0];
  let bestDot = Number.NEGATIVE_INFINITY;
  for (const offset of DIR8) {
    const slen = Math.hypot(offset.x, offset.y);
    const d = dirX * (offset.x / slen) + dirY * (offset.y / slen);
    if (d > bestDot) {
      bestDot = d;
      best = offset;
    }
  }
  return best;
}

export function towardCell(from: Vec2i, to: Vec2i): Vec2i {
  return vec(signi(to.x - from.x), signi(to.y - from.y));
}

/** ConeOfFire._forward_tiles */
export function forwardTiles(from: Vec2i, facing: Vec2i, target: Vec2i): number {
  const n = normalizeFacing(facing);
  if (n.x === 0 && n.y === 0) {
    return 0;
  }
  const denom = n.x * n.x + n.y * n.y;
  return ((target.x - from.x) * n.x + (target.y - from.y) * n.y) / denom;
}

export function isInSpottingForwardArc(
  from: Vec2i,
  facing: Vec2i,
  target: Vec2i,
  maxRange: number,
): boolean {
  const forward = forwardTiles(from, facing, target);
  return forward > 0 && forward <= maxRange + 0.001;
}

export function isFacingTowardTarget(
  from: Vec2i,
  facing: Vec2i,
  target: Vec2i,
  maxRange: number,
): boolean {
  const want = towardCell(from, target);
  const have = normalizeFacing(facing);
  if (want.x === have.x && want.y === have.y) {
    return true;
  }
  return isInSpottingForwardArc(from, facing, target, maxRange);
}

export function soldierKey(teamId: number, soldierId: number): string {
  return `${teamId}:${soldierId}`;
}
