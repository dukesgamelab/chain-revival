/**
 * Authoritative LOS + cover — port of LOSSystem / CoverSystem / CoverPolicy / LOSPolicy.
 * Shot LOS and spotting LOS stay distinct. Cover is not invisibility.
 */

import {
  chebyshev,
  DIR8,
  gridLine,
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

function peekSideFromCross(toRef: Vec2i, along: Vec2i): number {
  const cross = toRef.x * along.y - toRef.y * along.x;
  if (cross > 0) {
    return PEEK_LEFT;
  }
  if (cross < 0) {
    return PEEK_RIGHT;
  }
  if ((toRef.x === 0 && toRef.y === 0) || (along.x === 0 && along.y === 0)) {
    return PEEK_NONE;
  }
  return PEEK_LEFT;
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
    if (vecEq(wall, blocking) || !isAdjacent(wall, blocking)) {
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
  return result;
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

/** Shot LOS. COVER still allows a conceptual shot; BLOCKED does not. */
export function evaluate(
  from: Vec2i,
  to: Vec2i,
  map: MapData,
  occupants: LosOccupant[] | null = null,
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
