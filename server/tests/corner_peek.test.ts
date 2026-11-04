import assert from "node:assert/strict";
import { test } from "node:test";
import { cornerPeekCells, cornerWatchFacing, evaluate, LOS_BLOCKED, type LosOccupant } from "../src/los";
import { MapData } from "../src/map_data";
import { COVER_MODERATE } from "../src/map_objects";
import { POSITION_UP, vec, type Vec2i } from "../src/types";

// Building perimeter x 10..20, y 10..14; front wall is row 14.
function buildingMap(): MapData {
  const map = MapData.empty(30, 30);
  for (let x = 10; x <= 20; x++) {
    map.placeObject(vec(x, 10), "wall_straight", "SWAL");
    map.placeObject(vec(x, 14), "wall_straight", "SWAL");
  }
  for (let y = 11; y <= 13; y++) {
    map.placeObject(vec(10, y), "wall_straight", "SWAL");
    map.placeObject(vec(20, y), "wall_straight", "SWAL");
  }
  return map;
}

function occupant(cell: Vec2i, facing: Vec2i): LosOccupant {
  return { cell, isDead: false, positionState: POSITION_UP, facing };
}

test("corner to corner: soldiers at both ends of a wall can trade fire", () => {
  const map = buildingMap();
  const a = vec(10, 15);
  const b = vec(21, 14);
  const occ = [occupant(a, vec(1, 0)), occupant(b, vec(-1, 0))];
  const ab = evaluate(a, b, map, occ);
  assert.notEqual(ab.status, LOS_BLOCKED);
  assert.equal(ab.targetUsingWallCover, false);
  assert.equal(ab.coverType, COVER_MODERATE, "target leaning out is half exposed");
  assert.notEqual(evaluate(b, a, map, occ).status, LOS_BLOCKED);
});

test("corner hugger facing away stays protected", () => {
  const map = buildingMap();
  const a = vec(10, 15);
  const b = vec(21, 14);
  const occ = [occupant(a, vec(1, 0)), occupant(b, vec(0, -1))];
  const ab = evaluate(a, b, map, occ);
  assert.ok(ab.status === LOS_BLOCKED || ab.targetUsingWallCover);
});

test("mid-wall hugger behind the building stays blocked", () => {
  const map = buildingMap();
  const r = evaluate(vec(15, 8), vec(15, 15), map, null);
  assert.ok(r.status === LOS_BLOCKED || r.targetUsingWallCover);
  assert.deepEqual(cornerPeekCells(vec(15, 15), map), []);
});

test("lean needs both soldiers at a corner (no piercing a second wall)", () => {
  const map = MapData.empty(30, 30);
  map.placeObject(vec(11, 10), "wall_straight", "SWAL");
  map.placeObject(vec(12, 11), "wall_straight", "SWAL");
  assert.equal(evaluate(vec(10, 10), vec(14, 12), map, null).status, LOS_BLOCKED);
});

test("arriving at a corner faces around it, along the wall he is lined up with", () => {
  const map = buildingMap();
  // Below the bottom-left corner: lined up with the left wall, so peek up along it.
  assert.deepEqual(cornerWatchFacing(vec(10, 15), map), vec(0, -1));
  // Right of the bottom-right corner: lined up with the front wall, so peek along it.
  assert.deepEqual(cornerWatchFacing(vec(21, 14), map), vec(-1, 0));
  // Left of the bottom-left corner: lined up with the front wall.
  assert.deepEqual(cornerWatchFacing(vec(9, 14), map), vec(1, 0));
  assert.equal(cornerWatchFacing(vec(5, 5), map), null);
});

test("lone straight wall: in line with its end peeks around it, beside it looks along", () => {
  const map = MapData.empty(30, 30);
  for (let x = 5; x <= 10; x++) {
    map.placeObject(vec(x, 5), "wall_straight", "SWAL");
  }
  assert.deepEqual(cornerWatchFacing(vec(4, 5), map), vec(1, 0));
  assert.deepEqual(cornerWatchFacing(vec(5, 6), map), vec(1, 0));
});

// Doorway at (24,40) in a wall row, porch side walls at (23,41) and (25,41).
function doorMap(): MapData {
  const map = MapData.empty(50, 50);
  for (const c of [vec(22, 40), vec(23, 40), vec(25, 40), vec(26, 40), vec(23, 41), vec(25, 41)]) {
    map.placeObject(c, "wall_straight", "SWAL");
  }
  return map;
}

test("diagonal shot grazing past a wall corner is blocked", () => {
  const map = doorMap();
  const shooter = vec(24, 40);
  const target = vec(25, 42);
  // Target facing away: the line cuts past the porch wall end at (25,41) - blocked.
  const away = evaluate(shooter, target, map, [occupant(shooter, vec(0, 1)), occupant(target, vec(0, 1))]);
  assert.equal(away.status, LOS_BLOCKED);
  assert.deepEqual(away.blockingCell, vec(25, 41));
});

test("target facing the doorway leans out and can be hit, with moderate cover", () => {
  const map = doorMap();
  const shooter = vec(24, 40);
  const target = vec(25, 42);
  const facing = evaluate(shooter, target, map, [occupant(shooter, vec(0, 1)), occupant(target, vec(-1, -1))]);
  assert.notEqual(facing.status, LOS_BLOCKED);
  assert.equal(facing.coverType, COVER_MODERATE);
});

test("straight shot out of the doorway is unaffected", () => {
  const map = doorMap();
  assert.notEqual(evaluate(vec(24, 40), vec(24, 45), map, null).status, LOS_BLOCKED);
});
