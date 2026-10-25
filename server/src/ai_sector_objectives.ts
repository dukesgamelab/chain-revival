/**
 * Map-agnostic objective generation from AI plans, spawn geometry, and cover.
 * Port of ai_sector_objectives.gd (standard game modes; survival mode excluded).
 */

import type { GameState } from "./game_state";
import type { MapData } from "./map_data";
import { type AiObjective, makeObjective, isValid } from "./ai_objective";
import {
  PLAN_ATTACK_LEFT,
  PLAN_ATTACK_CENTER,
  PLAN_ATTACK_RIGHT,
  PLAN_DEFEND,
  PLAN_FLANK,
  normalizeId as normalizePlanId,
} from "./ai_plan";
import { coverCheck, type CoverResult } from "./los";
import { TEAM_USA, TEAM_GERMANY, type Vec2i, vec } from "./types";

// --- Constants ---

const DEFEND_FORWARD_CELLS = 10;
const DEFEND_LATERAL_CELLS = 8;
const DEFEND_COVER_RADIUS = 12;
const MAX_COVER_CHECKS_PER_QUERY = 96;

// --- Public API ---

/**
 * Build initial plan objectives for an AI-controlled team.
 * Returns an array of AiObjective ordered by relevance.
 */
export function objectivesForPlan(
  state: GameState,
  teamId: number,
  planId: string,
  claimedCells: Vec2i[] = [],
): AiObjective[] {
  const out: AiObjective[] = [];
  const enemyTeam = teamId === TEAM_USA ? TEAM_GERMANY : TEAM_USA;
  const ownAnchor = teamAnchor(state, teamId);
  const enemyAnchor = teamAnchor(state, enemyTeam);
  const sectors = sectorCells(state.map, ownAnchor, enemyAnchor);
  const plan = normalizePlanId(planId);

  switch (plan) {
    case PLAN_ATTACK_LEFT:
      out.push(pick("attack_left", "Attack Left", sectors.left, claimedCells, "sector", 10));
      break;
    case PLAN_ATTACK_CENTER:
      out.push(pick("attack_center", "Attack Center", sectors.center, claimedCells, "sector", 10));
      break;
    case PLAN_ATTACK_RIGHT:
      out.push(pick("attack_right", "Attack Right", sectors.right, claimedCells, "sector", 10));
      break;
    case PLAN_FLANK: {
      const leftCell = sectors.left[0] ?? vec(0, 0);
      const rightCell = sectors.right[0] ?? vec(0, 0);
      const leftScore = claimPenalty(leftCell, claimedCells);
      const rightScore = claimPenalty(rightCell, claimedCells);
      if (leftScore <= rightScore) {
        out.push(pick("flank_left", "Flank Left", sectors.left, claimedCells, "sector", 12));
      } else {
        out.push(pick("flank_right", "Flank Right", sectors.right, claimedCells, "sector", 12));
      }
      break;
    }
    case PLAN_DEFEND:
      out.push(...defendObjectives(state, teamId, ownAnchor, enemyAnchor, claimedCells));
      break;
    default:
      out.push(pick("attack_center", "Attack Center", sectors.center, claimedCells, "sector", 5));
      break;
  }

  // Optional victory-point objective (DEFEND handles VP itself).
  if (plan !== PLAN_DEFEND) {
    const vp = nearestVictoryPoint(state.map, enemyAnchor);
    if (vp.x > -900) {
      out.push(makeObjective("victory_point", "Victory Point", vp, "sector", 8));
    }
  }

  return out;
}

/** Pick the best option for a fireteam: least claimed, highest priority. */
export function selectForClaims(
  options: AiObjective[],
  claimedCells: Vec2i[] = [],
): AiObjective | null {
  if (options.length === 0) {
    return null;
  }
  let best: AiObjective | null = null;
  let bestScore = 999999999;
  for (const opt of options) {
    if (!isValid(opt)) {
      continue;
    }
    const claim = claimPenalty(opt.cell, claimedCells);
    const score = claim * 100 - opt.priority;
    if (best === null || score < bestScore) {
      best = opt;
      bestScore = score;
    }
  }
  return best ?? options[0];
}

/** Enemy spawn anchor for facing while holding a defensive post. */
export function enemyApproachCell(state: GameState, teamId: number): Vec2i {
  const enemyTeam = teamId === TEAM_USA ? TEAM_GERMANY : TEAM_USA;
  return teamAnchor(state, enemyTeam);
}

/** Retreat toward cover near own spawn. */
export function retreatObjective(state: GameState, teamId: number): AiObjective {
  const ownAnchor = teamAnchor(state, teamId);
  const cover = nearestCoverWithin(state, ownAnchor, ownAnchor, 24, []);
  return makeObjective("retreat", "Retreat", cover.x > -900 ? cover : ownAnchor, "retreat", 20);
}

/** Hold at specific cell. */
export function holdObjectiveAt(cell: Vec2i): AiObjective {
  return makeObjective("hold", "Hold", cell, "hold", 15);
}

/**
 * True when standing at `stand` puts cover BETWEEN that cell and `threat`.
 * Uses the same coverCheck geometry as combat (threat = shooter, stand = target).
 */
export function standCoveredVsThreat(stand: Vec2i, threat: Vec2i, map: MapData): boolean {
  if (threat.x <= -900 || (stand.x === threat.x && stand.y === threat.y)) {
    return false;
  }
  const check = coverCheck(threat, stand, map);
  return check.inCover;
}

/** True when an adjacent cover object sits closer to the threat than `stand`. */
export function standIsDirectlyBehind(stand: Vec2i, threat: Vec2i, map: MapData): boolean {
  if (threat.x <= -900) {
    return false;
  }
  const standD = Math.abs(stand.x - threat.x) + Math.abs(stand.y - threat.y);
  const offsets: Vec2i[] = [vec(1, 0), vec(-1, 0), vec(0, 1), vec(0, -1)];
  for (const offset of offsets) {
    const objCell = vec(stand.x + offset.x, stand.y + offset.y);
    const def = map.getObjectDef(objCell);
    if (def === null || !def.providesCover) {
      continue;
    }
    const objD = Math.abs(objCell.x - threat.x) + Math.abs(objCell.y - threat.y);
    if (objD < standD) {
      return true;
    }
  }
  return false;
}

/**
 * Cover stand within maxDist of nearCell. Returns {x:-999,y:-999} if none.
 * When faceToward is a distinct threat (not nearCell), only stands that pass
 * coverCheck vs that threat are eligible.
 */
export function nearestCoverWithin(
  state: GameState,
  nearCell: Vec2i,
  faceToward: Vec2i,
  maxDist: number,
  claimed: Vec2i[] = [],
  rejectClaimed = false,
  preferBehind = false,
): Vec2i {
  const map = state.map;
  const none = vec(-999, -999);
  if (maxDist < 0) {
    return none;
  }
  const requireDir = faceToward.x > -900 && !(faceToward.x === nearCell.x && faceToward.y === nearCell.y);

  // Collect cover stand cells: tiles with providesCover that have walkable adjacent cells.
  // Since MapData doesn't have getCoverStandCells, scan the map for tiles that provide cover
  // and return their adjacent walkable cells.
  const byDist = new Map<number, Vec2i[]>();
  const coverStands = collectCoverStandCells(map);

  for (const stand of coverStands) {
    const dist = Math.abs(stand.x - nearCell.x) + Math.abs(stand.y - nearCell.y);
    if (dist > maxDist || dist <= 0) {
      continue;
    }
    if (rejectClaimed && claimed.some(c => c.x === stand.x && c.y === stand.y)) {
      continue;
    }
    let bucket = byDist.get(dist);
    if (bucket === undefined) {
      bucket = [];
      byDist.set(dist, bucket);
    }
    bucket.push(stand);
  }

  if (byDist.size === 0) {
    return none;
  }

  const distances = [...byDist.keys()].sort((a, b) => a - b);
  let best = none;
  let bestScore = 999999;
  let checksThisQuery = 0;

  for (let i = 0; i < distances.length; i++) {
    const dist = distances[i];
    const stands = byDist.get(dist)!;
    // Deterministic sort
    stands.sort((a, b) => a.x !== b.x ? a.x - b.x : a.y - b.y);

    for (const stand of stands) {
      if (requireDir) {
        if (checksThisQuery >= MAX_COVER_CHECKS_PER_QUERY) {
          break;
        }
        checksThisQuery++;
        if (!standCoveredVsThreat(stand, faceToward, map)) {
          continue;
        }
      }
      let score = dist + claimPenalty(stand, claimed);
      if (preferBehind && requireDir) {
        if (standIsDirectlyBehind(stand, faceToward, map)) {
          score -= 20;
        } else {
          score += 6;
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = stand;
      }
    }

    // Early out when farther bands cannot beat current best (unless preferBehind).
    if (best.x > -900 && !preferBehind) {
      const nextMin = i + 1 < distances.length ? distances[i + 1] : 999999;
      if (bestScore <= nextMin) {
        return clampWalkable(map, best);
      }
    }
    if (checksThisQuery >= MAX_COVER_CHECKS_PER_QUERY) {
      break;
    }
  }

  if (best.x <= -900) {
    return none;
  }
  return clampWalkable(map, best);
}

// --- Public helper: team anchor ---

export function teamAnchor(state: GameState, teamId: number): Vec2i {
  const spawns = teamId === TEAM_USA ? state.map.team1Spawns : state.map.team2Spawns;
  if (spawns.length === 0) {
    // Fall back to living soldier positions.
    const soldiers = state.soldiersOnTeam(teamId);
    if (soldiers.length === 0) {
      return vec(Math.floor(state.map.width / 2), Math.floor(state.map.height / 2));
    }
    let sx = 0, sy = 0;
    for (const s of soldiers) {
      sx += s.gridPosition.x;
      sy += s.gridPosition.y;
    }
    return vec(Math.floor(sx / soldiers.length), Math.floor(sy / soldiers.length));
  }
  let sx = 0, sy = 0;
  for (const p of spawns) {
    sx += p.x;
    sy += p.y;
  }
  return vec(Math.floor(sx / spawns.length), Math.floor(sy / spawns.length));
}

// --- Internal helpers ---

/** Collect walkable cells adjacent to cover-providing objects. */
function collectCoverStandCells(map: MapData): Vec2i[] {
  const stands: Vec2i[] = [];
  const seen = new Set<string>();
  // Scan all tiles on the map for objects that provide cover
  for (let y = 0; y < map.height; y++) {
    for (let x = 0; x < map.width; x++) {
      const cell = vec(x, y);
      const tile = map.getTile(cell);
      if (tile === null || !tile.providesCover) {
        continue;
      }
      // Cover stands are walkable cells adjacent to this cover object
      for (const offset of [vec(1, 0), vec(-1, 0), vec(0, 1), vec(0, -1), vec(1, 1), vec(-1, -1), vec(1, -1), vec(-1, 1)]) {
        const stand = vec(x + offset.x, y + offset.y);
        const key = `${stand.x},${stand.y}`;
        if (seen.has(key)) {
          continue;
        }
        if (map.isWalkable(stand)) {
          seen.add(key);
          stands.push(stand);
        }
      }
    }
  }
  return stands;
}

function clampWalkable(map: MapData, cell: Vec2i): Vec2i {
  const c = vec(
    Math.max(0, Math.min(cell.x, map.width - 1)),
    Math.max(0, Math.min(cell.y, map.height - 1)),
  );
  if (map.isWalkable(c)) {
    return c;
  }
  for (let radius = 1; radius < 12; radius++) {
    for (let dx = -radius; dx <= radius; dx++) {
      for (let dy = -radius; dy <= radius; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== radius) {
          continue;
        }
        const n = vec(c.x + dx, c.y + dy);
        if (map.isInBounds(n) && map.isWalkable(n)) {
          return n;
        }
      }
    }
  }
  return c;
}

function sectorCells(
  map: MapData,
  ownAnchor: Vec2i,
  enemyAnchor: Vec2i,
): { left: Vec2i[]; center: Vec2i[]; right: Vec2i[] } {
  const mid = vec(
    Math.round((ownAnchor.x + enemyAnchor.x) * 0.5),
    Math.round((ownAnchor.y + enemyAnchor.y) * 0.5),
  );
  const dx = enemyAnchor.x - ownAnchor.x;
  const dy = enemyAnchor.y - ownAnchor.y;
  // Perpendicular offset for left/right sectors
  const px = -dy;
  const py = dx;
  const plen = Math.max(1, Math.sqrt(px * px + py * py));
  const ox = Math.round(px / plen * 8);
  const oy = Math.round(py / plen * 8);
  // Push slightly toward the enemy for attack posts
  const toward = vec(Math.round(dx * 0.35), Math.round(dy * 0.35));
  const center = clampWalkable(map, vec(mid.x + toward.x, mid.y + toward.y));
  const left = clampWalkable(map, vec(mid.x + toward.x + ox, mid.y + toward.y + oy));
  const right = clampWalkable(map, vec(mid.x + toward.x - ox, mid.y + toward.y - oy));
  return { left: [left], center: [center], right: [right] };
}

function defendSectorCells(
  map: MapData,
  ownAnchor: Vec2i,
  enemyAnchor: Vec2i,
): { left: Vec2i[]; center: Vec2i[]; right: Vec2i[] } {
  const dx = enemyAnchor.x - ownAnchor.x;
  const dy = enemyAnchor.y - ownAnchor.y;
  const flen = Math.max(1, Math.sqrt(dx * dx + dy * dy));
  const forward = Math.min(DEFEND_FORWARD_CELLS, Math.max(2, Math.round(flen * 0.2)));
  const lateral = Math.min(DEFEND_LATERAL_CELLS, Math.max(2, forward));
  const fx = Math.round(dx / flen * forward);
  const fy = Math.round(dy / flen * forward);
  const px = -dy;
  const py = dx;
  const plen = Math.max(1, Math.sqrt(px * px + py * py));
  const ox = Math.round(px / plen * lateral);
  const oy = Math.round(py / plen * lateral);
  const base = vec(ownAnchor.x + fx, ownAnchor.y + fy);
  const center = clampWalkable(map, base);
  const left = clampWalkable(map, vec(base.x + ox, base.y + oy));
  const right = clampWalkable(map, vec(base.x - ox, base.y - oy));
  return { left: [left], center: [center], right: [right] };
}

function defendObjectives(
  state: GameState,
  teamId: number,
  ownAnchor: Vec2i,
  enemyAnchor: Vec2i,
  claimedCells: Vec2i[],
): AiObjective[] {
  const out: AiObjective[] = [];
  const sectors = defendSectorCells(state.map, ownAnchor, enemyAnchor);

  const lanes = [
    { id: "defend_center", label: "Defend Center", cells: sectors.center, prio: 14 },
    { id: "defend_left", label: "Defend Left", cells: sectors.left, prio: 12 },
    { id: "defend_right", label: "Defend Right", cells: sectors.right, prio: 12 },
  ];

  const laneClaims = [...claimedCells];
  for (const lane of lanes) {
    if (lane.cells.length === 0) {
      continue;
    }
    const laneCell = lane.cells[0];
    let cover = nearestCoverWithin(state, laneCell, enemyAnchor, DEFEND_COVER_RADIUS, laneClaims, true, true);
    if (cover.x <= -900) {
      cover = clampWalkable(state.map, laneCell);
      if (laneClaims.some(c => c.x === cover.x && c.y === cover.y)) {
        cover = offsetUnclaimed(state.map, cover, laneClaims);
      }
    }
    out.push(makeObjective(lane.id, lane.label, cover, "hold", lane.prio));
    if (cover.x > -900) {
      laneClaims.push(cover);
    }
  }

  // Only chase a VP we don't already control
  const vp = nearestVictoryPoint(state.map, ownAnchor);
  if (vp.x > -900) {
    out.push(makeObjective("victory_point", "Victory Point", vp, "sector", 6));
  }

  return out;
}

function pick(
  id: string,
  label: string,
  candidates: Vec2i[],
  claimed: Vec2i[],
  kind: string,
  prio: number,
): AiObjective {
  let best = vec(-999, -999);
  let bestScore = 999999;
  for (const cell of candidates) {
    const score = claimPenalty(cell, claimed);
    if (score < bestScore) {
      bestScore = score;
      best = cell;
    }
  }
  if (best.x <= -900 && candidates.length > 0) {
    best = candidates[0];
  }
  return makeObjective(id, label, best, kind, prio);
}

function claimPenalty(cell: Vec2i, claimed: Vec2i[]): number {
  let penalty = 0;
  for (const other of claimed) {
    penalty += Math.abs(cell.x - other.x) + Math.abs(cell.y - other.y);
    if (cell.x === other.x && cell.y === other.y) {
      penalty += 40;
    }
  }
  // Deterministic micro tie-break
  penalty += Math.abs(cell.x * 3 + cell.y * 7) % 4;
  return penalty;
}

function nearestVictoryPoint(_map: MapData, _nearCell: Vec2i): Vec2i {
  // MapData does not currently expose victory points. Return none.
  // When victory points are added to MapData, this should scan them.
  return vec(-999, -999);
}

function offsetUnclaimed(map: MapData, cell: Vec2i, claimed: Vec2i[]): Vec2i {
  if (!claimed.some(c => c.x === cell.x && c.y === cell.y)) {
    return cell;
  }
  for (let radius = 1; radius < 8; radius++) {
    for (let dx = -radius; dx <= radius; dx++) {
      for (let dy = -radius; dy <= radius; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== radius) {
          continue;
        }
        const n = vec(cell.x + dx, cell.y + dy);
        if (claimed.some(c => c.x === n.x && c.y === n.y)) {
          continue;
        }
        if (map.isInBounds(n) && map.isWalkable(n)) {
          return n;
        }
      }
    }
  }
  return cell;
}
