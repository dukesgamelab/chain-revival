import assert from "node:assert/strict";
import { test } from "node:test";
import type { WebSocket } from "ws";
import { executeMove, processMovementTick } from "../src/action_resolver";
import { LocalMatch } from "../src/match";
import { SimTimers } from "../src/sim_timers";
import { SimulationClock } from "../src/simulation_clock";
import { GameState } from "../src/game_state";
import { MapData } from "../src/map_data";
import {
  MATCH_ID,
  MOVEMENT_CRAWL,
  MOVEMENT_RUN,
  MOVEMENT_WALK,
  MOVE_SCOPE_SINGLE,
  POSITION_DOWN,
  TEAM_USA,
  vec,
} from "../src/types";

function makeClock(): SimulationClock {
  return new SimulationClock();
}

function makeMatch(): LocalMatch {
  return new LocalMatch("ff_farm", { startDriver: false });
}

function fakeWs(): WebSocket & { sent: unknown[] } {
  const sent: unknown[] = [];
  const ws = {
    sent,
    readyState: 1,
    OPEN: 1,
    send(text: string) {
      sent.push(JSON.parse(text) as unknown);
    },
  };
  return ws as unknown as WebSocket & { sent: unknown[] };
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

function issueRun(match: LocalMatch, mode = MOVEMENT_RUN): void {
  const soldier = match.gameState.getSoldier(TEAM_USA, 1);
  assert.ok(soldier);
  if (mode === MOVEMENT_CRAWL) {
    soldier.positionState = POSITION_DOWN;
  }
  const dest = walkableNeighbor(match.gameState, soldier.gridPosition);
  const result = executeMove(
    match.gameState,
    {
      type: "move_command",
      matchId: MATCH_ID,
      requestId: `clk-${mode}`,
      teamId: TEAM_USA,
      soldierId: 1,
      targetCell: dest,
      scope: MOVE_SCOPE_SINGLE,
      movementMode: mode,
    },
    TEAM_USA,
  );
  assert.equal(result.success, true);
}

test("SimulationClock advances fixed 50ms steps at 20 Hz", () => {
  const clock = makeClock();
  assert.equal(clock.tickHz, 20);
  assert.equal(clock.tickMsec(), 50);
  assert.equal(clock.advanceTick(), 50);
  assert.equal(clock.getTicksMsec(), 50);
});

test("tick IDs increase monotonically", () => {
  const clock = makeClock();
  const ids: number[] = [];
  for (let i = 0; i < 8; i += 1) {
    clock.advanceTick();
    ids.push(clock.getTickId());
  }
  assert.deepEqual(ids, [1, 2, 3, 4, 5, 6, 7, 8]);
});

test("simulation time advances by the fixed timestep", () => {
  const clock = makeClock();
  clock.advanceTick();
  clock.advanceTick();
  clock.advanceTick();
  assert.equal(clock.getTicksMsec(), 150);
  assert.equal(clock.getTickId(), 3);
});

test("variable real-time intervals produce the same fixed steps", () => {
  const a = makeClock();
  const b = makeClock();
  a.consumeRealtime(20);
  a.consumeRealtime(30);
  a.consumeRealtime(50);
  b.consumeRealtime(100);
  assert.equal(a.getTickId(), b.getTickId());
  assert.equal(a.getTicksMsec(), b.getTicksMsec());
  assert.equal(a.getTickId(), 2);
  assert.equal(a.getTicksMsec(), 100);
});

test("pause and stop prevent simulation advancement", () => {
  const clock = makeClock();
  clock.advanceTick();
  clock.pause();
  assert.equal(clock.consumeRealtime(500).steps, 0);
  assert.equal(clock.advanceTick(), 0);
  assert.equal(clock.getTickId(), 1);
  clock.resume();
  assert.equal(clock.consumeRealtime(50).steps, 1);
  clock.stop();
  assert.equal(clock.consumeRealtime(500).steps, 0);
  assert.equal(clock.getTickId(), 2);
});

test("match end stops authoritative gameplay advancement", () => {
  const match = makeMatch();
  match.advanceRealtime(100);
  const tickAfter = match.clock.getTickId();
  const msecAfter = match.clock.getTicksMsec();
  match.endMatch();
  assert.equal(match.matchPhase, "ended");
  const pump = match.advanceRealtime(1000);
  assert.equal(pump.steps, 0);
  assert.equal(match.clock.getTickId(), tickAfter);
  assert.equal(match.clock.getTicksMsec(), msecAfter);
});

test("two connected clients share one match clock", () => {
  const match = makeMatch();
  const usa = fakeWs();
  const ger = fakeWs();
  match.attachClient("usa", usa);
  match.attachClient("ger", ger);
  assert.equal(match.clientCount, 2);
  match.advanceRealtime(150);
  const snapUsa = match.gameState.getSnapshot(match.matchPhase);
  match.sendSnapshot(usa);
  match.sendSnapshot(ger);
  const lastUsa = usa.sent[usa.sent.length - 1] as { tickId: number; simMsec: number };
  const lastGer = ger.sent[ger.sent.length - 1] as { tickId: number; simMsec: number };
  assert.equal(lastUsa.tickId, lastGer.tickId);
  assert.equal(lastUsa.simMsec, lastGer.simMsec);
  assert.equal(lastUsa.tickId, snapUsa.tickId);
  assert.equal(match.clock.getTickId(), 3);
});

test("client connect/disconnect does not reset simulation time", () => {
  const match = makeMatch();
  const ws = fakeWs();
  match.attachClient("a", ws);
  match.advanceRealtime(200);
  const tick = match.clock.getTickId();
  const msec = match.clock.getTicksMsec();
  match.removeClient("a");
  match.advanceRealtime(100);
  match.attachClient("b", fakeWs());
  assert.equal(match.clock.getTickId(), tick + 2);
  assert.equal(match.clock.getTicksMsec(), msec + 100);
  assert.ok(match.clock.getTickId() > tick);
});

test("movement advances through the centralized SimulationClock", () => {
  const match = makeMatch();
  issueRun(match, MOVEMENT_RUN);
  const soldier = match.gameState.getSoldier(TEAM_USA, 1);
  assert.ok(soldier?.isMoving);
  const start = { ...soldier.gridPosition };
  let stepped = false;
  for (let i = 0; i < 40; i += 1) {
    match.advanceRealtime(50);
    if (!vecEqish(soldier.gridPosition, start)) {
      stepped = true;
      break;
    }
  }
  assert.equal(stepped, true);
  assert.ok(match.movementTickSends >= 1);
});

function vecEqish(a: { x: number; y: number }, b: { x: number; y: number }): boolean {
  return a.x === b.x && a.y === b.y;
}

test("RUN is faster than WALK is faster than CRAWL on the same clock", () => {
  function ticksUntilFirstStep(mode: number): number {
    const match = makeMatch();
    issueRun(match, mode);
    const soldier = match.gameState.getSoldier(TEAM_USA, 1);
    assert.ok(soldier);
    const start = { ...soldier.gridPosition };
    for (let i = 0; i < 200; i += 1) {
      match.advanceRealtime(50);
      if (!vecEqish(soldier.gridPosition, start)) {
        return i + 1;
      }
    }
    return 999;
  }
  const run = ticksUntilFirstStep(MOVEMENT_RUN);
  const walk = ticksUntilFirstStep(MOVEMENT_WALK);
  const crawl = ticksUntilFirstStep(MOVEMENT_CRAWL);
  assert.ok(run < walk, `run=${run} walk=${walk}`);
  assert.ok(walk < crawl, `walk=${walk} crawl=${crawl}`);
});

test("server stall catch-up respects the configured cap", () => {
  const clock = makeClock();
  const pump = clock.consumeRealtime(5000);
  assert.equal(pump.steps, clock.maxCatchupTicks);
  assert.equal(pump.capped, true);
  assert.ok(pump.discardedMsec >= 50);
  assert.equal(clock.getTickId(), 10);
  assert.equal(clock.getTicksMsec(), 500);
});

test("initial snapshot includes simulation timing metadata", () => {
  const match = makeMatch();
  match.advanceRealtime(150);
  const snap = match.gameState.getSnapshot(match.matchPhase);
  assert.equal(snap.type, "match_snapshot");
  assert.equal(snap.matchId, MATCH_ID);
  assert.equal(snap.tickId, 3);
  assert.equal(snap.simMsec, 150);
  assert.equal(snap.simRunning, true);
  assert.equal(snap.matchPhase, "running");
});

test("idle ticks do not broadcast a full GameState", () => {
  const match = makeMatch();
  const ws = fakeWs();
  match.attachClient("c1", ws);
  match.advanceRealtime(250);
  assert.equal(match.snapshotSends, 0);
  const types = ws.sent.map((m) => (m as { type?: string }).type);
  assert.equal(types.includes("match_snapshot"), false);
  match.sendSnapshot(ws);
  assert.equal(match.snapshotSends, 1);
});

test("sim timers fire from simulation time, not wall-clock", () => {
  const clock = makeClock();
  const timers = new SimTimers();
  const fired: string[] = [];
  timers.scheduleAfter("cooldown", 120, clock, (id) => {
    fired.push(id);
  });
  clock.consumeRealtime(100);
  assert.deepEqual(timers.pollDue(clock), []);
  assert.deepEqual(fired, []);
  clock.consumeRealtime(50);
  assert.deepEqual(timers.pollDue(clock), ["cooldown"]);
  assert.deepEqual(fired, ["cooldown"]);
});

test("paused match clock does not advance movement", () => {
  const match = makeMatch();
  issueRun(match, MOVEMENT_RUN);
  const soldier = match.gameState.getSoldier(TEAM_USA, 1);
  assert.ok(soldier);
  const cell = { ...soldier.gridPosition };
  match.pauseSimulation();
  for (let i = 0; i < 20; i += 1) {
    match.advanceRealtime(50);
  }
  assert.deepEqual(soldier.gridPosition, cell);
  assert.equal(soldier.isMoving, true);
  match.resumeSimulation();
  let moved = false;
  for (let i = 0; i < 40; i += 1) {
    match.advanceRealtime(50);
    if (!vecEqish(soldier.gridPosition, cell) || !soldier.isMoving) {
      moved = true;
      break;
    }
  }
  assert.equal(moved, true);
});

test("direct processMovementTick still uses the match clock step size", () => {
  const state = new GameState(MapData.loadFromRepo("ff_farm"));
  assert.equal(state.clock.tickMsec(), 50);
  const tick = processMovementTick(state);
  assert.equal(tick.movementSteps.length, 0);
});
