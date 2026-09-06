/**
 * A* matching Godot AStarGrid2D:
 * - octile heuristic
 * - DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES (both cardinals walkable)
 */

import type { MapData } from "./map_data";
import { type Vec2i, vec, vecEq, vecKey } from "./types";

const CARDINALS: Vec2i[] = [vec(1, 0), vec(-1, 0), vec(0, 1), vec(0, -1)];
const DIAGONALS: Vec2i[] = [vec(1, 1), vec(1, -1), vec(-1, 1), vec(-1, -1)];
const SQRT2 = Math.SQRT2;

export function findPath(map: MapData, from: Vec2i, to: Vec2i): Vec2i[] {
  if (!map.isWalkable(from) || !map.isWalkable(to)) {
    return [];
  }
  if (vecEq(from, to)) {
    return [];
  }

  const startKey = vecKey(from);
  const goalKey = vecKey(to);
  const open: string[] = [startKey];
  const cameFrom = new Map<string, string>();
  const gScore = new Map<string, number>();
  const fScore = new Map<string, number>();
  const cells = new Map<string, Vec2i>();
  cells.set(startKey, from);
  gScore.set(startKey, 0);
  fScore.set(startKey, octile(from, to));

  while (open.length > 0) {
    let bestI = 0;
    let bestF = fScore.get(open[0]) ?? Infinity;
    for (let i = 1; i < open.length; i += 1) {
      const f = fScore.get(open[i]) ?? Infinity;
      if (f < bestF) {
        bestF = f;
        bestI = i;
      }
    }
    const currentKey = open.splice(bestI, 1)[0];
    const current = cells.get(currentKey);
    if (current === undefined) {
      continue;
    }
    if (currentKey === goalKey) {
      return reconstruct(cameFrom, cells, currentKey, from);
    }

    for (const next of neighbors(map, current)) {
      const nextKey = vecKey(next);
      const stepCost = current.x !== next.x && current.y !== next.y ? SQRT2 : 1;
      const tentative = (gScore.get(currentKey) ?? Infinity) + stepCost;
      if (tentative >= (gScore.get(nextKey) ?? Infinity)) {
        continue;
      }
      cells.set(nextKey, next);
      cameFrom.set(nextKey, currentKey);
      gScore.set(nextKey, tentative);
      fScore.set(nextKey, tentative + octile(next, to));
      if (!open.includes(nextKey)) {
        open.push(nextKey);
      }
    }
  }
  return [];
}

function neighbors(map: MapData, cell: Vec2i): Vec2i[] {
  const out: Vec2i[] = [];
  for (const d of CARDINALS) {
    const next = vec(cell.x + d.x, cell.y + d.y);
    if (map.isWalkable(next)) {
      out.push(next);
    }
  }
  for (const d of DIAGONALS) {
    const next = vec(cell.x + d.x, cell.y + d.y);
    if (!map.isWalkable(next)) {
      continue;
    }
    const a = vec(cell.x + d.x, cell.y);
    const b = vec(cell.x, cell.y + d.y);
    if (map.isWalkable(a) && map.isWalkable(b)) {
      out.push(next);
    }
  }
  return out;
}

function octile(a: Vec2i, b: Vec2i): number {
  const dx = Math.abs(a.x - b.x);
  const dy = Math.abs(a.y - b.y);
  return (dx + dy) + (SQRT2 - 2) * Math.min(dx, dy);
}

function reconstruct(
  cameFrom: Map<string, string>,
  cells: Map<string, Vec2i>,
  currentKey: string,
  from: Vec2i,
): Vec2i[] {
  const rev: Vec2i[] = [];
  let key = currentKey;
  while (cameFrom.has(key)) {
    const cell = cells.get(key);
    if (cell !== undefined) {
      rev.push(cell);
    }
    key = cameFrom.get(key) as string;
  }
  rev.push(from);
  rev.reverse();
  return rev;
}
