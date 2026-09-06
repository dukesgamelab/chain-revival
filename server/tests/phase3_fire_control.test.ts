import assert from "node:assert/strict";
import { test } from "node:test";
import {
  executeFireAt,
  executeFireControl,
  toFireAtResultPayload,
  toFireControlResultPayload,
} from "../src/action_resolver";
import { GameState } from "../src/game_state";
import { MapData } from "../src/map_data";
import {
  FIRE_AT_WILL,
  FIRE_HOLD,
  MATCH_ID,
  MOVE_SCOPE_SINGLE,
  MOVE_SCOPE_SQUAD,
  TEAM_GERMANY,
  TEAM_USA,
} from "../src/types";

function makeState(): GameState {
  return new GameState(MapData.loadFromRepo("ff_farm"));
}

function usa(state: GameState, id = 1) {
  const soldier = state.getSoldier(TEAM_USA, id);
  assert.ok(soldier);
  return soldier;
}

function ger(state: GameState, id = 1) {
  const soldier = state.getSoldier(TEAM_GERMANY, id);
  assert.ok(soldier);
  return soldier;
}

test("Hold Fire sets fireControlState and clears a priority target", () => {
  const state = makeState();
  const soldier = usa(state);
  soldier.fireControlState = FIRE_AT_WILL;
  soldier.beginSustainedFire();
  soldier.setEngagedTarget(TEAM_GERMANY, 1);
  const result = executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "hf1",
      teamId: TEAM_USA,
      soldierId: 1,
      fireControlState: FIRE_HOLD,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(soldier.fireControlState, FIRE_HOLD);
  assert.equal(soldier.sustainedFire, false);
  assert.equal(soldier.isEngaged(), false);
  assert.equal(result.syncFireAtUi, true);
});

test("Fire At Will sets fireControlState without inventing a target", () => {
  const state = makeState();
  const soldier = usa(state);
  soldier.fireControlState = FIRE_HOLD;
  const result = executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "faw1",
      teamId: TEAM_USA,
      soldierId: 1,
      fireControlState: FIRE_AT_WILL,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(soldier.fireControlState, FIRE_AT_WILL);
  assert.equal(soldier.isEngaged(), false);
});

test("wrong-side fire control is rejected", () => {
  const state = makeState();
  const soldier = ger(state);
  const result = executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "hf-bad",
      teamId: TEAM_GERMANY,
      soldierId: 1,
      fireControlState: FIRE_HOLD,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.equal(soldier.fireControlState, FIRE_AT_WILL);
});

test("dead soldier cannot change fire control", () => {
  const state = makeState();
  usa(state).isDead = true;
  const result = executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "hf-dead",
      teamId: TEAM_USA,
      soldierId: 1,
      fireControlState: FIRE_HOLD,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
});

test("manual Fire At assigns a priority/sustained target", () => {
  const state = makeState();
  const shooter = usa(state);
  const target = ger(state);
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa1",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: target.teamId,
      targetSoldierId: target.soldierId,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(shooter.fireControlState, FIRE_AT_WILL);
  assert.equal(shooter.sustainedFire, true);
  assert.equal(shooter.engagedTargetTeamId, TEAM_GERMANY);
  assert.equal(shooter.engagedTargetSoldierId, target.soldierId);
});

test("manual Fire At rejects a friendly target", () => {
  const state = makeState();
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-friend",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_USA,
      targetSoldierId: 2,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.equal(usa(state).isEngaged(), false);
});

test("manual Fire At rejects a dead target", () => {
  const state = makeState();
  ger(state).isDead = true;
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-dead",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
});

test("manual Fire At replaces the previous priority target", () => {
  const state = makeState();
  const shooter = usa(state);
  executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-a",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  const second = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-b",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 2,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(second.success, true);
  assert.equal(shooter.engagedTargetSoldierId, 2);
  assert.equal(shooter.sustainedFire, true);
});

test("Hold Fire after Fire At clears the priority target", () => {
  const state = makeState();
  executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-then-hf",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "hf-after",
      teamId: TEAM_USA,
      soldierId: 1,
      fireControlState: FIRE_HOLD,
    },
    TEAM_USA,
  );
  const soldier = usa(state);
  assert.equal(soldier.fireControlState, FIRE_HOLD);
  assert.equal(soldier.sustainedFire, false);
  assert.equal(soldier.isEngaged(), false);
});

test("manual Fire At is allowed while Hold Fire is set and switches to Fire At Will", () => {
  const state = makeState();
  const soldier = usa(state);
  soldier.fireControlState = FIRE_HOLD;
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-from-hf",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(soldier.fireControlState, FIRE_AT_WILL);
  assert.equal(soldier.sustainedFire, true);
});

test("squad Fire At assigns every living shooter on the acting side", () => {
  const state = makeState();
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-squad",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SQUAD,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  for (const soldier of state.soldiersOnTeam(TEAM_USA)) {
    if (soldier.isDead) {
      continue;
    }
    assert.equal(soldier.engagedTargetSoldierId, 1);
    assert.equal(soldier.sustainedFire, true);
  }
});

test("wrong-side Fire At is rejected", () => {
  const state = makeState();
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-side",
      teamId: TEAM_GERMANY,
      soldierId: 1,
      targetTeamId: TEAM_USA,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.equal(ger(state).isEngaged(), false);
});

test("Fire At without an explicit target is blocked until LOS is ported", () => {
  const state = makeState();
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-los",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: -1,
      targetSoldierId: -1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.match(result.statusMessage, /LOS|spotting/i);
});

test("stunned shooter cannot Fire At", () => {
  const state = makeState();
  usa(state).stunnedUntilMsec = state.clock.getTicksMsec() + 4000;
  const result = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "fa-stun",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
});

test("snapshot serializes fire-control and priority target", () => {
  const state = makeState();
  const soldier = usa(state);
  soldier.fireControlState = FIRE_HOLD;
  soldier.beginSustainedFire();
  soldier.setEngagedTarget(TEAM_GERMANY, 3);
  const entry = state.getSnapshot().soldiers.find((s) => s.teamId === TEAM_USA && s.soldierId === 1);
  assert.ok(entry);
  assert.equal(entry.fireControlState, FIRE_HOLD);
  assert.equal(entry.engagedTargetTeamId, TEAM_GERMANY);
  assert.equal(entry.engagedTargetSoldierId, 3);
  assert.equal(entry.sustainedFire, true);
});

test("both clients stay identical when applying fire-control and Fire At payloads", () => {
  const state = makeState();
  const hold = executeFireControl(
    state,
    {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: "both-hf",
      teamId: TEAM_USA,
      soldierId: 1,
      fireControlState: FIRE_HOLD,
    },
    TEAM_USA,
  );
  const holdPayload = toFireControlResultPayload(MATCH_ID, "both-hf", hold);
  assert.equal(holdPayload.targetUpdates[0].fireControlState, usa(state).fireControlState);

  const fire = executeFireAt(
    state,
    {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: "both-fa",
      teamId: TEAM_USA,
      soldierId: 1,
      targetTeamId: TEAM_GERMANY,
      targetSoldierId: 1,
      scope: MOVE_SCOPE_SINGLE,
    },
    TEAM_USA,
  );
  const firePayload = toFireAtResultPayload(MATCH_ID, "both-fa", fire);
  assert.equal(firePayload.targetUpdates[0].engagedTargetSoldierId, usa(state).engagedTargetSoldierId);
  assert.equal(firePayload.targetUpdates[0].sustainedFire, true);
});

test("automatic Fire At Will acquisition is not performed without authoritative LOS", () => {
  const state = makeState();
  const soldier = usa(state);
  soldier.fireControlState = FIRE_AT_WILL;
  assert.equal(soldier.isEngaged(), false);
  assert.equal(
    soldier.engagedTargetSoldierId,
    -1,
    "LOS/spotting is required before the server may auto-acquire; do not invent nearest-enemy.",
  );
});
