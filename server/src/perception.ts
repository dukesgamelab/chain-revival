/**
 * Authoritative spotting + target maintenance.
 * Team-aggregated visibility (one spotter reveals the enemy to the side).
 * Combat scan every 10 ticks (0.5s). Pair rebuild only when dirty or on scan.
 */

import type { GameState } from "./game_state";
import { euclidean, isFacingTowardTarget, manhattan, soldierKey } from "./grid";
import { COVER_COMPLETE, COVER_MODERATE, COVER_NONE } from "./map_objects";
import { evaluate, evaluateSpotting, isSpottingLineBlocked, LOS_BLOCKED } from "./los";
import type { SoldierState } from "./soldier_state";
import {
  FIRE_AT_WILL,
  MOVEMENT_RUN,
  MOVEMENT_WALK,
  POSITION_DOWN,
  TEAM_GERMANY,
  TEAM_USA,
  type TargetUpdatePayload,
  type Vec2i,
  type VisibilitySidePayload,
} from "./types";

export const WEAPON_RANGE_TILES = 40;
export const SPOTTING_RANGE_BONUS = 10;
export const COMBAT_SCAN_TICKS = 10;
export const TARGET_LOST_GRACE_MSEC = 1500;
export const RECENTLY_SEEN_SEC = 2.0;
export const LAST_KNOWN_NEAR_TILES = 2;

const VIS_BASE = 100;
const VIS_DIST = 4;
const VIS_RUN = 15;
const VIS_WALK = 10;
const VIS_FIRED = 25;
const VIS_COVER_PENALTY = 20;
const VIS_COVER_MULT = 0.65;

const AUTO_BASE = 100;
const AUTO_DIST = 4;
const AUTO_CLEAR = 25;
const AUTO_MOD = 10;
const AUTO_COMPLETE = 25;
const AUTO_MOVING = 10;
const AUTO_PRONE = 20;
const AUTO_FACING = 15;

export interface PerceptionTickResult {
  visibilityChanged: boolean;
  targetUpdates: TargetUpdatePayload[];
}

export class PerceptionSystem {
  visibleByTeam = new Map<number, Set<string>>();
  private fingerprint = "";
  dirty = true;

  markDirty(): void {
    this.dirty = true;
  }

  acknowledge(): void {
    this.dirty = false;
    this.fingerprint = fingerprint(this.visibleByTeam);
  }

  isVisibleToTeam(teamId: number, enemyTeamId: number, enemySoldierId: number): boolean {
    return this.visibleByTeam.get(teamId)?.has(soldierKey(enemyTeamId, enemySoldierId)) ?? false;
  }

  visibilityPayload(): VisibilitySidePayload[] {
    return [TEAM_USA, TEAM_GERMANY].map((teamId) => ({
      teamId,
      visible: [...(this.visibleByTeam.get(teamId) ?? [])].map((key) => {
        const [team, id] = key.split(":").map(Number);
        return { teamId: team, soldierId: id };
      }),
    }));
  }

  processTick(state: GameState, tickId: number, forceScan = false): PerceptionTickResult {
    const scan = forceScan || tickId % COMBAT_SCAN_TICKS === 0;
    if (this.dirty || scan) {
      this.rebuildVisibility(state);
      this.dirty = false;
    }
    const visibilityChanged = this.consumeVisibilityChange();
    const targetUpdates = scan ? this.maintainTargets(state) : [];
    return { visibilityChanged, targetUpdates };
  }

  rebuildVisibility(state: GameState): void {
    const next = new Map<number, Set<string>>();
    next.set(TEAM_USA, new Set());
    next.set(TEAM_GERMANY, new Set());
    const now = state.clock.getTicksMsec();
    for (const observer of state.soldiers) {
      if (observer.isDead) {
        continue;
      }
      const teamVis = next.get(observer.teamId);
      if (teamVis === undefined) {
        continue;
      }
      for (const target of state.soldiers) {
        if (target.teamId === observer.teamId || target.isDead) {
          continue;
        }
        const score = spotScore(observer, target, state);
        if (score >= 0) {
          teamVis.add(soldierKey(target.teamId, target.soldierId));
          observer.recordLastSeen(target.teamId, target.soldierId, now, target.gridPosition);
        }
      }
    }
    this.visibleByTeam = next;
  }

  private consumeVisibilityChange(): boolean {
    const next = fingerprint(this.visibleByTeam);
    if (next === this.fingerprint) {
      return false;
    }
    this.fingerprint = next;
    return true;
  }

  maintainTargets(state: GameState): TargetUpdatePayload[] {
    const updates: TargetUpdatePayload[] = [];
    const now = state.clock.getTicksMsec();
    for (const shooter of state.soldiers) {
      if (shooter.isDead) {
        continue;
      }
      const before = engagementKey(shooter);
      this.resolveEngagement(state, shooter, now);
      if (engagementKey(shooter) !== before) {
        updates.push(targetUpdate(shooter));
      }
    }
    return updates;
  }

  private resolveEngagement(state: GameState, shooter: SoldierState, now: number): void {
    if (shooter.isMoving || shooter.isStunned(now)) {
      return;
    }
    const current = shooter.isEngaged()
      ? state.getSoldier(shooter.engagedTargetTeamId, shooter.engagedTargetSoldierId)
      : null;

    if (shooter.sustainedFire) {
      if (current !== null && !current.isDead && isPriorityTrackable(shooter, current, state)) {
        shooter.engagedTargetLostMsec = 0;
        return;
      }
      if (current !== null && !targetLostGraceElapsed(shooter, now)) {
        return;
      }
      shooter.clearEngagedTarget();
      shooter.engagedTargetLostMsec = 0;
      return;
    }

    if (shooter.fireControlState !== FIRE_AT_WILL) {
      if (shooter.isEngaged()) {
        shooter.clearEngagedTarget();
      }
      return;
    }

    if (current !== null && !current.isDead && isAutoTargetValid(shooter, current, state)) {
      shooter.engagedTargetLostMsec = 0;
      return;
    }
    if (current !== null && !targetLostGraceElapsed(shooter, now)) {
      return;
    }
    const next = findBestAutoTarget(state, shooter);
    if (next === null) {
      shooter.clearEngagedTarget();
      shooter.engagedTargetLostMsec = 0;
      return;
    }
    shooter.setEngagedTarget(next.teamId, next.soldierId);
    shooter.engagedTargetLostMsec = 0;
    const facing = faceToward(shooter.gridPosition, next.gridPosition);
    if (facing.x !== 0 || facing.y !== 0) {
      shooter.facing = facing;
    }
  }
}

function fingerprint(vis: Map<number, Set<string>>): string {
  return [TEAM_USA, TEAM_GERMANY]
    .map((team) => `${team}:${[...(vis.get(team) ?? [])].sort().join(",")}`)
    .join("|");
}

function engagementKey(s: SoldierState): string {
  return `${s.engagedTargetTeamId}:${s.engagedTargetSoldierId}:${s.sustainedFire ? 1 : 0}`;
}

function targetUpdate(s: SoldierState): TargetUpdatePayload {
  return {
    teamId: s.teamId,
    soldierId: s.soldierId,
    fireControlState: s.fireControlState,
    engagedTargetTeamId: s.engagedTargetTeamId,
    engagedTargetSoldierId: s.engagedTargetSoldierId,
    sustainedFire: s.sustainedFire,
  };
}

function targetLostGraceElapsed(shooter: SoldierState, now: number): boolean {
  if (shooter.engagedTargetLostMsec <= 0) {
    shooter.engagedTargetLostMsec = now;
    return false;
  }
  return now - shooter.engagedTargetLostMsec >= TARGET_LOST_GRACE_MSEC;
}

export function spottingRange(): number {
  return WEAPON_RANGE_TILES + SPOTTING_RANGE_BONUS;
}

export function spotScore(observer: SoldierState, target: SoldierState, state: GameState): number {
  if (observer.isDead || target.isDead || observer.teamId === target.teamId) {
    return -1;
  }
  const dist = manhattan(observer.gridPosition, target.gridPosition);
  const range = spottingRange();
  if (dist > range) {
    return -1;
  }
  if (!isFacingTowardTarget(observer.gridPosition, observer.facing, target.gridPosition, range)) {
    return -1;
  }
  let score = VIS_BASE - dist * VIS_DIST;
  if (target.isMoving) {
    if (target.movementMode === MOVEMENT_RUN) {
      score += VIS_RUN;
    } else if (target.movementMode === MOVEMENT_WALK) {
      score += VIS_WALK;
    }
  }
  if (target.lastFiredMsec > 0) {
    const elapsed = (state.clock.getTicksMsec() - target.lastFiredMsec) / 1000;
    if (elapsed <= 2) {
      score += VIS_FIRED;
    }
  }
  if (score < 0) {
    return -1;
  }
  const observerProne = observer.positionState === POSITION_DOWN;
  const targetProne = target.positionState === POSITION_DOWN;
  if (score >= VIS_COVER_PENALTY) {
    if (isSpottingLineBlocked(observer.gridPosition, target.gridPosition, state.map, observerProne, targetProne)) {
      return -1;
    }
    return score;
  }
  const los = evaluateSpotting(
    observer.gridPosition,
    target.gridPosition,
    state.map,
    observerProne,
    targetProne,
  );
  if (los.status === LOS_BLOCKED) {
    return -1;
  }
  if (los.coverType === COVER_MODERATE) {
    score -= VIS_COVER_PENALTY;
    score *= VIS_COVER_MULT;
  }
  return score >= 0 ? score : -1;
}

export function canSpot(observer: SoldierState, target: SoldierState, state: GameState): boolean {
  return spotScore(observer, target, state) >= 0;
}

export function isEnemyRecentlySeen(observer: SoldierState, enemyTeamId: number, enemySoldierId: number, now: number): boolean {
  const seen = observer.getLastSeen(enemyTeamId, enemySoldierId);
  if (seen === null) {
    return false;
  }
  return (now - seen.msec) / 1000 <= RECENTLY_SEEN_SEC;
}

export function canAssignManualPriority(
  observer: SoldierState,
  target: SoldierState,
  state: GameState,
  clickCell: Vec2i | undefined,
): boolean {
  if (observer.isDead || target.isDead || observer.teamId === target.teamId) {
    return false;
  }
  if (canSpot(observer, target, state)) {
    return true;
  }
  const now = state.clock.getTicksMsec();
  if (!isEnemyRecentlySeen(observer, target.teamId, target.soldierId, now)) {
    return false;
  }
  const last = observer.getLastSeen(target.teamId, target.soldierId);
  const lastCell = last?.cell ?? target.gridPosition;
  const click = clickCell ?? target.gridPosition;
  return (
    manhattan(lastCell, click) <= LAST_KNOWN_NEAR_TILES ||
    manhattan(target.gridPosition, click) <= LAST_KNOWN_NEAR_TILES
  );
}

export function isPriorityTrackable(
  observer: SoldierState,
  target: SoldierState,
  state: GameState,
): boolean {
  if (observer.isDead || target.isDead || observer.teamId === target.teamId) {
    return false;
  }
  if (state.perception.isVisibleToTeam(observer.teamId, target.teamId, target.soldierId)) {
    return true;
  }
  if (canSpot(observer, target, state)) {
    return true;
  }
  return isEnemyRecentlySeen(observer, target.teamId, target.soldierId, state.clock.getTicksMsec());
}

export function scoreAutoTarget(shooter: SoldierState, target: SoldierState, state: GameState): number {
  if (shooter.isDead || target.isDead) {
    return -1;
  }
  const occupants = state.losOccupants();
  const los = evaluate(shooter.gridPosition, target.gridPosition, state.map, occupants);
  if (los.status === LOS_BLOCKED || los.targetUsingWallCover) {
    return -1;
  }
  const dist = euclidean(shooter.gridPosition, target.gridPosition);
  let score = AUTO_BASE - dist * AUTO_DIST;
  if (los.coverType === COVER_NONE) {
    score += AUTO_CLEAR;
  } else if (los.coverType === COVER_MODERATE) {
    score -= AUTO_MOD;
  } else if (los.coverType === COVER_COMPLETE) {
    score -= AUTO_COMPLETE;
  }
  if (target.isMoving) {
    score += AUTO_MOVING;
  }
  if (target.positionState === POSITION_DOWN) {
    score -= AUTO_PRONE;
  }
  const aim = faceToward(shooter.gridPosition, target.gridPosition);
  if (aim.x === shooter.facing.x && aim.y === shooter.facing.y) {
    score += AUTO_FACING;
  }
  return score;
}

export function isAutoTargetValid(shooter: SoldierState, target: SoldierState, state: GameState): boolean {
  if (!isPriorityTrackable(shooter, target, state)) {
    return false;
  }
  if (euclidean(shooter.gridPosition, target.gridPosition) > WEAPON_RANGE_TILES) {
    return false;
  }
  const los = evaluate(shooter.gridPosition, target.gridPosition, state.map, state.losOccupants());
  return los.status !== LOS_BLOCKED && !los.targetUsingWallCover;
}

export function findBestAutoTarget(state: GameState, shooter: SoldierState): SoldierState | null {
  if (shooter.isDead) {
    return null;
  }
  let best: SoldierState | null = null;
  let bestScore = Number.NEGATIVE_INFINITY;
  for (const enemy of state.soldiers) {
    if (enemy.teamId === shooter.teamId || enemy.isDead) {
      continue;
    }
    if (!state.perception.isVisibleToTeam(shooter.teamId, enemy.teamId, enemy.soldierId)) {
      continue;
    }
    if (euclidean(shooter.gridPosition, enemy.gridPosition) > WEAPON_RANGE_TILES) {
      continue;
    }
    const score = scoreAutoTarget(shooter, enemy, state);
    if (score < 0) {
      continue;
    }
    if (score > bestScore) {
      bestScore = score;
      best = enemy;
    }
  }
  return best;
}

function faceToward(from: Vec2i, to: Vec2i): Vec2i {
  const dx = Math.max(-1, Math.min(1, to.x - from.x));
  const dy = Math.max(-1, Math.min(1, to.y - from.y));
  if (dx === 0 && dy === 0) {
    return { x: 0, y: 0 };
  }
  return { x: dx, y: dy };
}
