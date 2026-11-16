import assert from "node:assert/strict";
import { test } from "node:test";
import { executeMove, processMovementTick } from "../src/action_resolver";
import { GameState } from "../src/game_state";
import { MapData } from "../src/map_data";
import {
  MATCH_ID,
  MOVEMENT_RUN,
  MOVE_SCOPE_SINGLE,
  MOVE_SCOPE_SQUAD,
  TEAM_USA,
  vec,
  vecEq,
} from "../src/types";

function makeState(): GameState {
  return new GameState(MapData.empty());
}

function usa(state: GameState, id = 1) {
  const soldier = state.getSoldier(TEAM_USA, id);
  assert.ok(soldier);
  return soldier;
}

function moveCmd(soldierId: number, target: { x: number; y: number }, scope = MOVE_SCOPE_SINGLE) {
  return {
    type: "move_command" as const,
    matchId: MATCH_ID,
    requestId: "m1",
    teamId: TEAM_USA,
    soldierId,
    targetCell: target,
    scope,
    movementMode: MOVEMENT_RUN,
  };
}

test("reissuing the same destination keeps the path and step progress", () => {
  const state = makeState();
  const soldier = usa(state);
  const target = vec(soldier.gridPosition.x + 4, soldier.gridPosition.y);
  const first = executeMove(state, moveCmd(soldier.soldierId, target), TEAM_USA);
  assert.equal(first.success, true);
  assert.ok(soldier.currentPath.length >= 3);
  const kept = soldier.currentPath.map((cell) => ({ ...cell }));
  soldier.moveAccumMsec = 40;
  const again = executeMove(state, moveCmd(soldier.soldierId, target), TEAM_USA);
  assert.equal(again.success, true);
  assert.equal(again.moveOrders.length, 0);
  assert.equal(soldier.moveAccumMsec, 40);
  assert.equal(soldier.currentPath.length, kept.length);
  for (let i = 0; i < kept.length; i += 1) {
    assert.ok(vecEq(soldier.currentPath[i], kept[i]));
  }
});

test("a redirect that keeps the next cell keeps step progress", () => {
  const state = makeState();
  const soldier = usa(state);
  const target = vec(soldier.gridPosition.x + 4, soldier.gridPosition.y);
  executeMove(state, moveCmd(soldier.soldierId, target), TEAM_USA);
  const next = { ...soldier.currentPath[1] };
  soldier.moveAccumMsec = 40;
  const redirect = executeMove(state, moveCmd(soldier.soldierId, next), TEAM_USA);
  assert.equal(redirect.success, true);
  assert.equal(soldier.moveAccumMsec, 40);
  assert.ok(vecEq(soldier.currentPath[1], next));

  soldier.assignPath([soldier.gridPosition, vec(soldier.gridPosition.x, soldier.gridPosition.y + 1)], 2);
  assert.equal(soldier.moveAccumMsec, 0);
});

test("a blocked next cell aborts without changing the cell", () => {
  const state = makeState();
  const soldier = usa(state);
  const next = vec(soldier.gridPosition.x + 1, soldier.gridPosition.y);
  state.map.placeObject(next, "tree", "", { terrain: "NO_PASS" });
  assert.equal(state.map.isBlocked(next), true);
  soldier.assignPath([soldier.gridPosition, next], 2);
  soldier.moveAccumMsec = soldier.moveStepCostMsec;
  const stayed = { ...soldier.gridPosition };
  const tick = processMovementTick(state);
  assert.ok(vecEq(soldier.gridPosition, stayed));
  assert.equal(soldier.isMoving, false);
  assert.equal(tick.movementSteps.length, 0);
  assert.ok(tick.movementCompletions.length > 0);
});

test("squad re-click of the same destination succeeds without new orders", () => {
  const state = makeState();
  const lead = usa(state, 1);
  const target = vec(lead.gridPosition.x + 4, lead.gridPosition.y);
  const first = executeMove(state, moveCmd(lead.soldierId, target, MOVE_SCOPE_SQUAD), TEAM_USA);
  assert.equal(first.success, true, first.statusMessage);
  assert.ok(first.moveOrders.length > 0);
  for (const soldier of state.soldiers) {
    if (soldier.teamId === TEAM_USA && soldier.isMoving) {
      soldier.moveAccumMsec = 25;
    }
  }
  const again = executeMove(state, moveCmd(lead.soldierId, target, MOVE_SCOPE_SQUAD), TEAM_USA);
  assert.equal(again.success, true, again.statusMessage);
  assert.equal(again.moveOrders.length, 0);
  for (const soldier of state.soldiers) {
    if (soldier.teamId === TEAM_USA && soldier.currentPath.length > 1) {
      assert.equal(soldier.moveAccumMsec, 25);
    }
  }
});

test("walkability follows terrain, not the saved blocked set", () => {
  const listed = vec(8, 8);
  const map = new MapData(
    "blocked_set",
    24,
    24,
    [listed],
    [vec(2, 2), vec(3, 2), vec(4, 2), vec(5, 2)],
    [vec(2, 10), vec(3, 10), vec(4, 10), vec(5, 10)],
  );
  assert.equal(map.isBlocked(listed), false);
  assert.equal(map.isWalkable(vec(6, 6)), true);

  const noPass = vec(7, 7);
  map.placeObject(noPass, "tree", "", { terrain: "NO_PASS", terrain_height: 0 });
  assert.equal(map.isBlocked(noPass), true);

  const climb = vec(7, 8);
  map.placeObject(climb, "tree", "", { terrain: "CLIMB", terrain_height: 0 });
  assert.equal(map.isBlocked(climb), true);

  const tall = vec(7, 9);
  map.placeObject(tall, "tree", "", { terrain: "EVEN", terrain_height: 1 });
  assert.equal(map.isBlocked(tall), true);

  map.applyTerrainGameplay = false;
  assert.equal(map.isBlocked(noPass), false);
  assert.equal(map.isBlocked(vec(-1, 0)), false);
});
