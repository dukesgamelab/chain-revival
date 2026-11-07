import assert from "node:assert/strict";
import { test } from "node:test";
import { cornerPeekCells, evaluate, firstWallOnSegment, LOS_BLOCKED } from "../src/los";
import { MapData } from "../src/map_data";
import { vec, type Vec2i } from "../src/types";

const farm = MapData.loadFromRepo("ff_farm");
const p = (a: Vec2i): string => `(${a.x},${a.y})`;

test("Store Rooms: no shot through the doorway jambs (Farm Fight match log)", () => {
  for (const [from, to] of [
    [vec(42, 46), vec(44, 47)],
    [vec(44, 47), vec(42, 46)],
    [vec(42, 44), vec(44, 47)],
    [vec(44, 47), vec(42, 44)],
    [vec(40, 45), vec(44, 44)],
    [vec(41, 45), vec(46, 45)],
  ]) {
    assert.equal(evaluate(from, to, farm).status, LOS_BLOCKED, `${p(from)} -> ${p(to)}`);
  }
});

test("Store Rooms: shots through the doorway itself still fire", () => {
  for (const [from, to] of [
    [vec(42, 45), vec(44, 45)],
    [vec(42, 44), vec(44, 46)],
    [vec(44, 46), vec(42, 44)],
  ]) {
    assert.notEqual(evaluate(from, to, farm).status, LOS_BLOCKED, `${p(from)} -> ${p(to)}`);
  }
});

test("a target hugging a wall cannot be shot through it", () => {
  const map = MapData.empty(30, 30);
  for (let x = 10; x <= 20; x++) map.placeObject(vec(x, 10), "wall_straight");
  const los = evaluate(vec(15, 5), vec(15, 11), map);
  assert.equal(los.status, LOS_BLOCKED);
  assert.deepEqual(los.blockingCell, vec(15, 10));
  // Angled shots at the hugger are blocked too while the line crosses the wall.
  assert.equal(evaluate(vec(22, 5), vec(20, 11), map).status, LOS_BLOCKED);
  // Past the wall end the line is clear.
  assert.notEqual(evaluate(vec(21, 5), vec(21, 11), map).status, LOS_BLOCKED);
});

test("walls meeting diagonally are sealed; a lone wall corner can be skimmed", () => {
  const sealed = MapData.empty(10, 10);
  sealed.placeObject(vec(4, 4), "wall_straight");
  sealed.placeObject(vec(5, 5), "wall_straight");
  assert.notEqual(firstWallOnSegment(vec(5, 4), vec(4, 5), sealed), null);
  assert.equal(evaluate(vec(6, 3), vec(3, 6), sealed).status, LOS_BLOCKED);
  const lone = MapData.empty(10, 10);
  lone.placeObject(vec(4, 4), "wall_straight");
  assert.deepEqual(firstWallOnSegment(vec(3, 3), vec(5, 5), lone), vec(4, 4));
  assert.equal(firstWallOnSegment(vec(4, 3), vec(6, 5), lone), null, "touching the corner is not entering it");
});

test("low walls (height 1) are not walls for the line of fire", () => {
  const map = MapData.empty(20, 20);
  map.placeObject(vec(5, 5), "haybail");
  assert.equal(firstWallOnSegment(vec(5, 2), vec(5, 8), map), null);
});

test("no shot that fires passes through a wall (ff_farm Store Rooms area)", () => {
  for (let ay = 38; ay <= 52; ay++) for (let ax = 38; ax <= 52; ax++) {
    const a = vec(ax, ay);
    if (!farm.isWalkable(a)) continue;
    for (let by = 38; by <= 52; by++) for (let bx = 38; bx <= 52; bx++) {
      const b = vec(bx, by);
      if (!farm.isWalkable(b) || (ax === bx && ay === by)) continue;
      if (evaluate(a, b, farm).status === LOS_BLOCKED) continue;
      const froms = [a, ...cornerPeekCells(a, farm)];
      const tos = [b, ...cornerPeekCells(b, farm)];
      const clear = froms.some((f) => tos.some((t) => !(f.x === t.x && f.y === t.y) && firstWallOnSegment(f, t, farm) === null));
      assert.ok(clear, `${p(a)} -> ${p(b)} fires through a wall`);
    }
  }
});
