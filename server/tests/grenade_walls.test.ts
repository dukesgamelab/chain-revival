import assert from "node:assert/strict";
import { test } from "node:test";
import { grenadeThrowRefusal } from "../src/grenade_system";
import { MapData } from "../src/map_data";
import { vec } from "../src/types";

// Farm Fight match 2026-11-07, Store Rooms: west wall x=43 with a doorway at (43,45).
const farm = MapData.loadFromRepo("ff_farm");
const THROUGH = "No clear throw - a wall is in the way.";
const ONTO = "Cannot throw onto a wall.";

test("Store Rooms: no grenade thrown out through the west wall", () => {
  // From inside the room to just outside (the throw that ended the match, and one that missed).
  assert.equal(grenadeThrowRefusal(farm, vec(44, 44), vec(42, 42)), THROUGH);
  assert.equal(grenadeThrowRefusal(farm, vec(44, 44), vec(41, 44)), THROUGH);
});

test("Store Rooms: no grenade onto a wall tile", () => {
  // Thrown from the doorway onto the south-west corner; the blast stunned the man outside.
  assert.equal(grenadeThrowRefusal(farm, vec(43, 45), vec(43, 49)), ONTO);
});

test("Store Rooms: throwing out of the doorway still works", () => {
  assert.equal(grenadeThrowRefusal(farm, vec(44, 46), vec(42, 44)), "");
  // Two tiles in and off to the side, the line clips the door frame: refused like the shot.
  assert.equal(grenadeThrowRefusal(farm, vec(44, 47), vec(43, 45)), THROUGH);
  assert.equal(grenadeThrowRefusal(farm, vec(44, 45), vec(41, 45)), "");
});

test("low cover does not stop a throw", () => {
  const map = MapData.empty(20, 20);
  for (let y = 5; y <= 15; y++) map.placeObject(vec(10, y), "haybail");
  assert.equal(grenadeThrowRefusal(map, vec(8, 10), vec(12, 10)), "");
});
