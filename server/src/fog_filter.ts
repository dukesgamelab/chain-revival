/**
 * Fog of war: what each team is allowed to receive (Phase 48).
 *
 * A team always gets its own soldiers in full. An enemy is "known" to a team while the
 * team's perception set holds him; then the team gets his position, stance, facing,
 * movement mode, stress and stun, but never his path, ammo or grenades. An unknown enemy
 * is left out, except for the facts that are public anyway: who is on the roster, who is
 * dead and where the body lies. A client with no team (joined but not on a side) is
 * treated as knowing no soldiers at all.
 */

import { teamDisplayName } from "./facing";
import type { GameState } from "./game_state";
import type { GrenadeExplosionPayload, GrenadeThrownPayload } from "./grenade_system";
import type { SoldierState } from "./soldier_state";
import type {
  CombatShotPayload,
  CombatShotsPayload,
  MatchSnapshot,
  MovementTickPayload,
  SoldierSnapshot,
  TargetSyncPayload,
  TargetUpdatePayload,
  Vec2i,
  VisibilityUpdatePayload,
} from "./types";

/** Roster entry for an enemy the team can't see (`known: false`). */
export interface HiddenSoldierSnapshot {
  soldierId: number;
  teamId: number;
  weaponId: string;
  isDead: boolean;
  known: false;
  /** Dead only: where the body lies. */
  gridPosition?: Vec2i;
  facing?: Vec2i;
  deathSpriteFamily?: string;
  stanceAtDeath?: number;
}

/** What a team may see of an enemy it has just spotted or still sees. */
export interface KnownEnemyState {
  teamId: number;
  soldierId: number;
  gridPosition: Vec2i;
  facing: Vec2i;
  positionState: number;
  movementMode: number;
  isMoving: boolean;
  moveSpeedMult: number;
  stress: number;
  stunnedUntilMsec: number;
  fireControlState: number;
  engagedTargetTeamId: number;
  engagedTargetSoldierId: number;
  sustainedFire: boolean;
  weaponId: string;
}

type SoldierRef = { teamId: number; soldierId: number };

export class FogView {
  constructor(
    private readonly state: GameState,
    readonly viewerTeamId: number | null,
  ) {}

  /** Own soldier, or an enemy the viewer's team currently sees. */
  knows(teamId: number, soldierId: number): boolean {
    if (this.viewerTeamId === null) {
      return false;
    }
    if (teamId === this.viewerTeamId) {
      return true;
    }
    return this.state.perception.isVisibleToTeam(this.viewerTeamId, teamId, soldierId);
  }

  isOwn(teamId: number): boolean {
    return this.viewerTeamId !== null && teamId === this.viewerTeamId;
  }

  knowsRef(ref: SoldierRef): boolean {
    return this.knows(ref.teamId, ref.soldierId);
  }
}

export function knownEnemyState(s: SoldierState): KnownEnemyState {
  return {
    teamId: s.teamId,
    soldierId: s.soldierId,
    gridPosition: { ...s.gridPosition },
    facing: { ...s.facing },
    positionState: s.positionState,
    movementMode: s.movementMode,
    isMoving: s.isMoving,
    moveSpeedMult: s.moveSpeedMult,
    stress: s.stress,
    stunnedUntilMsec: s.stunnedUntilMsec,
    fireControlState: s.fireControlState,
    engagedTargetTeamId: s.engagedTargetTeamId,
    engagedTargetSoldierId: s.engagedTargetSoldierId,
    sustainedFire: s.sustainedFire,
    weaponId: s.weaponId,
  };
}

function hiddenSnapshot(s: SoldierState): HiddenSoldierSnapshot {
  const entry: HiddenSoldierSnapshot = {
    soldierId: s.soldierId,
    teamId: s.teamId,
    weaponId: s.weaponId,
    isDead: s.isDead,
    known: false,
  };
  if (s.isDead) {
    entry.gridPosition = { ...s.gridPosition };
    entry.facing = { ...s.facing };
    entry.deathSpriteFamily = s.deathSpriteFamily;
    entry.stanceAtDeath = s.stanceAtDeath;
  }
  return entry;
}

/** Visible enemy in a snapshot: own-soldier shape minus path, ammo and grenades. */
function knownEnemySnapshot(s: SoldierState): SoldierSnapshot {
  const snap = s.toSnapshot();
  snap.currentPath = [];
  snap.pathIndex = 0;
  const trimmed: Partial<SoldierSnapshot> = { ...snap };
  delete trimmed.ammoCurrent;
  delete trimmed.grenadeCount;
  delete trimmed.fireReadyAfterMsec;
  delete trimmed.lastShotMsec;
  return trimmed as SoldierSnapshot;
}

export function filterSnapshot(
  snapshot: MatchSnapshot,
  state: GameState,
  view: FogView,
): Omit<MatchSnapshot, "soldiers"> & { soldiers: Array<SoldierSnapshot | HiddenSoldierSnapshot> } {
  const soldiers = state.soldiers.map((s) => {
    if (view.isOwn(s.teamId)) {
      return s.toSnapshot();
    }
    // Bodies are public; a dead enemy is never "visible" to perception.
    if (!s.isDead && view.knows(s.teamId, s.soldierId)) {
      return knownEnemySnapshot(s);
    }
    return hiddenSnapshot(s);
  });
  return {
    ...snapshot,
    soldiers,
    visibility: snapshot.visibility.filter((side) => side.teamId === view.viewerTeamId),
  };
}

/** Own side's visible list only, plus full state for enemies spotted since the last send. */
export function filterVisibility(
  payload: VisibilityUpdatePayload,
  view: FogView,
  revealed: SoldierState[],
): VisibilityUpdatePayload & { revealed: KnownEnemyState[] } {
  return {
    ...payload,
    sides: payload.sides.filter((side) => side.teamId === view.viewerTeamId),
    revealed: revealed.map(knownEnemyState),
  };
}

export function filterMovementTick(
  payload: MovementTickPayload,
  view: FogView,
): MovementTickPayload | null {
  const movementSteps = payload.movementSteps.filter((s) => view.knowsRef(s));
  const movementCompletions = payload.movementCompletions.filter((c) => view.knowsRef(c));
  if (movementSteps.length === 0 && movementCompletions.length === 0) {
    return null;
  }
  return { ...payload, movementSteps, movementCompletions };
}

interface SoldierSyncEntry {
  teamId: number;
  soldierId: number;
  [key: string]: unknown;
}

export function filterSoldierSync<T extends { soldiers: SoldierSyncEntry[] }>(payload: T, view: FogView): T {
  const soldiers: SoldierSyncEntry[] = [];
  for (const entry of payload.soldiers) {
    if (view.isOwn(entry.teamId)) {
      soldiers.push(entry);
    } else if (view.knowsRef(entry)) {
      const { grenadeCount: _g, ammoCurrent: _a, ...rest } = entry;
      soldiers.push(rest as SoldierSyncEntry);
    }
  }
  return { ...payload, soldiers };
}

export function filterTargetSync(payload: TargetSyncPayload, view: FogView): TargetSyncPayload | null {
  const targetUpdates = payload.targetUpdates.filter((u) => view.knowsRef(u));
  if (targetUpdates.length === 0) {
    return null;
  }
  return { ...payload, targetUpdates };
}

/** Per-soldier arrays carried by order results (move/face/position/fire control/Fire At). */
const RESULT_SOLDIER_LISTS = [
  "moveOrders",
  "movementHalts",
  "stanceTransitionOrders",
  "soldierUpdates",
  "faceUpdates",
  "targetUpdates",
] as const;

/**
 * Order result for the team that did not issue it: only soldiers it can see, no paths
 * (a path is the enemy's destination), no status text. Null when nothing is left.
 */
export function filterForeignResult<T extends { success: boolean; statusMessage: string }>(
  payload: T,
  view: FogView,
): T | null {
  if (!payload.success) {
    return null;
  }
  const out: Record<string, unknown> = { ...payload, statusMessage: "" };
  let any = false;
  for (const key of RESULT_SOLDIER_LISTS) {
    const list = (payload as Record<string, unknown>)[key];
    if (!Array.isArray(list)) {
      continue;
    }
    const kept = (list as SoldierRef[])
      .filter((entry) => view.knowsRef(entry))
      .map((entry) => (key === "moveOrders" ? { ...entry, path: [] } : entry));
    out[key] = kept;
    if (kept.length > 0) {
      any = true;
    }
  }
  return any ? (out as T) : null;
}

/**
 * Shots by or at the viewer's soldiers. A hidden enemy shooter comes with only his cell
 * (`shooterCell`, `shooterHidden`) so the tracer and the last-known marker can be drawn;
 * his pose, ammo and the hit breakdown stay on the server. Shots that never fired from a
 * hidden enemy are dropped.
 */
export function filterCombatShots(
  payload: CombatShotsPayload,
  state: GameState,
  view: FogView,
): CombatShotsPayload | null {
  const shots: CombatShotPayload[] = [];
  for (const shot of payload.shots) {
    const shooterKnown = view.knows(shot.shooterTeamId, shot.shooterId);
    const targetKnown = view.knows(shot.targetTeamId, shot.targetId);
    if (!shooterKnown && !targetKnown) {
      continue;
    }
    if (view.isOwn(shot.shooterTeamId)) {
      // Our soldier can keep firing at an enemy for a moment after losing sight of him.
      const out: CombatShotPayload & { targetCell?: Vec2i } = { ...shot };
      if (!targetKnown) {
        delete out.targetStress;
        delete out.movementHalt;
        const target = state.getSoldier(shot.targetTeamId, shot.targetId);
        if (shot.killed && target !== null) {
          out.targetCell = { ...target.gridPosition };
        }
      }
      shots.push(out);
      continue;
    }
    if (shooterKnown) {
      const { ammoCurrent: _a, fireReadyAfterMsec: _f, ...rest } = shot;
      shots.push(rest as CombatShotPayload);
      continue;
    }
    if (!shot.fired) {
      continue;
    }
    const shooter = state.getSoldier(shot.shooterTeamId, shot.shooterId);
    shots.push({
      shotId: shot.shotId,
      shooterTeamId: shot.shooterTeamId,
      shooterId: shot.shooterId,
      targetTeamId: shot.targetTeamId,
      targetId: shot.targetId,
      fired: shot.fired,
      hit: shot.hit,
      killed: shot.killed,
      blocked: shot.blocked,
      noAmmo: false,
      outOfRange: false,
      onCooldown: false,
      hadCover: shot.hadCover,
      coverType: shot.coverType,
      weaponId: shot.weaponId,
      weaponName: shot.weaponName,
      tracerCount: shot.tracerCount,
      cornerPeek: false,
      peekSide: 0,
      cornerCell: { x: -999, y: -999 },
      hitFinal: 0,
      killChance: 0,
      ammoCurrent: 0,
      fireReadyAfterMsec: 0,
      facing: { x: 0, y: 0 },
      deathSpriteFamily: shot.deathSpriteFamily,
      stanceAtDeath: shot.stanceAtDeath,
      movementHalt: shot.movementHalt, // the target's cell (ours), not the shooter's
      targetStress: shot.targetStress,
      messages: shot.messages,
      shooterHidden: true,
      shooterCell: shooter !== null ? { ...shooter.gridPosition } : undefined,
    } as CombatShotPayload);
  }
  if (shots.length === 0) {
    return null;
  }
  return { ...payload, shots };
}

/**
 * Successful throw seen by the other team: they see the grenade come in, so they get the
 * target cell and, if the thrower is hidden, only his cell (`throwerHidden`).
 */
export function filterForeignGrenadeThrown(
  payload: GrenadeThrownPayload,
  state: GameState,
  view: FogView,
): (GrenadeThrownPayload & { throwerHidden?: boolean; throwerCell?: Vec2i }) | null {
  if (!payload.success) {
    return null;
  }
  const out: GrenadeThrownPayload & { throwerHidden?: boolean; throwerCell?: Vec2i } = {
    ...payload,
    statusMessage: "",
    grenadeCount: 0,
  };
  if (view.knows(payload.throwerTeamId, payload.throwerId)) {
    return out;
  }
  const thrower = state.getSoldier(payload.throwerTeamId, payload.throwerId);
  out.facing = { x: 0, y: 0 };
  delete out.movementHalt;
  out.throwerHidden = true;
  if (thrower !== null) {
    out.throwerCell = { ...thrower.gridPosition };
  }
  return out;
}

/** Blast cell and deaths are public; stuns only for soldiers the viewer can see. */
export function filterGrenadeExplode(
  payload: GrenadeExplosionPayload,
  view: FogView,
): GrenadeExplosionPayload {
  const hiddenStuns = payload.stunned.filter((s) => !view.knowsRef(s));
  if (hiddenStuns.length === 0) {
    return payload;
  }
  const prefixes = hiddenStuns.map((s) => `${teamDisplayName(s.teamId)} Soldier ${s.soldierId} stunned`);
  return {
    ...payload,
    stunned: payload.stunned.filter((s) => view.knowsRef(s)),
    messages: payload.messages.filter((m) => !prefixes.some((p) => m.startsWith(p))),
  };
}
