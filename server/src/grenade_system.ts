/**
 * Authoritative grenade system: throw validation, fuse check, blast resolution.
 * Port of ActionResolver.execute_grenade + CombatSystem.resolve_grenade.
 */

import type { GameState } from "./game_state";
import { towardCell } from "./facing";
import { combatRange } from "./hit_resolution";
import { firstWallOnSegment, isShotWall } from "./los";
import type { MapData } from "./map_data";
import type { SoldierState } from "./soldier_state";
import { LETHALITY_MULTIPLIER } from "./hit_resolution";
import { onSoldierKilled } from "./scenario_rules";
import {
  chebyshev,
  POSITION_DOWN,
  MOVEMENT_RUN,
  MOVEMENT_CRAWL,
  type Vec2i,
  type GrenadeCommandIntent,
} from "./types";

// --- Grenade constants (from GrenadePolicy) ---

/** RECOVERED ArmamentGranade */
export const GRENADE_STARTING_COUNT = 5;
/** RECOVERED INITMaxGranadeDistance (Chebyshev tiles) */
export const GRENADE_THROW_RANGE = 5;
/** RECOVERED GranadeHitDistance (Euclidean tiles) */
export const GRENADE_HIT_DISTANCE = 2.0;
/** TUNED fuse delay in simulation msec */
export const GRENADE_FUSE_MSEC = 1800;
/** RECOVERED blast model constants */
export const GRENADE_VAR_A = 30.0;
export const GRENADE_VAR_B = 0.0;
export const GRENADE_VAR_C = 30.0;
export const GRENADE_VAR_D = 5.0;
/** TUNED divide-by-zero guard for distance denominator */
export const GRENADE_DISTANCE_DENOM_MIN = 0.5;
/** TUNED (2026-11-03): stun lasts at least this long anywhere in the blast. Mirrors GrenadePolicy.stun_min_sec. */
export const GRENADE_STUN_MIN_SEC = 5.0;

// --- Result types ---

export interface GrenadeKillEntry {
  teamId: number;
  soldierId: number;
  /** Where the body lies. Deaths are public, so this goes to both teams. */
  cell: Vec2i;
}

export interface GrenadeStunEntry {
  teamId: number;
  soldierId: number;
  durationSec: number;
}

export interface GrenadeExplosionPayload {
  type: "grenade_explode";
  matchId: string;
  simMsec: number;
  throwerTeamId: number;
  throwerId: number;
  explosionCell: Vec2i;
  blastRadius: number;
  killed: GrenadeKillEntry[];
  stunned: GrenadeStunEntry[];
  messages: string[];
}

export interface GrenadeThrownPayload {
  type: "grenade_thrown";
  matchId: string;
  simMsec: number;
  requestId: string;
  success: boolean;
  statusMessage: string;
  throwerTeamId: number;
  throwerId: number;
  targetCell: Vec2i;
  grenadeCount: number;
  facing: Vec2i;
  movementHalt?: Vec2i;
}

// --- Blast math ---

function euclideanDistance(a: Vec2i, b: Vec2i): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/** P(casualty) before lethality: VarA / (d + VarB), as 0-1. */
function casualtyChanceAtDistance(distance: number): number {
  const denom = Math.max(distance + GRENADE_VAR_B, GRENADE_DISTANCE_DENOM_MIN);
  const pct = GRENADE_VAR_A / denom;
  return Math.min(Math.max(pct / 100, 0), 1);
}

/** Stun duration in seconds: VarC / (d + VarD), floored at GRENADE_STUN_MIN_SEC. */
export function stunDurationAtDistance(distance: number): number {
  const denom = Math.max(distance + GRENADE_VAR_D, GRENADE_DISTANCE_DENOM_MIN);
  return Math.max(GRENADE_VAR_C / denom, GRENADE_STUN_MIN_SEC);
}

/**
 * Walls / opaque tiles between blast and victim block fragments. Port of
 * CombatSystem._grenade_blast_blocked: no wall-hugging cover exception, no corner
 * peeks, and soldiers never shield each other.
 */
// Walls stop fragments the same way they stop bullets: no line through a wall tile
// (los.ts isShotWall / firstWallOnSegment). A blast inside a wall reaches nobody.
function blastBlocked(from: Vec2i, to: Vec2i, state: GameState): boolean {
  if (from.x === to.x && from.y === to.y) {
    return false;
  }
  if (isShotWall(state.map, from)) {
    return true;
  }
  return firstWallOnSegment(from, to, state.map) !== null;
}

/** Why a throw is refused ("" when it is fine): no grenades onto or through a wall. Low walls,
 *  doorways and windows do not stop a throw. Mirrors CombatSystem.grenade_throw_refusal. */
export function grenadeThrowRefusal(map: MapData, from: Vec2i, to: Vec2i): string {
  if (isShotWall(map, to)) {
    return "Cannot throw onto a wall.";
  }
  if (firstWallOnSegment(from, to, map) !== null) {
    return "No clear throw - a wall is in the way.";
  }
  return "";
}

// --- Throw validation ---

export function executeGrenade(
  state: GameState,
  intent: GrenadeCommandIntent,
  teamId: number,
): GrenadeThrownPayload {
  const result: GrenadeThrownPayload = {
    type: "grenade_thrown",
    matchId: intent.matchId ?? "",
    simMsec: state.clock.getTicksMsec(),
    requestId: intent.requestId,
    success: false,
    statusMessage: "",
    throwerTeamId: intent.teamId,
    throwerId: intent.soldierId,
    targetCell: intent.targetCell,
    grenadeCount: 0,
    facing: { x: 0, y: 0 },
  };

  if (intent.teamId !== teamId) {
    result.statusMessage = "Cannot control that team.";
    return result;
  }

  const soldier = state.getSoldier(intent.teamId, intent.soldierId);
  if (soldier === null || soldier.isDead) {
    result.statusMessage = "Soldier unavailable.";
    return result;
  }
  if (soldier.isStunned(state.clock.getTicksMsec())) {
    result.statusMessage = "Soldier is stunned.";
    return result;
  }
  if (soldier.grenadeExplodeAtMsec > 0) {
    result.statusMessage = "Soldier already has a grenade in the air.";
    return result;
  }
  if (soldier.grenadeCount <= 0) {
    result.statusMessage = "No grenades remaining.";
    return result;
  }

  const targetCell = state.map.clampToBounds(intent.targetCell);
  const throwDistance = chebyshev(soldier.gridPosition, targetCell);
  if (throwDistance > GRENADE_THROW_RANGE) {
    result.statusMessage = "Target is out of grenade range.";
    return result;
  }
  const refusal = grenadeThrowRefusal(state.map, soldier.gridPosition, targetCell);
  if (refusal !== "") {
    result.statusMessage = refusal;
    return result;
  }

  // Friendly fire warning (allowed but risky)
  // grenadeWouldHitFriendly is still used client-side for the visual warning

  // Halt movement
  if (soldier.isMoving) {
    soldier.clearPath();
    result.movementHalt = { ...soldier.gridPosition };
  }

  // Face toward target
  const facing = towardCell(soldier.gridPosition, targetCell);
  if (facing.x !== 0 || facing.y !== 0) {
    soldier.facing = facing;
  }

  // Commit the throw
  soldier.grenadeCount -= 1;
  soldier.endSustainedFire();
  soldier.resetFirePrep();
  soldier.pendingGrenadeTarget = { ...targetCell };
  soldier.grenadeExplodeAtMsec = state.clock.getTicksMsec() + GRENADE_FUSE_MSEC;

  result.success = true;
  result.statusMessage = "Grenade thrown.";
  result.grenadeCount = soldier.grenadeCount;
  result.facing = { ...soldier.facing };
  result.targetCell = { ...targetCell };
  return result;
}

// --- Blast resolution ---

export function resolveGrenade(
  state: GameState,
  thrower: SoldierState,
  explosionCell: Vec2i,
): { killed: GrenadeKillEntry[]; stunned: GrenadeStunEntry[]; messages: string[] } {
  const killed: GrenadeKillEntry[] = [];
  const stunned: GrenadeStunEntry[] = [];
  const messages: string[] = [];

  for (const soldier of state.soldiers) {
    if (soldier.isDead) {
      continue;
    }
    const isFriendly = soldier.teamId === thrower.teamId;

    const distance = euclideanDistance(soldier.gridPosition, explosionCell);
    if (distance > GRENADE_HIT_DISTANCE) {
      continue;
    }
    if (blastBlocked(explosionCell, soldier.gridPosition, state)) {
      continue;
    }

    const casualtyChance = casualtyChanceAtDistance(distance);
    const killChance = Math.min(Math.max(casualtyChance * LETHALITY_MULTIPLIER, 0), 1);

    if (state.rng.chance(killChance)) {
      soldier.markKilled(state.rng);
      state.markPerceptionDirty();
      if (!isFriendly) {
        onSoldierKilled(state.scenario, thrower.teamId, soldier);
      }
      killed.push({ teamId: soldier.teamId, soldierId: soldier.soldierId, cell: { ...soldier.gridPosition } });
      const killMsg = isFriendly
        ? `${teamDisplayName(soldier.teamId)} Soldier ${soldier.soldierId} killed by FRIENDLY grenade!`
        : `${teamDisplayName(soldier.teamId)} Soldier ${soldier.soldierId} killed by grenade blast.`;
      messages.push(killMsg);

      // Clear engagements on this dead soldier
      for (const other of state.soldiers) {
        if (
          other.engagedTargetTeamId === soldier.teamId &&
          other.engagedTargetSoldierId === soldier.soldierId
        ) {
          other.clearEngagedTarget();
          other.resetFirePrep();
          other.endSustainedFire();
        }
      }
      continue;
    }

    // Survivor: apply stun
    const stunSec = stunDurationAtDistance(distance);
    applyGrenadeStun(soldier, stunSec, state.clock.getTicksMsec());
    stunned.push({ teamId: soldier.teamId, soldierId: soldier.soldierId, durationSec: stunSec });
    const stunMsg = isFriendly
      ? `${teamDisplayName(soldier.teamId)} Soldier ${soldier.soldierId} stunned by FRIENDLY grenade! (${stunSec.toFixed(1)}s)`
      : `${teamDisplayName(soldier.teamId)} Soldier ${soldier.soldierId} stunned by grenade blast (${stunSec.toFixed(1)}s).`;
    messages.push(stunMsg);
  }

  return { killed, stunned, messages };
}

/** Check grenade fuse expiry during combat tick. Returns explosions to broadcast. */
export function processGrenadeExplosions(
  state: GameState,
): { explosions: Array<{ thrower: SoldierState; explosionCell: Vec2i; killed: GrenadeKillEntry[]; stunned: GrenadeStunEntry[]; messages: string[] }> } {
  const explosions: Array<{ thrower: SoldierState; explosionCell: Vec2i; killed: GrenadeKillEntry[]; stunned: GrenadeStunEntry[]; messages: string[] }> = [];
  const nowMsec = state.clock.getTicksMsec();

  for (const soldier of state.soldiers) {
    if (soldier.grenadeExplodeAtMsec <= 0) {
      continue;
    }
    if (nowMsec < soldier.grenadeExplodeAtMsec) {
      continue;
    }

    const explosionCell = { ...soldier.pendingGrenadeTarget };
    soldier.clearPendingGrenade();

    const result = resolveGrenade(state, soldier, explosionCell);
    explosions.push({
      thrower: soldier,
      explosionCell,
      ...result,
    });
  }

  return { explosions };
}

/** Stun recovery: stand up after stun expires. */
export function recoverStunTick(state: GameState): boolean {
  let changed = false;
  const nowMsec = state.clock.getTicksMsec();
  for (const soldier of state.soldiers) {
    if (soldier.isDead || soldier.isStunned(nowMsec)) {
      continue;
    }
    if (soldier.standOnStunRecovery) {
      soldier.standOnStunRecovery = false;
      if (soldier.positionState === POSITION_DOWN) {
        soldier.positionState = 0; // POSITION_UP
        soldier.movementMode = MOVEMENT_RUN;
        changed = true;
      }
    }
  }
  return changed;
}

function grenadeWouldHitFriendly(
  state: GameState,
  throwerTeamId: number,
  explosionCell: Vec2i,
): boolean {
  for (const soldier of state.soldiers) {
    if (soldier.isDead || soldier.teamId !== throwerTeamId) {
      continue;
    }
    const distance = euclideanDistance(soldier.gridPosition, explosionCell);
    if (distance > GRENADE_HIT_DISTANCE) {
      continue;
    }
    if (blastBlocked(explosionCell, soldier.gridPosition, state)) {
      continue;
    }
    return true;
  }
  return false;
}

function applyGrenadeStun(soldier: SoldierState, durationSec: number, nowMsec: number): void {
  soldier.stunnedUntilMsec = nowMsec + Math.max(durationSec, 0) * 1000;
  soldier.positionState = POSITION_DOWN;
  soldier.movementMode = MOVEMENT_CRAWL;
  soldier.clearPendingPosition();
  soldier.standOnStunRecovery = true;
  soldier.clearPath();
  soldier.endSustainedFire();
  soldier.resetFirePrep();
  soldier.clearPendingGrenade();
}

function teamDisplayName(teamId: number): string {
  return teamId === 2 ? "Germany" : "USA";
}
