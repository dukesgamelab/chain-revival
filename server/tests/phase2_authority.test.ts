import assert from "node:assert/strict";
import { test } from "node:test";
import {
  executeFace,
  executeMove,
  executePosition,
  toFaceResultPayload,
  toMoveResultPayload,
  toPositionResultPayload,
} from "../src/action_resolver";
import { towardCell, towardWorldPoint } from "../src/facing";
import { GameState } from "../src/game_state";
import { MapData } from "../src/map_data";
import {
  MATCH_ID,
  MOVEMENT_CRAWL,
  MOVEMENT_RUN,
  MOVEMENT_WALK,
  MOVE_SCOPE_SINGLE,
  MOVE_SCOPE_SQUAD,
  POSITION_DOWN,
  POSITION_UP,
  TEAM_GERMANY,
  TEAM_USA,
  vec,
  vecEq,
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

function walkableNeighbor(state: GameState, from: { x: number; y: number }) {
  const offsets = [
    vec(1, 0),
    vec(-1, 0),
    vec(0, 1),
    vec(0, -1),
    vec(1, 1),
    vec(-1, -1),
  ];
  for (const offset of offsets) {
    const cell = vec(from.x + offset.x, from.y + offset.y);
    if (state.map.isWalkable(cell)) {
      return cell;
    }
  }
  throw new Error("No walkable neighbor");
}

test("single facing updates only the ordered soldier", () => {
  const state = makeState();
  const soldier = usa(state);
  const target = vec(soldier.gridPosition.x + 1, soldier.gridPosition.y);
  const beforeOthers = ger(state).facing;
  const result = executeFace(
    state,
    {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: "f1",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: target,
      scope: MOVE_SCOPE_SINGLE,
      aimWorld: null,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(result.faceUpdates.length, 1);
  assert.deepEqual(soldier.facing, towardCell(soldier.gridPosition, target));
  assert.deepEqual(ger(state).facing, beforeOthers);
});

test("squad facing reorients every living soldier on the acting side", () => {
  const state = makeState();
  const lead = usa(state);
  const target = vec(lead.gridPosition.x + 2, lead.gridPosition.y + 1);
  const result = executeFace(
    state,
    {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: "f2",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: target,
      scope: MOVE_SCOPE_SQUAD,
      aimWorld: null,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.ok(result.faceUpdates.length >= 2);
  for (const soldier of state.soldiersOnTeam(TEAM_USA)) {
    assert.deepEqual(soldier.facing, towardCell(soldier.gridPosition, target));
  }
});

test("wrong-side facing is rejected", () => {
  const state = makeState();
  const german = ger(state);
  const original = { ...german.facing };
  const result = executeFace(
    state,
    {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: "f3",
      teamId: TEAM_GERMANY,
      soldierId: 1,
      targetCell: vec(german.gridPosition.x + 1, german.gridPosition.y),
      scope: MOVE_SCOPE_SINGLE,
      aimWorld: null,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.deepEqual(german.facing, original);
});

test("dead and stunned soldiers cannot face", () => {
  const state = makeState();
  const dead = usa(state, 1);
  dead.isDead = true;
  const deadResult = executeFace(
    state,
    {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: "f4",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: vec(dead.gridPosition.x + 1, dead.gridPosition.y),
      scope: MOVE_SCOPE_SINGLE,
      aimWorld: null,
    },
    TEAM_USA,
  );
  assert.equal(deadResult.success, false);

  const stunned = usa(state, 2);
  stunned.stunnedUntilMsec = state.clock.getTicksMsec() + 5000;
  const stunnedResult = executeFace(
    state,
    {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: "f5",
      teamId: TEAM_USA,
      soldierId: 2,
      targetCell: vec(stunned.gridPosition.x + 1, stunned.gridPosition.y),
      scope: MOVE_SCOPE_SINGLE,
      aimWorld: null,
    },
    TEAM_USA,
  );
  assert.equal(stunnedResult.success, false);
});

test("UP to DOWN and DOWN to UP", () => {
  const state = makeState();
  const soldier = usa(state);
  const down = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "p1",
      teamId: TEAM_USA,
      soldierId: 1,
      positionState: POSITION_DOWN,
    },
    TEAM_USA,
  );
  assert.equal(down.success, true);
  assert.equal(soldier.positionState, POSITION_DOWN);
  assert.equal(down.stanceTransitionOrders.length, 1);

  soldier.clearPendingPosition();
  const up = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "p2",
      teamId: TEAM_USA,
      soldierId: 1,
      positionState: POSITION_UP,
    },
    TEAM_USA,
  );
  assert.equal(up.success, true);
  assert.equal(soldier.positionState, POSITION_UP);
});

test("wrong-side stance is rejected", () => {
  const state = makeState();
  const soldier = ger(state);
  const result = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "p3",
      teamId: TEAM_GERMANY,
      soldierId: 1,
      positionState: POSITION_DOWN,
    },
    TEAM_USA,
  );
  assert.equal(result.success, false);
  assert.equal(soldier.positionState, POSITION_UP);
});

test("dead and stunned soldiers cannot change stance", () => {
  const state = makeState();
  usa(state, 1).isDead = true;
  assert.equal(
    executePosition(
      state,
      {
        type: "position_command",
        matchId: MATCH_ID,
        requestId: "p4",
        teamId: TEAM_USA,
        soldierId: 1,
        positionState: POSITION_DOWN,
      },
      TEAM_USA,
    ).success,
    false,
  );
  usa(state, 2).stunnedUntilMsec = state.clock.getTicksMsec() + 4000;
  assert.equal(
    executePosition(
      state,
      {
        type: "position_command",
        matchId: MATCH_ID,
        requestId: "p5",
        teamId: TEAM_USA,
        soldierId: 2,
        positionState: POSITION_DOWN,
      },
      TEAM_USA,
    ).success,
    false,
  );
});

test("stance while moving halts at the authoritative cell", () => {
  const state = makeState();
  const soldier = usa(state);
  const dest = walkableNeighbor(state, soldier.gridPosition);
  const move = executeMove(
    state,
    {
      type: "move_command",
      matchId: MATCH_ID,
      requestId: "m1",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: dest,
      scope: MOVE_SCOPE_SINGLE,
      movementMode: MOVEMENT_RUN,
    },
    TEAM_USA,
  );
  assert.equal(move.success, true);
  assert.equal(soldier.isMoving, true);
  const cell = { ...soldier.gridPosition };
  const prone = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "p6",
      teamId: TEAM_USA,
      soldierId: 1,
      positionState: POSITION_DOWN,
    },
    TEAM_USA,
  );
  assert.equal(prone.success, true);
  assert.equal(soldier.isMoving, false);
  assert.deepEqual(soldier.gridPosition, cell);
  assert.equal(soldier.positionState, POSITION_DOWN);
  assert.equal(prone.movementHalts.length, 1);
});

test("RUN WALK CRAWL commit authoritative movementMode", () => {
  const modes = [
    [MOVEMENT_RUN, "run"],
    [MOVEMENT_WALK, "walk"],
    [MOVEMENT_CRAWL, "crawl"],
  ] as const;
  for (const [mode] of modes) {
    const state = makeState();
    const soldier = usa(state);
    if (mode === MOVEMENT_CRAWL) {
      soldier.positionState = POSITION_DOWN;
    }
    const dest = walkableNeighbor(state, soldier.gridPosition);
    const result = executeMove(
      state,
      {
        type: "move_command",
        matchId: MATCH_ID,
        requestId: `mode-${mode}`,
        teamId: TEAM_USA,
        soldierId: 1,
        targetCell: dest,
        scope: MOVE_SCOPE_SINGLE,
        movementMode: mode,
      },
      TEAM_USA,
    );
    assert.equal(result.success, true, `mode ${mode}`);
    assert.equal(soldier.movementMode, mode);
    assert.equal(result.moveOrders[0].movementMode, mode);
  }
});

test("standing + CRAWL goes prone", () => {
  const state = makeState();
  const soldier = usa(state);
  assert.equal(soldier.positionState, POSITION_UP);
  const dest = walkableNeighbor(state, soldier.gridPosition);
  const result = executeMove(
    state,
    {
      type: "move_command",
      matchId: MATCH_ID,
      requestId: "stand-crawl",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: dest,
      scope: MOVE_SCOPE_SINGLE,
      movementMode: MOVEMENT_CRAWL,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
  assert.equal(soldier.positionState, POSITION_DOWN);
  assert.equal(soldier.movementMode, MOVEMENT_CRAWL);
});

test("prone + RUN/WALK stand; prone + CRAWL stays down", () => {
  for (const mode of [MOVEMENT_RUN, MOVEMENT_WALK, MOVEMENT_CRAWL]) {
    const state = makeState();
    const soldier = usa(state);
    soldier.positionState = POSITION_DOWN;
    const dest = walkableNeighbor(state, soldier.gridPosition);
    const result = executeMove(
      state,
      {
        type: "move_command",
        matchId: MATCH_ID,
        requestId: `prone-${mode}`,
        teamId: TEAM_USA,
        soldierId: 1,
        targetCell: dest,
        scope: MOVE_SCOPE_SINGLE,
        movementMode: mode,
      },
      TEAM_USA,
    );
    assert.equal(result.success, true);
    if (mode === MOVEMENT_CRAWL) {
      assert.equal(soldier.positionState, POSITION_DOWN);
    } else {
      assert.equal(soldier.positionState, POSITION_UP);
    }
    assert.equal(soldier.movementMode, mode);
  }
});

test("snapshot serializes facing, stance, and movementMode", () => {
  const state = makeState();
  const soldier = usa(state);
  soldier.facing = vec(1, 0);
  soldier.positionState = POSITION_DOWN;
  soldier.movementMode = MOVEMENT_CRAWL;
  const snap = state.getSnapshot();
  const entry = snap.soldiers.find((s) => s.teamId === TEAM_USA && s.soldierId === 1);
  assert.ok(entry);
  assert.deepEqual(entry.facing, vec(1, 0));
  assert.equal(entry.positionState, POSITION_DOWN);
  assert.equal(entry.movementMode, MOVEMENT_CRAWL);
});

test("both clients stay identical when applying the same result payloads", () => {
  const state = makeState();
  const soldier = usa(state);
  const target = vec(soldier.gridPosition.x + 1, soldier.gridPosition.y);
  const face = executeFace(
    state,
    {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: "both-f",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: target,
      scope: MOVE_SCOPE_SINGLE,
      aimWorld: null,
    },
    TEAM_USA,
  );
  const facePayload = toFaceResultPayload(MATCH_ID, "both-f", face);
  const replicaA = { ...soldier.facing };
  const replicaB = { ...facePayload.faceUpdates[0].facing };
  assert.deepEqual(replicaA, replicaB);

  soldier.clearPendingPosition();
  const pos = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "both-p",
      teamId: TEAM_USA,
      soldierId: 1,
      positionState: POSITION_DOWN,
    },
    TEAM_USA,
  );
  const posPayload = toPositionResultPayload(MATCH_ID, "both-p", pos);
  assert.equal(posPayload.soldierUpdates[0].positionState, soldier.positionState);

  const dest = walkableNeighbor(state, soldier.gridPosition);
  const move = executeMove(
    state,
    {
      type: "move_command",
      matchId: MATCH_ID,
      requestId: "both-m",
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: dest,
      scope: MOVE_SCOPE_SINGLE,
      movementMode: MOVEMENT_RUN,
    },
    TEAM_USA,
  );
  const movePayload = toMoveResultPayload(MATCH_ID, "both-m", move);
  assert.equal(movePayload.moveOrders[0].movementMode, soldier.movementMode);
  assert.equal(movePayload.moveOrders[0].positionState, soldier.positionState);
  assert.equal(soldier.positionState, POSITION_UP);
});

test("stance command is rejected while a pending transition gate is active", () => {
  const state = makeState();
  const first = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "gate-1",
      teamId: TEAM_USA,
      soldierId: 1,
      positionState: POSITION_DOWN,
    },
    TEAM_USA,
  );
  assert.equal(first.success, true);
  const second = executePosition(
    state,
    {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: "gate-2",
      teamId: TEAM_USA,
      soldierId: 1,
      positionState: POSITION_UP,
    },
    TEAM_USA,
  );
  assert.equal(second.success, false);
  assert.equal(usa(state).positionState, POSITION_DOWN);
});

test("toward_world_point matches cell facing when the cells differ", () => {
  const from = vec(4, 4);
  const to = vec(5, 3);
  assert.deepEqual(towardWorldPoint(from, to, null), towardCell(from, to));
  assert.ok(vecEq(towardWorldPoint(from, from, null), vec(0, 0)));
});
