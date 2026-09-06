/**
 * Authoritative movement resolution — port of ActionResolver.execute_move /
 * process_movement_tick (movement slice only).
 */

import type { GameState } from "./game_state";
import { speedMultiplier, stepCostMsec } from "./movement_policy";
import { findPath } from "./pathfinder";
import type { SoldierState } from "./soldier_state";
import {
  MOVEMENT_CRAWL,
  MOVE_SCOPE_SQUAD,
  POSITION_DOWN,
  POSITION_UP,
  type MoveCommandIntent,
  type MoveOrderPayload,
  type MoveResultPayload,
  type MovementTickPayload,
  type Vec2i,
  chebyshev,
  vec,
  vecEq,
} from "./types";

export interface ActionResult {
  success: boolean;
  statusMessage: string;
  moveOrders: MoveOrderPayload[];
  movementHalts: Array<{ teamId: number; soldierId: number; snapCell: Vec2i }>;
  movementSteps: MovementTickPayload["movementSteps"];
  movementCompletions: MovementTickPayload["movementCompletions"];
}

export function fail(message: string): ActionResult {
  return {
    success: false,
    statusMessage: message,
    moveOrders: [],
    movementHalts: [],
    movementSteps: [],
    movementCompletions: [],
  };
}

export function executeMove(
  gameState: GameState,
  cmd: MoveCommandIntent,
  actingTeamId: number,
): ActionResult {
  if (cmd.teamId !== actingTeamId) {
    return fail("That soldier is not under your control.");
  }

  const target = gameState.map.clampToBounds(cmd.targetCell);
  if (!gameState.map.isWalkable(target)) {
    if (gameState.map.isBlocked(target)) {
      return fail("That tile is blocked.");
    }
    return fail("No path to that tile.");
  }

  if (cmd.scope === MOVE_SCOPE_SQUAD) {
    return executeSquadMove(gameState, cmd, target);
  }

  const soldier = gameState.getSoldier(cmd.teamId, cmd.soldierId);
  if (soldier === null) {
    return fail("Soldier unavailable.");
  }
  const resolved = resolveMoveOrder(soldier, cmd.movementMode, gameState.clock.getTicksMsec());
  if (resolved.rejected) {
    return fail(resolved.message);
  }
  standUpForLocomotion(soldier, resolved.mode);

  const result: ActionResult = {
    success: true,
    statusMessage: "",
    moveOrders: [],
    movementHalts: [],
    movementSteps: [],
    movementCompletions: [],
  };
  if (!assignMovePath(gameState, soldier, target, resolved.mode, result)) {
    if (vecEq(target, soldier.gridPosition)) {
      return fail("Soldier is already at that tile.");
    }
    return fail("No path to that tile.");
  }
  const modeLabel = movementLabel(resolved.mode);
  result.statusMessage = `Soldier ${cmd.soldierId} ${modeLabel} to (${target.x}, ${target.y})`;
  return result;
}

function executeSquadMove(
  gameState: GameState,
  cmd: MoveCommandIntent,
  squadTarget: Vec2i,
): ActionResult {
  const now = gameState.clock.getTicksMsec();
  const orderable: SoldierState[] = [];
  const notices: string[] = [];
  for (const soldier of gameState.soldiersOnTeam(cmd.teamId)) {
    const preview = resolveMoveOrder(soldier, cmd.movementMode, now);
    if (preview.rejected) {
      if (preview.message) {
        notices.push(preview.message);
      }
      continue;
    }
    orderable.push(soldier);
  }
  if (orderable.length === 0) {
    return fail(notices[0] ?? "No soldiers could move to that tile.");
  }

  const formationRefs = new Map<number, Vec2i>();
  for (const soldier of orderable) {
    formationRefs.set(soldier.soldierId, formationReferenceCell(soldier));
  }
  const anchor = orderable[0];
  const anchorPos = formationRefs.get(anchor.soldierId) as Vec2i;
  const result: ActionResult = {
    success: true,
    statusMessage: "",
    moveOrders: [],
    movementHalts: [],
    movementSteps: [],
    movementCompletions: [],
  };
  let leadPath: Vec2i[] = [];
  let leadStart = vec(-999, -999);
  let ordered = 0;

  for (const soldier of orderable) {
    const resolved = resolveMoveOrder(soldier, cmd.movementMode, now);
    standUpForLocomotion(soldier, resolved.mode);
    const memberRef = formationRefs.get(soldier.soldierId) as Vec2i;
    const offset = vec(memberRef.x - anchorPos.x, memberRef.y - anchorPos.y);
    const memberTarget = squadRelativeCell(gameState, squadTarget, offset);
    let assigned = false;
    if (leadPath.length > 0 && leadStart.x > -900) {
      assigned = assignTranslatedSquadPath(
        gameState,
        soldier,
        resolved.mode,
        leadPath,
        leadStart,
        memberTarget,
        result,
      );
    }
    if (!assigned) {
      assigned = assignMovePath(gameState, soldier, memberTarget, resolved.mode, result);
      if (assigned && leadPath.length === 0 && result.moveOrders.length > 0) {
        const last = result.moveOrders[result.moveOrders.length - 1];
        if (last.soldierId === soldier.soldierId) {
          leadPath = last.path.map((c) => ({ ...c }));
          if (leadPath.length > 0) {
            leadStart = leadPath[0];
          }
        }
      }
    }
    if (assigned) {
      ordered += 1;
    }
  }
  if (ordered === 0) {
    return fail(notices[0] ?? "No soldiers could move to that tile.");
  }
  result.statusMessage = `Fireteam moving to (${squadTarget.x}, ${squadTarget.y})`;
  return result;
}

function resolveMoveOrder(
  soldier: SoldierState,
  requestedMode: number,
  nowMsec: number,
): { mode: number; message: string; rejected: boolean } {
  if (soldier.isDead) {
    return { mode: requestedMode, message: "Soldier unavailable.", rejected: true };
  }
  if (soldier.isStunned(nowMsec)) {
    return {
      mode: requestedMode,
      message: "Soldier is stunned and cannot move.",
      rejected: true,
    };
  }
  return { mode: requestedMode, message: "", rejected: false };
}

function standUpForLocomotion(soldier: SoldierState, mode: number): void {
  if (mode === MOVEMENT_CRAWL) {
    return;
  }
  if (soldier.positionState === POSITION_DOWN) {
    soldier.positionState = POSITION_UP;
  }
}

function formationReferenceCell(soldier: SoldierState): Vec2i {
  if (soldier.isMoving && soldier.currentPath.length > 0) {
    return { ...soldier.currentPath[soldier.currentPath.length - 1] };
  }
  return { ...soldier.gridPosition };
}

function squadRelativeCell(gameState: GameState, base: Vec2i, offset: Vec2i): Vec2i {
  const cell = vec(base.x + offset.x, base.y + offset.y);
  if (gameState.map.isWalkable(cell)) {
    return cell;
  }
  const fallback = nearestWalkable(gameState, cell, 3);
  if (fallback !== null) {
    return fallback;
  }
  if (gameState.map.isWalkable(base)) {
    return base;
  }
  return cell;
}

function nearestWalkable(gameState: GameState, origin: Vec2i, radius: number): Vec2i | null {
  if (gameState.map.isWalkable(origin)) {
    return origin;
  }
  let best: Vec2i | null = null;
  let bestD = 999999;
  for (let dy = -radius; dy <= radius; dy += 1) {
    for (let dx = -radius; dx <= radius; dx += 1) {
      const cell = vec(origin.x + dx, origin.y + dy);
      if (!gameState.map.isWalkable(cell)) {
        continue;
      }
      const d = Math.abs(dx) + Math.abs(dy);
      if (d < bestD) {
        bestD = d;
        best = cell;
      }
    }
  }
  return best;
}

function assignMovePath(
  gameState: GameState,
  soldier: SoldierState,
  target: Vec2i,
  mode: number,
  result: ActionResult,
): boolean {
  if (soldier.isDead) {
    return false;
  }
  const start = soldier.gridPosition;
  if (vecEq(target, start) || !gameState.map.isWalkable(target)) {
    return false;
  }
  const path = findPath(gameState.map, start, target);
  if (path.length < 2) {
    return false;
  }
  for (let i = 1; i < path.length; i += 1) {
    if (gameState.map.isBlocked(path[i])) {
      return false;
    }
  }
  if (soldier.isMoving) {
    result.movementHalts.push({
      teamId: soldier.teamId,
      soldierId: soldier.soldierId,
      snapCell: { ...soldier.gridPosition },
    });
    soldier.clearPath();
  }
  soldier.movementMode = mode;
  const speedMult = speedMultiplier(mode);
  soldier.assignPath(path, speedMult);
  result.moveOrders.push({
    teamId: soldier.teamId,
    soldierId: soldier.soldierId,
    path: path.map((c) => ({ ...c })),
    speedMult,
  });
  return true;
}

function assignTranslatedSquadPath(
  gameState: GameState,
  soldier: SoldierState,
  mode: number,
  leadPath: Vec2i[],
  leadStart: Vec2i,
  memberTarget: Vec2i,
  result: ActionResult,
): boolean {
  if (soldier.isDead || leadPath.length === 0) {
    return false;
  }
  const start = soldier.gridPosition;
  const path: Vec2i[] = [];
  if (vecEq(start, leadStart)) {
    for (const cell of leadPath) {
      path.push({ ...cell });
    }
  } else {
    const dx = start.x - leadStart.x;
    const dy = start.y - leadStart.y;
    for (const cell of leadPath) {
      const step = vec(cell.x + dx, cell.y + dy);
      if (!vecEq(step, start) && !gameState.map.isWalkable(step)) {
        return false;
      }
      path.push(step);
    }
  }
  if (path.length === 0 || !vecEq(path[0], start)) {
    return false;
  }
  if (vecEq(path[path.length - 1], start)) {
    return false;
  }
  const end = path[path.length - 1];
  if (!vecEq(end, memberTarget) && gameState.map.isWalkable(memberTarget)) {
    const prev = path.length >= 2 ? path[path.length - 2] : start;
    if (chebyshev(prev, memberTarget) <= 1) {
      path[path.length - 1] = { ...memberTarget };
    }
  }
  if (!vecEq(path[path.length - 1], memberTarget)) {
    return false;
  }
  if (soldier.isMoving) {
    result.movementHalts.push({
      teamId: soldier.teamId,
      soldierId: soldier.soldierId,
      snapCell: { ...soldier.gridPosition },
    });
    soldier.clearPath();
  }
  soldier.movementMode = mode;
  const speedMult = speedMultiplier(mode);
  soldier.assignPath(path, speedMult);
  result.moveOrders.push({
    teamId: soldier.teamId,
    soldierId: soldier.soldierId,
    path: path.map((c) => ({ ...c })),
    speedMult,
  });
  return true;
}

export function processMovementTick(gameState: GameState): ActionResult {
  const result: ActionResult = {
    success: true,
    statusMessage: "",
    moveOrders: [],
    movementHalts: [],
    movementSteps: [],
    movementCompletions: [],
  };
  const tickMsec = gameState.clock.tickMsec();
  for (const soldier of gameState.soldiers) {
    if (soldier.isDead || !soldier.isMoving) {
      continue;
    }
    advanceSoldier(gameState, soldier, tickMsec, result);
  }
  return result;
}

function advanceSoldier(
  gameState: GameState,
  soldier: SoldierState,
  tickMsec: number,
  result: ActionResult,
): void {
  if (soldier.currentPath.length < 2 || soldier.pathIndex <= 0) {
    completeMove(soldier, result);
    return;
  }
  soldier.moveAccumMsec += tickMsec;
  while (soldier.isMoving && soldier.moveAccumMsec >= soldier.moveStepCostMsec) {
    soldier.moveAccumMsec -= soldier.moveStepCostMsec;
    const from = soldier.currentPath[soldier.pathIndex - 1];
    const to = soldier.currentPath[soldier.pathIndex];
    if (gameState.map.isBlocked(to)) {
      completeMove(soldier, result);
      return;
    }
    if (chebyshev(from, to) > 1) {
      completeMove(soldier, result);
      return;
    }
    const stepDelta = vec(to.x - from.x, to.y - from.y);
    soldier.gridPosition = { ...to };
    if (stepDelta.x !== 0 || stepDelta.y !== 0) {
      soldier.facing = {
        x: Math.max(-1, Math.min(1, stepDelta.x)),
        y: Math.max(-1, Math.min(1, stepDelta.y)),
      };
    }
    result.movementSteps.push({
      teamId: soldier.teamId,
      soldierId: soldier.soldierId,
      tile: { ...to },
      stepDelta,
    });
    soldier.pathIndex += 1;
    if (soldier.pathIndex >= soldier.currentPath.length) {
      completeMove(soldier, result);
      return;
    }
    soldier.moveStepCostMsec = stepCostMsec(
      soldier.currentPath[soldier.pathIndex - 1],
      soldier.currentPath[soldier.pathIndex],
      soldier.moveSpeedMult,
    );
  }
}

function completeMove(soldier: SoldierState, result: ActionResult): void {
  soldier.clearPath();
  result.movementCompletions.push({
    teamId: soldier.teamId,
    soldierId: soldier.soldierId,
  });
}

function movementLabel(mode: number): string {
  if (mode === 1) {
    return "walk";
  }
  if (mode === 2) {
    return "crawl";
  }
  return "run";
}

export function toMoveResultPayload(
  matchId: string,
  requestId: string,
  result: ActionResult,
): MoveResultPayload {
  return {
    type: "move_result",
    matchId,
    requestId,
    success: result.success,
    statusMessage: result.statusMessage,
    moveOrders: result.moveOrders,
    movementHalts: result.movementHalts,
  };
}
