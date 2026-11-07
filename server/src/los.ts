/**
 * Authoritative LOS + cover — port of LOSSystem / CoverSystem / CoverPolicy / LOSPolicy.
 * Shot LOS and spotting LOS stay distinct. Cover is not invisibility.
 */

import {
  chebyshev,
  DIR8,
  gridLine,
  isInSpottingForwardArc,
  lineCellsBetween,
  manhattan,
  snapToCoverOffset,
} from "./grid";
import type { MapData } from "./map_data";
import { COVER_COMPLETE, COVER_MODERATE, COVER_NONE, type ObjectDef } from "./map_objects";
import { TERRAIN_NO_PASS } from "./map_objects";
import { POSITION_DOWN, type Vec2i, vec, vecEq } from "./types";

export const LOS_CLEAR = 0;
export const LOS_COVER = 1;
export const LOS_BLOCKED = 2;

export const QUALIFIER_NONE = 0;
export const QUALIFIER_CORNER = 1;

export const PEEK_NONE = 0;
export const PEEK_LEFT = 1;
export const PEEK_RIGHT = 2;

const CORNER_PEEK_WHILE_PRONE = true;
const PEEK_ADJACENCY = 1;

export interface LosOccupant {
  cell: Vec2i;
  isDead: boolean;
  positionState: number;
  facing?: Vec2i;
}

export interface LosResult {
  status: number;
  coverType: number;
  coverSourceType: string;
  coverSourceCell: Vec2i;
  coverQualifier: number;
  blockingCell: Vec2i;
  blockingType: string;
  shooterUsingWallCover: boolean;
  targetUsingWallCover: boolean;
  targetCoverCell: Vec2i;
  cornerPeek: boolean;
  peekSide: number;
  cornerCell: Vec2i;
  /** Target leaning out of his corner (corner-to-corner): lighter cover than normal. */
  targetLeaning: boolean;
}

export interface CoverResult {
  coverType: number;
  sourceTypeId: string;
  sourceCell: Vec2i;
  qualifier: number;
  inCover: boolean;
}

const MISSING = vec(-999, -999);

export function emptyLos(): LosResult {
  return {
    status: LOS_CLEAR,
    coverType: COVER_NONE,
    coverSourceType: "",
    coverSourceCell: { ...MISSING },
    coverQualifier: QUALIFIER_NONE,
    blockingCell: { ...MISSING },
    blockingType: "",
    shooterUsingWallCover: false,
    targetUsingWallCover: false,
    targetCoverCell: { ...MISSING },
    cornerPeek: false,
    peekSide: PEEK_NONE,
    cornerCell: { ...MISSING },
    targetLeaning: false,
  };
}

export function isAdjacent(a: Vec2i, b: Vec2i): boolean {
  if (vecEq(a, b)) {
    return false;
  }
  return chebyshev(a, b) <= PEEK_ADJACENCY;
}

export function isCompleteCoverWall(def: ObjectDef | null): boolean {
  return def !== null && def.providesCover && def.coverType === COVER_COMPLETE;
}

export function allowsPeekAndShootOver(def: ObjectDef | null): boolean {
  return def !== null && def.providesCover && def.coverType === COVER_MODERATE && !def.blocksLos;
}

export function tileBlocksVision(
  map: MapData,
  cell: Vec2i,
  def: ObjectDef | null,
  observerProne = false,
  targetProne = false,
): boolean {
  if (isCompleteCoverWall(def)) {
    return false;
  }
  if (map.hasObject(cell)) {
    return map.blocksVision(cell, observerProne, targetProne);
  }
  return def !== null && def.blocksLos;
}

export function livingStandingSoldierBlocks(
  cell: Vec2i,
  occupants: LosOccupant[] | null,
): boolean {
  if (occupants === null) {
    return false;
  }
  const soldier = occupants.find((s) => !s.isDead && vecEq(s.cell, cell));
  if (soldier === undefined) {
    return false;
  }
  return soldier.positionState !== POSITION_DOWN;
}

export function cellOccupantProne(cell: Vec2i, occupants: LosOccupant[] | null): boolean {
  if (occupants === null) {
    return false;
  }
  const soldier = occupants.find((s) => !s.isDead && vecEq(s.cell, cell));
  return soldier !== undefined && soldier.positionState === POSITION_DOWN;
}

export function evaluateWallCoverUsage(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  line?: Vec2i[],
): { shooter: boolean; target: boolean; shooterCell: Vec2i; targetCell: Vec2i } {
  const usage = {
    shooter: false,
    target: false,
    shooterCell: { ...MISSING },
    targetCell: { ...MISSING },
  };
  if (vecEq(from, to)) {
    return usage;
  }
  const cells = line ?? lineCellsBetween(from, to);
  const lineSet = new Set(cells.map((c) => `${c.x},${c.y}`));
  for (const cell of cells) {
    if (!isCompleteCoverWall(map.getObjectDef(cell))) {
      continue;
    }
    if (isAdjacent(from, cell)) {
      usage.shooter = true;
      usage.shooterCell = cell;
    }
    if (isAdjacent(to, cell)) {
      usage.target = true;
      usage.targetCell = cell;
    }
  }
  for (const offset of DIR8) {
    const shooterAdj = vec(from.x + offset.x, from.y + offset.y);
    if (map.isInBounds(shooterAdj) && isCompleteCoverWall(map.getObjectDef(shooterAdj)) && lineSet.has(`${shooterAdj.x},${shooterAdj.y}`)) {
      usage.shooter = true;
      usage.shooterCell = shooterAdj;
    }
    const targetAdj = vec(to.x + offset.x, to.y + offset.y);
    if (map.isInBounds(targetAdj) && isCompleteCoverWall(map.getObjectDef(targetAdj)) && lineSet.has(`${targetAdj.x},${targetAdj.y}`)) {
      usage.target = true;
      usage.targetCell = targetAdj;
    }
  }
  return usage;
}

function isCornerPeekBlocker(map: MapData, cell: Vec2i): boolean {
  if (!map.isInBounds(cell)) {
    return false;
  }
  if (map.terrainClass(cell) === TERRAIN_NO_PASS) {
    return true;
  }
  if (isCompleteCoverWall(map.getObjectDef(cell))) {
    return true;
  }
  return map.obstructionHeight(cell) >= 2;
}

// Positive cross -> RIGHT to match wallEndPeekSide's (-dy, dx) "left" and the client's L/R corner art.
function peekSideFromCross(toRef: Vec2i, along: Vec2i): number {
  const cross = toRef.x * along.y - toRef.y * along.x;
  if (cross > 0) {
    return PEEK_RIGHT;
  }
  if (cross < 0) {
    return PEEK_LEFT;
  }
  if ((toRef.x === 0 && toRef.y === 0) || (along.x === 0 && along.y === 0)) {
    return PEEK_NONE;
  }
  return PEEK_LEFT;
}

const ORTHO: Vec2i[] = [vec(-1, 0), vec(1, 0), vec(0, -1), vec(0, 1)];

// Wall tip (1 closed ortho) or building corner (2 adjacent closed). Not a mid-run face.
function isStructureCornerOrWallTip(map: MapData, wall: Vec2i): boolean {
  const closed = ORTHO.filter((d) => isCornerPeekBlocker(map, vec(wall.x + d.x, wall.y + d.y)));
  if (closed.length <= 1) {
    return true;
  }
  if (closed.length >= 3) {
    return false;
  }
  return closed[0].x + closed[1].x !== 0 || closed[0].y + closed[1].y !== 0;
}

function wallRunLength(map: MapData, start: Vec2i, dir: Vec2i): number {
  let n = 0;
  let cell = vec(start.x + dir.x, start.y + dir.y);
  while (n < 64 && isCornerPeekBlocker(map, cell)) {
    n += 1;
    cell = vec(cell.x + dir.x, cell.y + dir.y);
  }
  return n;
}

// Port of CoverSystem.corner_watch_facing: face toward the corner along the wall the soldier
// is lined up with (lean around it); longest such run wins. Without one, look along the wall
// beside him. Null when there is no wall to use.
export function cornerWatchFacing(from: Vec2i, map: MapData): Vec2i | null {
  let inline: Vec2i | null = null;
  let inlineLen = 0;
  let beside: Vec2i | null = null;
  let besideLen = 0;
  for (const offset of ORTHO) {
    const wall = vec(from.x + offset.x, from.y + offset.y);
    if (!isCornerPeekBlocker(map, wall) || !isStructureCornerOrWallTip(map, wall)) {
      continue;
    }
    if (isCornerPeekBlocker(map, vec(wall.x + offset.x, wall.y + offset.y))) {
      const len = wallRunLength(map, wall, offset);
      if (len > inlineLen) {
        inline = { ...offset };
        inlineLen = len;
      }
    }
    for (const run of ORTHO) {
      if ((run.x === offset.x && run.y === offset.y) || (run.x === -offset.x && run.y === -offset.y)) {
        continue;
      }
      if (
        isCornerPeekBlocker(map, vec(wall.x + run.x, wall.y + run.y))
        && !isCornerPeekBlocker(map, vec(from.x + run.x, from.y + run.y))
      ) {
        const len = wallRunLength(map, wall, run);
        if (len > besideLen) {
          beside = { ...run };
          besideLen = len;
        }
      }
    }
  }
  return inline ?? beside;
}

function perpNeighborOpen(map: MapData, cell: Vec2i): boolean {
  if (!map.isInBounds(cell)) {
    return true;
  }
  return !isCornerPeekBlocker(map, cell);
}

function wallEndPeekSide(from: Vec2i, to: Vec2i, wall: Vec2i, map: MapData): number {
  const dx = Math.sign(to.x - from.x);
  const dy = Math.sign(to.y - from.y);
  if (dx === 0 && dy === 0) {
    return PEEK_NONE;
  }
  const leftOff = vec(-dy, dx);
  const rightOff = vec(dy, -dx);
  const leftOpen = perpNeighborOpen(map, vec(wall.x + leftOff.x, wall.y + leftOff.y));
  const rightOpen = perpNeighborOpen(map, vec(wall.x + rightOff.x, wall.y + rightOff.y));
  if (!leftOpen && !rightOpen) {
    return PEEK_NONE;
  }
  if (leftOpen && !rightOpen) {
    return PEEK_LEFT;
  }
  if (rightOpen && !leftOpen) {
    return PEEK_RIGHT;
  }
  return peekSideFromCross(vec(wall.x - from.x, wall.y - from.y), vec(to.x - from.x, to.y - from.y));
}

// A lean only goes around the wall's open end: never through a mid-run face, through the
// run behind a wall tip, or into the corner a building corner closes. wallEndPeekSide alone
// cannot tell, since a diagonal shot checks diagonal neighbours that are open on any run.
// Port of CoverSystem._shot_clears_wall_end.
function shotClearsWallEnd(from: Vec2i, to: Vec2i, wall: Vec2i, map: MapData): boolean {
  if (!isStructureCornerOrWallTip(map, wall)) {
    return false;
  }
  const closed = ORTHO.filter((d) => isCornerPeekBlocker(map, vec(wall.x + d.x, wall.y + d.y)));
  const s = vec(from.x - wall.x, from.y - wall.y);
  const t = vec(to.x - wall.x, to.y - wall.y);
  const dot = (a: Vec2i, b: Vec2i): number => a.x * b.x + a.y * b.y;
  if (closed.length === 2) {
    const inside = (p: Vec2i): boolean => dot(p, closed[0]) > 0 && dot(p, closed[1]) > 0;
    if (inside(s) !== inside(t)) {
      return false;
    }
  }
  for (const run of closed) {
    const perp = vec(-run.y, run.x);
    const a = dot(s, perp);
    const b = dot(t, perp);
    if (a === 0 || (b !== 0 && Math.sign(a) === Math.sign(b))) {
      continue;
    }
    // Where the shot crosses the run's centre line, in tiles along the run from this wall.
    const along = dot(s, run) + (a / (a - b)) * (dot(t, run) - dot(s, run));
    if (along > 0.5) {
      return false;
    }
  }
  return true;
}

function cornerPeekAtCell(
  from: Vec2i,
  to: Vec2i,
  wall: Vec2i,
  map: MapData,
): { isCorner: boolean; peekSide: number; cornerCell: Vec2i } {
  const empty = { isCorner: false, peekSide: PEEK_NONE, cornerCell: { ...MISSING } };
  if (!isAdjacent(from, wall) || !isCornerPeekBlocker(map, wall)) {
    return empty;
  }
  if (!shotClearsWallEnd(from, to, wall, map)) {
    return empty;
  }
  const side = wallEndPeekSide(from, to, wall, map);
  if (side === PEEK_NONE) {
    return empty;
  }
  return { isCorner: true, peekSide: side, cornerCell: wall };
}

function remoteCornerPeek(
  from: Vec2i,
  to: Vec2i,
  blocking: Vec2i,
  map: MapData,
): { isCorner: boolean; peekSide: number; cornerCell: Vec2i } {
  const empty = { isCorner: false, peekSide: PEEK_NONE, cornerCell: { ...MISSING } };
  if (!isCornerPeekBlocker(map, blocking)) {
    return empty;
  }
  if (wallEndPeekSide(from, to, blocking, map) === PEEK_NONE) {
    return empty;
  }
  for (const offset of DIR8) {
    const wall = vec(from.x + offset.x, from.y + offset.y);
    // Only the next tile of the leaned corner's own run; a diagonal neighbour is another wall.
    if (!isOrthogonalAdjacent(wall, blocking)) {
      continue;
    }
    const at = cornerPeekAtCell(from, to, wall, map);
    if (at.isCorner) {
      return at;
    }
  }
  return empty;
}

function isOrthogonalAdjacent(a: Vec2i, b: Vec2i): boolean {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y) === 1;
}

export function cornerPeekFlanksCover(corner: Vec2i, cover: Vec2i): boolean {
  if (cover.x === -999 || corner.x === -999) {
    return false;
  }
  if (vecEq(cover, corner)) {
    return true;
  }
  if (isOrthogonalAdjacent(corner, cover)) {
    return true;
  }
  return chebyshev(corner, cover) <= 2;
}

function canPeekAndShootOver(from: Vec2i, to: Vec2i, cover: Vec2i, def: ObjectDef | null): boolean {
  if (!allowsPeekAndShootOver(def) || !isAdjacent(from, cover)) {
    return false;
  }
  return manhattan(from, cover) <= manhattan(cover, to);
}

export function coverCheck(shooter: Vec2i, target: Vec2i, map: MapData): CoverResult {
  const result: CoverResult = {
    coverType: COVER_NONE,
    sourceTypeId: "",
    sourceCell: { ...MISSING },
    qualifier: QUALIFIER_NONE,
    inCover: false,
  };
  if (vecEq(shooter, target)) {
    return result;
  }
  const toward = vec(shooter.x - target.x, shooter.y - target.y);
  if (toward.x === 0 && toward.y === 0) {
    return result;
  }
  const offset = snapToCoverOffset(toward);
  const cell = vec(target.x + offset.x, target.y + offset.y);
  if (!map.isInBounds(cell) || map.obstructionHeight(cell) < 1) {
    return result;
  }
  result.inCover = true;
  result.sourceCell = cell;
  result.coverType = COVER_MODERATE;
  if (offset.x !== 0 && offset.y !== 0) {
    result.qualifier = QUALIFIER_CORNER;
  }
  const def = map.getObjectDef(cell);
  if (def !== null) {
    result.sourceTypeId = def.typeId;
    if (isCompleteCoverWall(def) && isAdjacent(target, cell) && isCellOnFireLine(shooter, target, cell)) {
      result.coverType = COVER_COMPLETE;
    }
  } else {
    result.sourceTypeId = "terrain";
  }
  return result;
}

export function isCellOnFireLine(from: Vec2i, to: Vec2i, cell: Vec2i): boolean {
  if (vecEq(cell, from) || vecEq(cell, to)) {
    return false;
  }
  return lineCellsBetween(from, to).some((c) => vecEq(c, cell));
}

export function evaluateTargetCover(from: Vec2i, target: Vec2i, map: MapData): CoverResult {
  return coverCheck(from, target, map);
}

interface BlockResult {
  blocked: boolean;
  blockingCell: Vec2i;
  blockingType: string;
  cornerPeek: boolean;
  peekSide: number;
  cornerCell: Vec2i;
}

function emptyBlock(): BlockResult {
  return {
    blocked: false,
    blockingCell: { ...MISSING },
    blockingType: "",
    cornerPeek: false,
    peekSide: PEEK_NONE,
    cornerCell: { ...MISSING },
  };
}

export function findBlockingTile(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  occupants: LosOccupant[] | null = null,
  blockSoldiers = true,
  line?: Vec2i[],
): BlockResult {
  const result = emptyBlock();
  const observerProne = cellOccupantProne(from, occupants);
  const targetProne = cellOccupantProne(to, occupants);
  const cells = line ?? lineCellsBetween(from, to);
  let skippedShooterSide = false;
  let skippedCorner = false;
  for (const cell of cells) {
    if (blockSoldiers && livingStandingSoldierBlocks(cell, occupants)) {
      result.blocked = true;
      result.blockingCell = cell;
      result.blockingType = "soldier";
      return result;
    }
    const def = map.getObjectDef(cell);
    if (def === null && !map.hasObject(cell)) {
      continue;
    }
    const completeWall = isCompleteCoverWall(def);
    const visionBlocks = tileBlocksVision(map, cell, def, observerProne, targetProne);
    const hardBlocks = completeWall || visionBlocks;
    if (!hardBlocks) {
      continue;
    }
    if (!completeWall && !skippedShooterSide && canPeekAndShootOver(from, to, cell, def)) {
      skippedShooterSide = true;
      continue;
    }
    if (!skippedCorner && (CORNER_PEEK_WHILE_PRONE || !observerProne)) {
      let corner = cornerPeekAtCell(from, to, cell, map);
      if (!corner.isCorner) {
        corner = remoteCornerPeek(from, to, cell, map);
      }
      if (corner.isCorner) {
        skippedCorner = true;
        result.cornerPeek = true;
        result.peekSide = corner.peekSide;
        result.cornerCell = corner.cornerCell;
        continue;
      }
    }
    if (
      skippedCorner &&
      result.cornerCell.x !== -999 &&
      isOrthogonalAdjacent(result.cornerCell, cell) &&
      wallEndPeekSide(from, to, cell, map) !== PEEK_NONE
    ) {
      continue;
    }
    if (completeWall && isAdjacent(to, cell)) {
      continue;
    }
    result.blocked = true;
    result.blockingCell = cell;
    result.blockingType = def?.typeId ?? "terrain";
    return result;
  }
  const graze = diagonalWallGraze(from, to, cells, map, result);
  if (graze !== null) {
    result.blocked = true;
    result.blockingCell = graze;
    result.blockingType = map.getObjectDef(graze)?.typeId ?? "terrain";
  }
  return result;
}

// A diagonal step in the shot line that squeezes past a tall wall on either side is blocked
// (no corner cutting, like the pathfinder). Exempt: walls next to the shooter (the corner he
// leans around) and the peeked corner's wall run. Port of CoverSystem._diagonal_wall_graze.
function diagonalWallGraze(
  from: Vec2i,
  to: Vec2i,
  cells: Vec2i[],
  map: MapData,
  block: BlockResult,
): Vec2i | null {
  let prev = from;
  for (const cell of [...cells, to]) {
    if (cell.x !== prev.x && cell.y !== prev.y) {
      for (const side of [vec(cell.x, prev.y), vec(prev.x, cell.y)]) {
        if (!isCornerPeekBlocker(map, side) || isOrthogonalAdjacent(side, from)) {
          continue;
        }
        if (
          block.cornerPeek
          && block.cornerCell.x !== -999
          && (vecEq(side, block.cornerCell) || isOrthogonalAdjacent(side, block.cornerCell))
        ) {
          continue;
        }
        return side;
      }
    }
    prev = cell;
  }
  return null;
}

function spottingCellBlocks(
  from: Vec2i,
  to: Vec2i,
  cell: Vec2i,
  map: MapData,
  observerProne: boolean,
  targetProne: boolean,
  skippedShooterSide: boolean,
  result: BlockResult,
): number {
  const def = map.getObjectDef(cell);
  if (def === null && !map.hasObject(cell)) {
    return -1;
  }
  if (isCompleteCoverWall(def)) {
    return -1;
  }
  if (!tileBlocksVision(map, cell, def, observerProne, targetProne)) {
    return -1;
  }
  if (!skippedShooterSide && canPeekAndShootOver(from, to, cell, def)) {
    return 0;
  }
  result.blocked = true;
  result.blockingCell = cell;
  result.blockingType = def?.typeId ?? "terrain";
  return 1;
}

export function findSpottingBlockingTile(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  observerProne = false,
  targetProne = false,
): BlockResult {
  const result = emptyBlock();
  let skipped = false;
  for (const cell of lineCellsBetween(from, to)) {
    const blocked = spottingCellBlocks(from, to, cell, map, observerProne, targetProne, skipped, result);
    if (blocked < 0) {
      continue;
    }
    if (blocked === 0) {
      skipped = true;
      continue;
    }
    return result;
  }
  return result;
}

export function isSpottingLineBlocked(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  observerProne = false,
  targetProne = false,
): boolean {
  if (!map.isInBounds(from) || !map.isInBounds(to)) {
    return true;
  }
  return findSpottingBlockingTile(from, to, map, observerProne, targetProne).blocked;
}

// Open tiles a soldier hugging a structure corner or wall tip can lean into: beside him,
// perpendicular to the wall, past the wall's end. Port of CoverSystem.corner_peek_cells.
export function cornerPeekCells(cell: Vec2i, map: MapData): Vec2i[] {
  const out: Vec2i[] = [];
  for (const o of ORTHO) {
    const wall = vec(cell.x + o.x, cell.y + o.y);
    if (!isCornerPeekBlocker(map, wall) || !isStructureCornerOrWallTip(map, wall)) {
      continue;
    }
    for (const p of ORTHO) {
      if (p.x * o.x + p.y * o.y !== 0) {
        continue;
      }
      const peek = vec(cell.x + p.x, cell.y + p.y);
      if (
        map.isInBounds(peek)
        && !isCornerPeekBlocker(map, peek)
        && !isCornerPeekBlocker(map, vec(wall.x + p.x, wall.y + p.y))
        && !out.some((c) => vecEq(c, peek))
      ) {
        out.push(peek);
      }
    }
  }
  return out;
}


// ---- Physical line of fire -------------------------------------------------------------
// Walls are full unit squares: tall (height 2) or impassable tiles. Low walls (height 1,
// _HG_Climb) are shoot-over cover, not walls. Port of CoverSystem.is_shot_wall.
export function isShotWall(map: MapData, cell: Vec2i): boolean {
  if (!map.isInBounds(cell) || !map.hasObject(cell)) {
    return false;
  }
  return map.obstructionHeight(cell) >= 2 || map.terrainClass(cell) === TERRAIN_NO_PASS;
}

function gcd(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y !== 0) {
    [x, y] = [y, x % y];
  }
  return x;
}

// First wall the segment between two tile centres passes through, or null. Exact integer
// maths in doubled coordinates (centres even, tile edges odd). Touching a wall's edge or
// corner is allowed; passing between two walls that meet diagonally is not.
// Port of CoverSystem.first_wall_on_segment.
export function firstWallOnSegment(a: Vec2i, b: Vec2i, map: MapData): Vec2i | null {
  if (vecEq(a, b)) {
    return null;
  }
  const ax = 2 * a.x;
  const ay = 2 * a.y;
  const dx = 2 * (b.x - a.x);
  const dy = 2 * (b.y - a.y);
  // Entry parameter t = num / den of the best (earliest) hit so far.
  let bestCell: Vec2i | null = null;
  let bestNum = 1;
  let bestDen = 1;
  for (let y = Math.min(a.y, b.y); y <= Math.max(a.y, b.y); y++) {
    for (let x = Math.min(a.x, b.x); x <= Math.max(a.x, b.x); x++) {
      const cell = vec(x, y);
      if (!isShotWall(map, cell)) {
        continue;
      }
      // Liang-Barsky against the open square (2x-1, 2x+1) x (2y-1, 2y+1).
      let loNum = 0;
      let loDen = 1;
      let hiNum = 1;
      let hiDen = 1;
      let inside = true;
      for (const [p, d, c] of [[ax, dx, 2 * x], [ay, dy, 2 * y]]) {
        if (d === 0) {
          inside = inside && c - 1 < p && p < c + 1;
          continue;
        }
        const s = Math.sign(d);
        const n1 = s * (c - 1 - p);
        const n2 = s * (c + 1 - p);
        const den = Math.abs(d);
        const enter = Math.min(n1, n2);
        const exit = Math.max(n1, n2);
        if (enter * loDen > loNum * den) {
          loNum = enter;
          loDen = den;
        }
        if (exit * hiDen < hiNum * den) {
          hiNum = exit;
          hiDen = den;
        }
      }
      if (inside && loNum * hiDen < hiNum * loDen && loNum * bestDen < bestNum * loDen) {
        bestCell = cell;
        bestNum = loNum;
        bestDen = loDen;
      }
    }
  }
  // Seams: a lattice point of the doubled segment with both coordinates odd is a tile corner.
  const g = gcd(dx, dy);
  const sx = Math.sign(dx);
  const sy = Math.sign(dy);
  for (let k = 1; k < g; k++) {
    const vx = ax + (k * dx) / g;
    const vy = ay + (k * dy) / g;
    if (vx % 2 === 0 || vy % 2 === 0) {
      continue;
    }
    const side1 = vec((vx + sx) / 2, (vy - sy) / 2);
    const side2 = vec((vx - sx) / 2, (vy + sy) / 2);
    if (isShotWall(map, side1) && isShotWall(map, side2) && k * bestDen < bestNum * g) {
      bestCell = side1;
      bestNum = k;
      bestDen = g;
    }
  }
  return bestCell;
}

// No shooting through walls: from his own tile, or (allowLean) from a tile he can lean into
// at a corner or wall tip, the line to the target must not pass through a wall. Returns the
// wall in the way of the direct line, or null when some line is clear.
// Port of CoverSystem.shot_line_wall.
export function shotLineWall(from: Vec2i, to: Vec2i, map: MapData, allowLean: boolean): Vec2i | null {
  const wall = firstWallOnSegment(from, to, map);
  if (wall === null || !allowLean) {
    return wall;
  }
  for (const lean of cornerPeekCells(from, map)) {
    if (!vecEq(lean, to) && firstWallOnSegment(lean, to, map) === null) {
      return null;
    }
  }
  return wall;
}

function lineTouches(from: Vec2i, to: Vec2i, cells: Vec2i[]): boolean {
  return lineCellsBetween(from, to).some((c) => cells.some((x) => vecEq(c, x)));
}

/**
 * Shot LOS. COVER still allows a conceptual shot; BLOCKED does not.
 * Corner-to-corner: when the direct line is blocked, soldiers hugging a corner lean out
 * (shooter always; target only when facing the shooter) and the shot uses those tiles.
 */
export function evaluate(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  occupants: LosOccupant[] | null = null,
): LosResult {
  const direct = evaluateDirect(from, to, map, occupants);
  // Only a line blocked partway (around a corner) qualifies; a target hugging the wall
  // straight between the two keeps its complete cover.
  if (direct.status !== LOS_BLOCKED) {
    return direct;
  }
  // Corner to corner only: both soldiers must be hugging a corner or wall tip.
  const fromPeeks = cornerPeekCells(from, map);
  const toPeeks = cornerPeekCells(to, map);
  if (fromPeeks.length === 0 || toPeeks.length === 0) {
    return direct;
  }
  const targetFacing = occupants?.find((o) => !o.isDead && vecEq(o.cell, to))?.facing;
  const targetCanLean = targetFacing === undefined || isInSpottingForwardArc(to, targetFacing, from, 999);
  const fromCells = [from, ...fromPeeks];
  const toCells = targetCanLean ? [to, ...toPeeks] : [to];
  for (const f of fromCells) {
    for (const t of toCells) {
      if ((vecEq(f, from) && vecEq(t, to)) || lineTouches(f, t, [from, to])) {
        continue;
      }
      // The lean tiles are the whole lean: no second lean from them.
      const peek = evaluateDirect(f, t, map, occupants, false);
      if (peek.status === LOS_BLOCKED || peek.targetUsingWallCover) {
        continue;
      }
      peek.cornerPeek = true;
      // A target leaning out of a corner is only half exposed.
      if (!vecEq(t, to) && peek.coverType === COVER_NONE) {
        peek.coverType = COVER_MODERATE;
        peek.status = LOS_COVER;
        peek.targetLeaning = true;
      }
      return peek;
    }
  }
  return direct;
}

function evaluateDirect(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  occupants: LosOccupant[] | null = null,
  allowLean = true,
): LosResult {
  const result = emptyLos();
  if (!map.isInBounds(from) || !map.isInBounds(to)) {
    result.status = LOS_BLOCKED;
    return result;
  }
  const line = lineCellsBetween(from, to);
  const wall = evaluateWallCoverUsage(from, to, map, line);
  result.shooterUsingWallCover = wall.shooter;
  result.targetUsingWallCover = wall.target;
  result.targetCoverCell = wall.targetCell;
  const block = findBlockingTile(from, to, map, occupants, true, line);
  if (block.cornerPeek) {
    result.cornerPeek = true;
    result.peekSide = block.peekSide;
    result.cornerCell = block.cornerCell;
    if (result.targetUsingWallCover && cornerPeekFlanksCover(result.cornerCell, result.targetCoverCell)) {
      result.targetUsingWallCover = false;
    }
  }
  if (block.blocked) {
    result.status = LOS_BLOCKED;
    result.blockingCell = block.blockingCell;
    result.blockingType = block.blockingType;
    return result;
  }
  // The tile scan above has tolerances (wall-end lean, target hugging a wall, graze
  // exemptions); none of them may put the shot through a wall.
  const wallCell = shotLineWall(from, to, map, allowLean);
  if (wallCell !== null) {
    result.status = LOS_BLOCKED;
    result.blockingCell = wallCell;
    result.blockingType = map.getObjectDef(wallCell)?.typeId ?? "terrain";
    return result;
  }
  if (result.cornerPeek && !result.targetUsingWallCover) {
    result.status = LOS_CLEAR;
    return result;
  }
  const cover = evaluateTargetCover(from, to, map);
  result.coverType = cover.coverType;
  result.coverSourceType = cover.sourceTypeId;
  result.coverSourceCell = cover.sourceCell;
  result.coverQualifier = cover.qualifier;
  result.status =
    cover.coverType === COVER_MODERATE || cover.coverType === COVER_COMPLETE ? LOS_COVER : LOS_CLEAR;
  return result;
}

/** Spotting: soldiers never block; complete-cover walls never block the ray. */
export function evaluateSpotting(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  observerProne = false,
  targetProne = false,
): LosResult {
  const result = emptyLos();
  if (!map.isInBounds(from) || !map.isInBounds(to)) {
    result.status = LOS_BLOCKED;
    return result;
  }
  const block = findSpottingBlockingTile(from, to, map, observerProne, targetProne);
  if (block.blocked) {
    result.status = LOS_BLOCKED;
    result.blockingCell = block.blockingCell;
    result.blockingType = block.blockingType;
    return result;
  }
  const cover = evaluateTargetCover(from, to, map);
  result.coverType = cover.coverType;
  result.coverSourceType = cover.sourceTypeId;
  result.coverSourceCell = cover.sourceCell;
  result.coverQualifier = cover.qualifier;
  result.status = cover.coverType === COVER_MODERATE ? LOS_COVER : LOS_CLEAR;
  return result;
}

/** Unused by evaluate but kept so Bresenham stays identical to Godot. */
export function debugGridLine(from: Vec2i, to: Vec2i): Vec2i[] {
  return gridLine(from, to);
}
