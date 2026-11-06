import assert from "node:assert/strict";
import { test } from "node:test";
import type { WebSocket } from "ws";
import { FogView, filterCombatShots, filterGrenadeExplode } from "../src/fog_filter";
import type { GrenadeExplosionPayload } from "../src/grenade_system";
import { LocalMatch } from "../src/match";
import type { SoldierState } from "../src/soldier_state";
import {
  FIRE_AT_WILL,
  FIRE_HOLD,
  MATCH_ID,
  MOVEMENT_RUN,
  MOVE_SCOPE_SINGLE,
  POSITION_DOWN,
  TEAM_GERMANY,
  TEAM_USA,
  vec,
  type CombatShotPayload,
  type CombatShotsPayload,
  type Vec2i,
} from "../src/types";

type Msg = Record<string, unknown> & { type: string };
type FakeWs = WebSocket & { sent: Msg[] };

function fakeWs(): FakeWs {
  const sent: Msg[] = [];
  const ws = {
    sent,
    readyState: 1,
    OPEN: 1,
    send(text: string) {
      sent.push(JSON.parse(text) as Msg);
    },
  };
  return ws as unknown as FakeWs;
}

function makeMatch(): { match: LocalMatch; usa: FakeWs; ger: FakeWs } {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  const usa = fakeWs();
  const ger = fakeWs();
  match.attachClient("usa", usa);
  match.attachClient("ger", ger);
  match.setClientTeam("usa", TEAM_USA);
  match.setClientTeam("ger", TEAM_GERMANY);
  return { match, usa, ger };
}

function soldier(match: LocalMatch, teamId: number, id: number): SoldierState {
  const s = match.gameState.getSoldier(teamId, id);
  assert.ok(s);
  return s;
}

function rebuild(match: LocalMatch): void {
  match.gameState.perception.rebuildVisibility(match.gameState);
}

function usaSees(match: LocalMatch, gerId: number): boolean {
  return match.gameState.perception.isVisibleToTeam(TEAM_USA, TEAM_GERMANY, gerId);
}

/** Put German `gerId` somewhere USA 1 can spot him, a few tiles in front. */
function placeInView(match: LocalMatch, gerId: number): Vec2i {
  const observer = soldier(match, TEAM_USA, 1);
  const target = soldier(match, TEAM_GERMANY, gerId);
  const dirs = [vec(-1, 0), vec(1, 0), vec(0, -1), vec(0, 1), vec(-1, -1), vec(1, 1), vec(-1, 1), vec(1, -1)];
  for (const dist of [3, 4, 5, 2, 6]) {
    for (const dir of dirs) {
      const cell = vec(observer.gridPosition.x + dir.x * dist, observer.gridPosition.y + dir.y * dist);
      if (!match.gameState.map.isWalkable(cell) || match.gameState.findLivingSoldierAtCell(cell) !== null) {
        continue;
      }
      target.gridPosition = cell;
      observer.facing = dir;
      rebuild(match);
      if (usaSees(match, gerId)) {
        return cell;
      }
    }
  }
  throw new Error("no spot in view of USA 1");
}

/** Every object in `value` that names a German soldier. */
function germanRefs(value: unknown, out: Array<Record<string, unknown>> = []): Array<Record<string, unknown>> {
  if (Array.isArray(value)) {
    for (const item of value) germanRefs(item, out);
  } else if (value !== null && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    if (obj.teamId === TEAM_GERMANY && typeof obj.soldierId === "number") {
      out.push(obj);
    }
    for (const child of Object.values(obj)) germanRefs(child, out);
  }
  return out;
}

const POSITION_KEYS = ["gridPosition", "tile", "snapCell", "path", "facing", "positionState", "stress", "cell"];

function assertNoGermanState(messages: Msg[]): void {
  for (const msg of messages) {
    if (msg.type === "match_ended") continue;
    for (const ref of germanRefs(msg)) {
      for (const key of POSITION_KEYS) {
        assert.ok(!(key in ref), `${msg.type} leaks German ${ref.soldierId} ${key}: ${JSON.stringify(ref)}`);
      }
    }
    for (const key of ["shooterCell", "throwerCell"]) {
      assert.ok(!(key in msg), `${msg.type} carries ${key}`);
    }
  }
}

function moveGerman(match: LocalMatch, id: number, target: Vec2i, requestId = "gm1"): void {
  match.handleMove("ger", {
    type: "move_command",
    matchId: MATCH_ID,
    requestId,
    teamId: TEAM_GERMANY,
    soldierId: id,
    targetCell: target,
    scope: MOVE_SCOPE_SINGLE,
    movementMode: MOVEMENT_RUN,
  });
}

test("snapshot: own soldiers in full, unseen enemies as roster only", () => {
  const { match, usa } = makeMatch();
  usa.sent.length = 0;
  match.sendSnapshot(usa);
  const snap = usa.sent[0];
  assert.equal(snap.type, "match_snapshot");
  const soldiers = snap.soldiers as Array<Record<string, unknown>>;
  const own = soldiers.find((s) => s.teamId === TEAM_USA && s.soldierId === 1)!;
  assert.ok("gridPosition" in own && "ammoCurrent" in own && "currentPath" in own);
  const enemy = soldiers.find((s) => s.teamId === TEAM_GERMANY && s.soldierId === 1)!;
  assert.deepEqual(Object.keys(enemy).sort(), ["isDead", "known", "soldierId", "teamId", "weaponId"]);
  assert.equal(enemy.known, false);
  const sides = snap.visibility as Array<{ teamId: number }>;
  assert.deepEqual(sides.map((s) => s.teamId), [TEAM_USA]);
});

test("a client with no side gets no soldier positions at all", () => {
  const match = new LocalMatch("ff_farm", { startDriver: false });
  const ws = fakeWs();
  match.attachClient("lurker", ws);
  match.sendSnapshot(ws);
  const soldiers = ws.sent[0].soldiers as Array<Record<string, unknown>>;
  assert.ok(soldiers.every((s) => s.known === false && !("gridPosition" in s)));
  match.advanceRealtime(1000);
  for (const msg of ws.sent.filter((m) => m.type === "soldier_sync")) {
    assert.deepEqual(msg.soldiers, []);
  }
});

test("match start: neither side receives anything about the other's soldiers", () => {
  const { match, usa, ger } = makeMatch();
  match.sendSnapshot(usa);
  match.sendSnapshot(ger);
  // Germany deploys and fiddles about in its own zone, far out of sight.
  const g1 = soldier(match, TEAM_GERMANY, 1);
  moveGerman(match, 1, vec(g1.gridPosition.x + 2, g1.gridPosition.y));
  match.handleFace("ger", {
    type: "face_command",
    matchId: MATCH_ID,
    requestId: "gf1",
    teamId: TEAM_GERMANY,
    soldierId: 2,
    targetCell: vec(g1.gridPosition.x, g1.gridPosition.y + 3),
    scope: MOVE_SCOPE_SINGLE,
    aimWorld: null,
  });
  match.handlePosition("ger", {
    type: "position_command",
    matchId: MATCH_ID,
    requestId: "gp1",
    teamId: TEAM_GERMANY,
    soldierId: 3,
    positionState: POSITION_DOWN,
  });
  match.handleFireControl("ger", {
    type: "fire_control_command",
    matchId: MATCH_ID,
    requestId: "gc1",
    teamId: TEAM_GERMANY,
    soldierId: 4,
    fireControlState: FIRE_HOLD,
  });
  match.advanceRealtime(3000);
  assert.ok(!usaSees(match, 1));
  assertNoGermanState(usa.sent);
  assert.ok(!usa.sent.some((m) => m.type === "move_result"), "foreign hidden move_result is dropped");
  // Germany still hears all of it, path included.
  const ownMove = ger.sent.find((m) => m.type === "move_result")!;
  const orders = ownMove.moveOrders as Array<{ path: Vec2i[] }>;
  assert.ok(orders[0].path.length > 1);
});

test("enemy walking into view is revealed with his real cell, then tracked", () => {
  const { match, usa } = makeMatch();
  const cell = placeInView(match, 2);
  // Hide him again so the next scan is a fresh reveal.
  const g2 = soldier(match, TEAM_GERMANY, 2);
  g2.gridPosition = vec(8, 46);
  rebuild(match);
  match.advanceRealtime(500);
  usa.sent.length = 0;
  g2.gridPosition = cell;
  match.gameState.markPerceptionDirty();
  match.advanceRealtime(100);
  const vis = usa.sent.find((m) => m.type === "visibility_update")!;
  assert.ok(vis, "visibility_update on spotting");
  const revealed = vis.revealed as Array<Record<string, unknown>>;
  const entry = revealed.find((r) => r.teamId === TEAM_GERMANY && r.soldierId === 2)!;
  assert.deepEqual(entry.gridPosition, cell);
  assert.ok(!("ammoCurrent" in entry) && !("grenadeCount" in entry) && !("currentPath" in entry));
  const sides = vis.sides as Array<{ teamId: number; visible: Array<{ soldierId: number }> }>;
  assert.deepEqual(sides.map((s) => s.teamId), [TEAM_USA]);
  assert.ok(sides[0].visible.some((v) => v.soldierId === 2));

  // While seen, soldier_sync carries him, minus ammo and grenades.
  match.advanceRealtime(500);
  const sync = usa.sent.filter((m) => m.type === "soldier_sync").pop()!;
  const syncEntry = (sync.soldiers as Array<Record<string, unknown>>).find(
    (s) => s.teamId === TEAM_GERMANY && s.soldierId === 2,
  )!;
  assert.ok(syncEntry && "positionState" in syncEntry);
  assert.ok(!("ammoCurrent" in syncEntry) && !("grenadeCount" in syncEntry));
  // A second scan with no change does not reveal him again.
  usa.sent.length = 0;
  match.advanceRealtime(500);
  for (const m of usa.sent.filter((x) => x.type === "visibility_update")) {
    assert.ok(!(m.revealed as unknown[]).length);
  }
});

test("seen enemy's order reaches the other side without path or status text", () => {
  const { match, usa } = makeMatch();
  const cell = placeInView(match, 2);
  match.advanceRealtime(100);
  usa.sent.length = 0;
  moveGerman(match, 2, vec(cell.x, cell.y + 2), "gm2");
  const foreign = usa.sent.find((m) => m.type === "move_result")!;
  assert.ok(foreign, "foreign move_result for a seen soldier");
  assert.equal(foreign.statusMessage, "");
  for (const order of foreign.moveOrders as Array<{ soldierId: number; path: unknown[] }>) {
    assert.equal(order.soldierId, 2);
    assert.deepEqual(order.path, []);
  }
});

test("enemy stepping out of view: that step and later ones are never sent", () => {
  const { match, usa } = makeMatch();
  placeInView(match, 2);
  match.advanceRealtime(100);
  assert.ok(usaSees(match, 2));
  // Turn the only spotter away; the German walks off.
  const u1 = soldier(match, TEAM_USA, 1);
  u1.facing = vec(-u1.facing.x || 1, -u1.facing.y);
  for (const s of match.gameState.soldiersOnTeam(TEAM_USA)) {
    if (s.soldierId !== 1) s.facing = { ...u1.facing };
  }
  match.gameState.markPerceptionDirty();
  match.advanceRealtime(100);
  assert.ok(!usaSees(match, 2), "precondition: hidden again");
  usa.sent.length = 0;
  const g2 = soldier(match, TEAM_GERMANY, 2);
  moveGerman(match, 2, vec(g2.gridPosition.x, g2.gridPosition.y + 3), "gm3");
  match.advanceRealtime(2000);
  assert.ok(!usaSees(match, 2), "still hidden after the walk");
  assertNoGermanState(usa.sent);
});

test("hidden shooter: tracer cell only, no pose, ammo or hit breakdown", () => {
  const { match } = makeMatch();
  const shooter = soldier(match, TEAM_GERMANY, 1);
  const shot = {
    shotId: 1,
    shooterTeamId: TEAM_GERMANY,
    shooterId: 1,
    targetTeamId: TEAM_USA,
    targetId: 1,
    fired: true,
    hit: false,
    killed: false,
    blocked: false,
    noAmmo: false,
    outOfRange: false,
    onCooldown: false,
    hadCover: false,
    coverType: 0,
    weaponId: "kar98k",
    weaponName: "Kar98k",
    tracerCount: 1,
    cornerPeek: true,
    peekSide: 1,
    cornerCell: vec(1, 1),
    hitFinal: 0.3,
    killChance: 0.1,
    ammoCurrent: 4,
    fireReadyAfterMsec: 1234,
    facing: vec(1, 0),
    hitBreakdown: { base: 1 },
    targetStress: 40,
    messages: ["shot"],
  } as CombatShotPayload;
  const payload: CombatShotsPayload = { type: "combat_shots", matchId: MATCH_ID, simMsec: 0, tickId: 0, shots: [shot] };
  const view = new FogView(match.gameState, TEAM_USA);
  const out = filterCombatShots(payload, match.gameState, view)!;
  const sent = out.shots[0] as CombatShotPayload & { shooterHidden?: boolean; shooterCell?: Vec2i };
  assert.equal(sent.shooterHidden, true);
  assert.deepEqual(sent.shooterCell, shooter.gridPosition);
  assert.equal(sent.ammoCurrent, 0);
  assert.equal(sent.cornerPeek, false);
  assert.deepEqual(sent.facing, vec(0, 0));
  assert.ok(!("hitBreakdown" in sent));
  assert.equal(sent.targetStress, 40, "our own soldier's stress still arrives");
  // A dry click (not fired) from a hidden enemy is dropped.
  const dry = filterCombatShots({ ...payload, shots: [{ ...shot, fired: false }] }, match.gameState, view);
  assert.equal(dry, null);
  // Germany's own client gets its shot untouched.
  const own = filterCombatShots(payload, match.gameState, new FogView(match.gameState, TEAM_GERMANY))!;
  assert.equal(own.shots[0].ammoCurrent, 4);
});

test("grenade blast: deaths with body cell are public, hidden stuns are not", () => {
  const { match } = makeMatch();
  const payload: GrenadeExplosionPayload = {
    type: "grenade_explode",
    matchId: MATCH_ID,
    simMsec: 0,
    throwerTeamId: TEAM_USA,
    throwerId: 1,
    explosionCell: vec(10, 46),
    blastRadius: 2,
    killed: [{ teamId: TEAM_GERMANY, soldierId: 1, cell: vec(10, 46) }],
    stunned: [{ teamId: TEAM_GERMANY, soldierId: 2, durationSec: 4 }],
    messages: ["Germany Soldier 1 killed by grenade blast.", "Germany Soldier 2 stunned by grenade blast (4.0s)."],
  };
  const out = filterGrenadeExplode(payload, new FogView(match.gameState, TEAM_USA));
  assert.equal(out.killed.length, 1);
  assert.deepEqual(out.killed[0].cell, vec(10, 46));
  assert.equal(out.stunned.length, 0);
  assert.deepEqual(out.messages, ["Germany Soldier 1 killed by grenade blast."]);
  const own = filterGrenadeExplode(payload, new FogView(match.gameState, TEAM_GERMANY));
  assert.equal(own.stunned.length, 1);
});

test("fire control of a hidden enemy changes nothing the other side can see", () => {
  const { match, usa } = makeMatch();
  usa.sent.length = 0;
  match.handleFireControl("ger", {
    type: "fire_control_command",
    matchId: MATCH_ID,
    requestId: "gc2",
    teamId: TEAM_GERMANY,
    soldierId: 1,
    fireControlState: FIRE_AT_WILL,
  });
  assert.ok(!usa.sent.some((m) => m.type === "fire_control_result"));
});
