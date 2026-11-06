import assert from "node:assert/strict";
import { test } from "node:test";
import type { WebSocket } from "ws";
import { LocalMatch } from "../src/match";
import { POSITION_DOWN, POSITION_UP, TEAM_GERMANY, TEAM_USA } from "../src/types";

type Msg = Record<string, unknown> & { type: string };
type SyncEntry = Record<string, unknown> & { teamId: number; soldierId: number };

function fakeWs(): WebSocket & { sent: Msg[] } {
  const sent: Msg[] = [];
  const ws = {
    sent,
    readyState: 1,
    OPEN: 1,
    send(text: string) {
      sent.push(JSON.parse(text) as Msg);
    },
  };
  return ws as unknown as WebSocket & { sent: Msg[] };
}

function makeMatch(): { match: LocalMatch; ws: WebSocket & { sent: Msg[] } } {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  const ws = fakeWs();
  match.attachClient("usa", ws);
  // Fog of war: a client only hears about its own team (and enemies it can see).
  match.setClientTeam("usa", TEAM_USA);
  return { match, ws };
}

function lastSync(ws: { sent: Msg[] }): SyncEntry[] {
  const syncs = ws.sent.filter((m) => m.type === "soldier_sync");
  assert.ok(syncs.length > 0, "expected at least one soldier_sync");
  return syncs[syncs.length - 1].soldiers as SyncEntry[];
}

function entryFor(entries: SyncEntry[], teamId: number, soldierId: number): SyncEntry {
  const entry = entries.find((e) => e.teamId === teamId && e.soldierId === soldierId);
  assert.ok(entry, `no sync entry for ${teamId}:${soldierId}`);
  return entry;
}

test("soldier_sync is sent every combat scan with the full field set", () => {
  const { match, ws } = makeMatch();
  match.advanceRealtime(1000);
  const count = () => ws.sent.filter((m) => m.type === "soldier_sync").length;
  const before = count();
  match.advanceRealtime(500);
  assert.equal(count() - before, 1, "one sync per 10-tick scan");
  const entry = entryFor(lastSync(ws), TEAM_USA, 1);
  for (const key of [
    "positionState",
    "movementMode",
    "facing",
    "stress",
    "grenadeCount",
    "ammoCurrent",
    "stunnedUntilMsec",
    "fireControlState",
    "engagedTargetTeamId",
    "engagedTargetSoldierId",
    "sustainedFire",
  ]) {
    assert.ok(key in entry, `missing ${key}`);
  }
});

test("scenario_time no longer carries the stress list", () => {
  const { match, ws } = makeMatch();
  match.advanceRealtime(1000);
  const times = ws.sent.filter((m) => m.type === "scenario_time");
  assert.ok(times.length > 0);
  for (const t of times) {
    assert.ok(!("stress" in t));
  }
});

test("dead soldiers are left out of soldier_sync", () => {
  const { match, ws } = makeMatch();
  const victim = match.gameState.getSoldier(TEAM_GERMANY, 1)!;
  victim.isDead = true;
  match.advanceRealtime(500);
  const entries = lastSync(ws);
  assert.ok(!entries.some((e) => e.teamId === TEAM_GERMANY && e.soldierId === 1));
});

test("grenade count change with no action result reaches clients", () => {
  const { match, ws } = makeMatch();
  match.gameState.getSoldier(TEAM_USA, 1)!.grenadeCount = 3;
  match.advanceRealtime(500);
  assert.equal(entryFor(lastSync(ws), TEAM_USA, 1).grenadeCount, 3);
});

test("standing up after a stun shows in soldier_sync", () => {
  const { match, ws } = makeMatch();
  const soldier = match.gameState.getSoldier(TEAM_USA, 1)!;
  const now = match.clock.getTicksMsec();
  soldier.positionState = POSITION_DOWN;
  soldier.stunnedUntilMsec = now + 400;
  soldier.standOnStunRecovery = true;
  match.advanceRealtime(500);
  const during = entryFor(lastSync(ws), TEAM_USA, 1);
  assert.equal(during.stunnedUntilMsec, now + 400);
  match.advanceRealtime(500);
  assert.equal(entryFor(lastSync(ws), TEAM_USA, 1).positionState, POSITION_UP);
});
