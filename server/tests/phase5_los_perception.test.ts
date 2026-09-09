import assert from "node:assert/strict";
import { test } from "node:test";
import { executeFireAt, executeFireControl } from "../src/action_resolver";
import { towardCell } from "../src/facing";
import { GameState } from "../src/game_state";
import {
  evaluate,
  evaluateSpotting,
  evaluateTargetCover,
  isSpottingLineBlocked,
  LOS_BLOCKED,
  LOS_CLEAR,
} from "../src/los";
import { MapData } from "../src/map_data";
import { COVER_COMPLETE, COVER_MODERATE, COVER_NONE } from "../src/map_objects";
import { canAssignManualPriority, COMBAT_SCAN_TICKS, findBestAutoTarget } from "../src/perception";
import {
  FIRE_AT_WILL,
  FIRE_HOLD,
  MATCH_ID,
  MOVE_SCOPE_SINGLE,
  POSITION_DOWN,
  POSITION_UP,
  TEAM_GERMANY,
  TEAM_USA,
  vec,
} from "../src/types";

function emptyState(): GameState {
  return new GameState(MapData.empty(24, 24));
}

function usa(state: GameState, id = 1) {
  const s = state.getSoldier(TEAM_USA, id);
  assert.ok(s);
  return s;
}

function ger(state: GameState, id = 1) {
  const s = state.getSoldier(TEAM_GERMANY, id);
  assert.ok(s);
  return s;
}

function parkOthers(state: GameState): void {
  for (const s of state.soldiers) {
    if (s.soldierId === 1) {
      continue;
    }
    s.isDead = true;
  }
}

function pairFacing(state: GameState, a = vec(4, 4), b = vec(4, 10)): void {
  parkOthers(state);
  const shooter = usa(state);
  const target = ger(state);
  shooter.gridPosition = a;
  target.gridPosition = b;
  shooter.facing = towardCell(a, b);
  target.facing = towardCell(b, a);
  shooter.isDead = false;
  target.isDead = false;
  shooter.positionState = POSITION_UP;
  target.positionState = POSITION_UP;
  shooter.fireControlState = FIRE_HOLD;
  target.fireControlState = FIRE_HOLD;
  state.perception.rebuildVisibility(state);
}

test("farm map loads gameplay objects without presentation data", () => {
  const map = MapData.loadFromRepo("ff_farm");
  assert.ok(map.width > 10);
  assert.ok(map.hasObject(vec(7, 49)));
  const tree = map.getTile(vec(7, 49));
  assert.ok(tree);
  assert.equal(tree.family, "TR01");
  assert.equal(tree.height, 2);
  assert.ok(tree.typeId.length > 0);
  assert.ok(!JSON.stringify(tree).includes(".png"));
});

test("clear shot LOS on open ground", () => {
  const map = MapData.empty();
  const los = evaluate(vec(4, 4), vec(4, 10), map, []);
  assert.equal(los.status, LOS_CLEAR);
  assert.equal(los.coverType, COVER_NONE);
});

test("height-2 non-wall blocker blocks shot and spotting", () => {
  const map = MapData.empty();
  map.placeObject(vec(4, 7), "coc_blocker", "");
  assert.equal(evaluate(vec(4, 4), vec(4, 10), map, []).status, LOS_BLOCKED);
  assert.equal(isSpottingLineBlocked(vec(4, 4), vec(4, 10), map, false, false), true);
});

test("facing cone is required to spot", () => {
  const state = emptyState();
  pairFacing(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  usa(state).facing = vec(0, -1);
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
});

test("prone observer cannot see over height-1 hay / window", () => {
  const map = MapData.empty();
  map.placeObject(vec(4, 7), "haybail", "BG01");
  assert.equal(isSpottingLineBlocked(vec(4, 4), vec(4, 10), map, false, false), false);
  assert.equal(isSpottingLineBlocked(vec(4, 4), vec(4, 10), map, true, false), true);
  map.placeObject(vec(8, 7), "coc_swin", "SWIN");
  assert.equal(isSpottingLineBlocked(vec(8, 4), vec(8, 10), map, false, false), false);
  assert.equal(isSpottingLineBlocked(vec(8, 4), vec(8, 10), map, true, false), true);
});

test("complete wall does not block spotting but hard-blocks the shot unless adjacent", () => {
  const map = MapData.empty();
  map.placeObject(vec(4, 7), "wall_straight", "SWAL");
  const spot = evaluateSpotting(vec(4, 4), vec(4, 10), map, false, false);
  assert.notEqual(spot.status, LOS_BLOCKED);
  const shot = evaluate(vec(4, 4), vec(4, 10), map, []);
  assert.equal(shot.status, LOS_BLOCKED);
  const peekShot = evaluate(vec(4, 6), vec(4, 8), map, []);
  assert.notEqual(peekShot.status, LOS_BLOCKED);
});

test("window opening is climb-height cover, not a hard vision wall", () => {
  const map = MapData.empty();
  map.placeObject(vec(5, 6), "coc_swin", "SWIN");
  const tile = map.getTile(vec(5, 6));
  assert.ok(tile);
  assert.equal(tile.height, 1);
  assert.equal(tile.coverType, COVER_MODERATE);
  assert.equal(tile.blocksLos, false);
});

test("no cover / moderate / complete / directional cover", () => {
  const map = MapData.empty();
  const open = evaluateTargetCover(vec(5, 1), vec(5, 5), map);
  assert.equal(open.inCover, false);
  assert.equal(open.coverType, COVER_NONE);

  map.placeObject(vec(5, 4), "haybail", "BG01");
  const hay = evaluateTargetCover(vec(5, 1), vec(5, 5), map);
  assert.equal(hay.inCover, true);
  assert.equal(hay.coverType, COVER_MODERATE);

  const flank = evaluateTargetCover(vec(5, 9), vec(5, 5), map);
  assert.equal(flank.inCover, false);

  map.placeObject(vec(10, 4), "wall_straight", "SWAL");
  const wall = evaluateTargetCover(vec(10, 1), vec(10, 5), map);
  assert.equal(wall.inCover, true);
  assert.equal(wall.coverType, COVER_COMPLETE);
});

test("visible plus cover is still visible", () => {
  const state = emptyState();
  pairFacing(state, vec(5, 1), vec(5, 5));
  state.map.placeObject(vec(5, 4), "haybail", "BG01");
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  const cover = evaluateTargetCover(vec(5, 1), vec(5, 5), state.map);
  assert.equal(cover.inCover, true);
});

test("team visibility aggregates any observer", () => {
  const state = emptyState();
  pairFacing(state);
  const buddy = usa(state, 2);
  buddy.isDead = false;
  buddy.gridPosition = vec(5, 4);
  buddy.facing = vec(0, -1);
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  usa(state).facing = vec(0, -1);
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
  buddy.facing = towardCell(buddy.gridPosition, ger(state).gridPosition);
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
});

test("visibility gained and lost after movement", () => {
  const state = emptyState();
  pairFacing(state, vec(4, 4), vec(4, 10));
  state.map.placeObject(vec(4, 7), "coc_blocker", "");
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
  usa(state).gridPosition = vec(8, 4);
  usa(state).facing = towardCell(vec(8, 4), vec(4, 10));
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  usa(state).gridPosition = vec(4, 4);
  usa(state).facing = towardCell(vec(4, 4), vec(4, 10));
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
});

test("visibility changes after stance on height-1 terrain", () => {
  const state = emptyState();
  pairFacing(state, vec(4, 4), vec(4, 10));
  state.map.placeObject(vec(4, 7), "haybail", "BG01");
  usa(state).positionState = POSITION_UP;
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  usa(state).positionState = POSITION_DOWN;
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
});

test("dead observer and dead target are not spotted", () => {
  const state = emptyState();
  pairFacing(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  usa(state).isDead = true;
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
  usa(state).isDead = false;
  ger(state).isDead = true;
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
});

test("USA and Germany spotting are symmetric", () => {
  const state = emptyState();
  pairFacing(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  assert.equal(state.perception.isVisibleToTeam(TEAM_GERMANY, TEAM_USA, 1), true);
  usa(state).facing = vec(1, 0);
  ger(state).facing = vec(-1, 0);
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), false);
  assert.equal(state.perception.isVisibleToTeam(TEAM_GERMANY, TEAM_USA, 1), false);
});

test("Fire At Will acquires a spotted shootable enemy on combat scan", () => {
  const state = emptyState();
  pairFacing(state, vec(4, 4), vec(4, 5));
  const shooter = usa(state);
  shooter.fireControlState = FIRE_AT_WILL;
  state.perception.rebuildVisibility(state);
  const acquired = findBestAutoTarget(state, shooter);
  assert.ok(acquired);
  assert.equal(acquired.soldierId, 1);
  const result = state.perception.processTick(state, COMBAT_SCAN_TICKS, true);
  assert.equal(shooter.engagedTargetTeamId, TEAM_GERMANY);
  assert.equal(shooter.engagedTargetSoldierId, 1);
  assert.equal(shooter.sustainedFire, false);
  assert.ok(result.targetUpdates.length >= 1);
});

test("manual Fire At rejects an unseen enemy", () => {
  const state = emptyState();
  pairFacing(state);
  usa(state).facing = vec(0, -1);
  ger(state).facing = vec(0, 1);
  usa(state).recordLastSeen(TEAM_GERMANY, 1, -10_000, ger(state).gridPosition);
  state.perception.rebuildVisibility(state);
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-hidden",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.match(result.statusMessage, /No visible target/i);
  assert.equal(usa(state).isEngaged(), false);
});

test("manual Fire At assigns when spotted even if the shot is blocked", () => {
  const state = emptyState();
  pairFacing(state, vec(4, 4), vec(4, 10));
  state.map.placeObject(vec(4, 7), "wall_straight", "SWAL");
  state.perception.rebuildVisibility(state);
  assert.equal(state.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, 1), true);
  assert.equal(evaluate(vec(4, 4), vec(4, 10), state.map, []).status, LOS_BLOCKED);
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-wall",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(usa(state).isEngaged(), true);
  assert.match(result.statusMessage, /holding fire/i);
});

test("target is cleared after visibility is lost past grace", () => {
  const state = emptyState();
  pairFacing(state, vec(4, 4), vec(4, 5));
  const shooter = usa(state);
  executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-lose",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(shooter.isEngaged(), true);
  shooter.facing = vec(0, -1);
  state.perception.rebuildVisibility(state);
  pumpSim(state, 2500);
  pumpSim(state, 2000);
  assert.equal(shooter.isEngaged(), false);
});

function pumpSim(state: GameState, msec: number): void {
  let left = msec;
  while (left > 0) {
    const slice = Math.min(500, left);
    state.clock.consumeRealtime(slice, (tickId) => {
      state.perception.processTick(state, tickId);
    });
    left -= slice;
  }
}

test("snapshot includes per-side visibility without LOS rays", () => {
  const state = emptyState();
  pairFacing(state);
  const snap = state.getSnapshot();
  assert.ok(Array.isArray(snap.visibility));
  const usaSide = snap.visibility.find((side) => side.teamId === TEAM_USA);
  assert.ok(usaSide);
  assert.ok(usaSide.visible.some((v) => v.teamId === TEAM_GERMANY && v.soldierId === 1));
});

test("Hold Fire still does not fire a weapon", () => {
  const state = emptyState();
  pairFacing(state, vec(4, 4), vec(4, 5));
  executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "hf",
      teamId: TEAM_USA,
      soldierId: 1,
      fireControlState: FIRE_HOLD,
    },
    TEAM_USA,
  );
  assert.equal(usa(state).isEngaged(), false);
});

test("canAssignManualPriority uses live spotting", () => {
  const state = emptyState();
  pairFacing(state);
  assert.equal(canAssignManualPriority(usa(state), ger(state), state, ger(state).gridPosition), true);
  usa(state).facing = vec(0, -1);
  usa(state).recordLastSeen(TEAM_GERMANY, 1, -10_000, ger(state).gridPosition);
  assert.equal(canAssignManualPriority(usa(state), ger(state), state, ger(state).gridPosition), false);
});

test("perception dirty rebuild is not required every idle tick", () => {
  const state = emptyState();
  pairFacing(state);
  const system = state.perception;
  system.acknowledge();
  const idle = system.processTick(state, 1, false);
  assert.equal(idle.visibilityChanged, false);
  usa(state).facing = vec(0, -1);
  state.markPerceptionDirty();
  const changed = system.processTick(state, 2, false);
  assert.equal(changed.visibilityChanged, true);
});
