// Sim-parity Step 3 drift fixes that need the full server flow, not a pure-rule fixture.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { WebSocket } from "ws";
import { beginFirePrep, resolveShot } from "../src/combat_system";
import { GameState } from "../src/game_state";
import { DEPLOYMENT_FIRE_LOCKED_MSG, DEPLOYMENT_GRENADE_LOCKED_MSG, LocalMatch } from "../src/match";
import { MapData } from "../src/map_data";
import { MATCH_ID, MOVE_SCOPE_SINGLE, TEAM_GERMANY, TEAM_USA, vec } from "../src/types";

type Msg = Record<string, unknown> & { type: string };

function fakeWs(): WebSocket & { sent: Msg[] } {
  const sent: Msg[] = [];
  const ws = { sent, readyState: 1, OPEN: 1, send: (text: string) => sent.push(JSON.parse(text) as Msg) };
  return ws as unknown as WebSocket & { sent: Msg[] };
}

function usaClient(deploying: boolean) {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  const ws = fakeWs();
  match.attachClient("usa", ws);
  match.setClientTeam("usa", TEAM_USA);
  (match as unknown as { deploymentRemainingSec: number }).deploymentRemainingSec = deploying ? 10 : 0;
  return { match, ws };
}

const grenadeIntent = (requestId: string) => ({
  type: "grenade_command" as const,
  matchId: MATCH_ID,
  requestId,
  teamId: TEAM_USA,
  soldierId: 1,
  targetCell: vec(0, 0),
});

function advanceSim(state: GameState, msec: number): void {
  let left = msec;
  while (left > 0) {
    const slice = Math.min(500, left);
    state.clock.consumeRealtime(slice, () => {});
    left -= slice;
  }
}

function duel(map: MapData, shooterCell = vec(15, 5), targetCell = vec(15, 11)) {
  const state = new GameState(map);
  for (const s of state.soldiers) {
    s.isDead = !(s.soldierId === 1);
  }
  const shooter = state.getSoldier(TEAM_USA, 1)!;
  const target = state.getSoldier(TEAM_GERMANY, 1)!;
  shooter.gridPosition = shooterCell;
  shooter.facing = vec(0, 1);
  target.gridPosition = targetCell;
  target.facing = vec(0, 1);
  target.stress = 0;
  return { state, shooter, target };
}

test("no shot and no suppression through the wall a target is hugging", () => {
  const map = MapData.empty(30, 30);
  for (let x = 10; x <= 20; x++) map.placeObject(vec(x, 10), "wall_straight");
  const { state, shooter, target } = duel(map);
  state.rng.forceChance = true;
  beginFirePrep(state, shooter, 6);
  advanceSim(state, 5000);
  const shot = resolveShot(state, shooter, target, true);
  assert.equal(shot.blocked, true);
  assert.equal(shot.fired, false);
  // Same value as the suppression_wall_hugging_target parity fixture (GDScript reference).
  assert.equal(target.stress, 0);
});

test("grenades are refused during deployment, as grenade_thrown to the issuer only", () => {
  const { match, ws } = usaClient(true);
  const grenadesBefore = match.gameState.getSoldier(TEAM_USA, 1)!.grenadeCount;
  match.handleGrenade("usa", grenadeIntent("g1"));
  const reply = ws.sent.find((m) => m.requestId === "g1");
  assert.ok(reply);
  assert.equal(reply.type, "grenade_thrown");
  assert.equal(reply.success, false);
  assert.equal(reply.statusMessage, DEPLOYMENT_GRENADE_LOCKED_MSG);
  assert.equal(match.gameState.getSoldier(TEAM_USA, 1)!.grenadeCount, grenadesBefore);
});

test("Fire At is refused during deployment", () => {
  const { match, ws } = usaClient(true);
  match.handleFireAt("usa", {
    type: "fire_at_command",
    matchId: MATCH_ID,
    requestId: "f1",
    teamId: TEAM_USA,
    soldierId: 1,
    targetTeamId: TEAM_GERMANY,
    targetSoldierId: 1,
    scope: MOVE_SCOPE_SINGLE,
  });
  const reply = ws.sent.find((m) => m.requestId === "f1");
  assert.ok(reply);
  assert.equal(reply.type, "fire_at_result");
  assert.equal(reply.success, false);
  assert.equal(reply.statusMessage, DEPLOYMENT_FIRE_LOCKED_MSG);
  assert.equal(match.gameState.getSoldier(TEAM_USA, 1)!.isEngaged(), false);
});

test("forfeit after the reconnect window still reports the player who dropped", () => {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  match.attachClient("usa", fakeWs());
  match.setClientTeam("usa", TEAM_USA);
  match.attachClient("ger", fakeWs());
  match.setClientTeam("ger", TEAM_GERMANY);
  let reported: Map<string, number | null> | null = null;
  match.onMatchEnded = (info) => {
    reported = info.clientTeams;
  };
  match.holdClientTeam("ger");
  match.forceEndMatchForfeit(TEAM_GERMANY);
  assert.ok(reported);
  const teams = reported as Map<string, number | null>;
  assert.equal(teams.get("usa"), TEAM_USA);
  assert.equal(teams.get("ger"), TEAM_GERMANY);
});

test("a held player who reconnects is reported once, under the new connection", () => {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  match.attachClient("usa", fakeWs());
  match.setClientTeam("usa", TEAM_USA);
  match.attachClient("ger-old", fakeWs());
  match.setClientTeam("ger-old", TEAM_GERMANY);
  match.holdClientTeam("ger-old");
  match.removeClient("ger-old");
  match.attachClient("ger-new", fakeWs());
  match.setClientTeam("ger-new", TEAM_GERMANY);
  let reported: Map<string, number | null> | null = null;
  match.onMatchEnded = (info) => {
    reported = info.clientTeams;
  };
  match.forceEndMatchForfeit(TEAM_USA);
  const teams = reported as unknown as Map<string, number | null>;
  assert.equal(teams.has("ger-old"), false);
  assert.equal(teams.get("ger-new"), TEAM_GERMANY);
});

test("failed grenade throws reply with grenade_thrown, never grenade_result", () => {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  const ws = fakeWs();
  match.attachClient("spectator", ws);
  match.handleGrenade("spectator", grenadeIntent("g2"));
  const reply = ws.sent.find((m) => m.requestId === "g2");
  assert.ok(reply);
  assert.equal(reply.type, "grenade_thrown");
  assert.equal(reply.success, false);
});
