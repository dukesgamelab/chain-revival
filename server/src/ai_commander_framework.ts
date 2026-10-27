/**
 * Match-level AI orchestration. Runs on the authoritative server only.
 * Discovers AI-controlled teams, ticks AiCommanders, coordinates objectives,
 * and submits gameplay commands through the match's command handlers.
 *
 * Port of AiCommanderFramework.gd (no survival mode).
 */

import { AiCommander } from "./ai_commander";
import { AiTeamCoordinator } from "./ai_team_coordinator";
import { buildSnapshot } from "./ai_commander";
import type { GameState } from "./game_state";
import { findPath } from "./pathfinder";
import {
  executeMove,
  executeFace,
  executeFireAt,
  executeFireControl,
  executePosition,
} from "./action_resolver";
import { executeGrenade } from "./grenade_system";
import {
  TEAM_USA,
  TEAM_GERMANY,
  MATCH_ID,
  type Vec2i,
  type MoveCommandIntent,
  type FaceCommandIntent,
  type FireAtCommandIntent,
  type PositionCommandIntent,
  type GrenadeCommandIntent,
} from "./types";
import { resolveToConcrete } from "./ai_plan";

/** Think every N simulation ticks (4 @ 20 Hz = ~5 Hz per commander). */
const THINK_EVERY_N_TICKS = 4;
/** Cap A* calls per tick across all AI. */
const MAX_AI_PATHFINDS_PER_TICK = 8;
/** LRU path memo capacity. */
const PATH_MEMO_MAX = 96;

export interface AiFrameworkOptions {
  /** Which teams are AI-controlled. */
  aiTeams: number[];
  /** Plan ID per team (e.g. { 1: "attack_center", 2: "defend" }). */
  plans?: Record<number, string>;
}

export class AiCommanderFramework {
  private commanders: Map<number, AiCommander> = new Map();
  private coordinator = new AiTeamCoordinator();
  private tickCounter = 0;
  private enabled = true;
  private pathfindsRemaining = 0;
  private pathMemo: Map<string, Vec2i[]> = new Map();
  private pathMemoOrder: string[] = [];

  setup(state: GameState, options: AiFrameworkOptions): void {
    this.commanders.clear();
    this.coordinator.clear();
    this.tickCounter = 0;
    this.pathMemo.clear();
    this.pathMemoOrder = [];

    for (const teamId of options.aiTeams) {
      const planId = options.plans?.[teamId] ?? (teamId === TEAM_GERMANY ? "defend" : "attack_center");
      const resolved = resolveToConcrete(planId, state.rng);
      const commander = new AiCommander(teamId, teamId, resolved);
      this.commanders.set(teamId, commander);
    }
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  hasCommanders(): boolean {
    return this.commanders.size > 0;
  }

  /** Run one AI think cycle. Called from the match simulation tick. */
  tick(state: GameState): void {
    if (!this.enabled || this.commanders.size === 0) {
      return;
    }

    this.tickCounter += 1;

    // Determine which commanders think this tick (staggered).
    const thinkers: AiCommander[] = [];
    let slot = 0;
    for (const commander of this.commanders.values()) {
      if ((this.tickCounter + slot) % THINK_EVERY_N_TICKS === 0) {
        thinkers.push(commander);
      }
      slot += 1;
    }

    if (thinkers.length === 0) {
      return;
    }

    // One shared battlefield read for all thinkers.
    const thinkerTeamIds = thinkers.map((c) => c.teamId);
    const snapshot = buildSnapshot(state, thinkerTeamIds);

    // Shared A* budget.
    this.pathfindsRemaining = MAX_AI_PATHFINDS_PER_TICK;

    const budgetedFindPath = (from: Vec2i, to: Vec2i): Vec2i[] => {
      return this.budgetedFindPath(state, from, to);
    };

    const nowMsec = state.clock.getTicksMsec();

    for (const commander of thinkers) {
      const claimed = this.coordinator.claimedCellsFor(commander.teamId);

      const submitCommand = (command: Record<string, unknown>): { success: boolean } => {
        return this.submitCommand(state, commander.teamId, command);
      };

      const cell = commander.tick(
        state,
        budgetedFindPath,
        submitCommand,
        claimed,
        nowMsec,
        snapshot,
      );

      this.coordinator.setClaim(commander.teamId, cell);
    }

    this.coordinator.resolveDuplicateClaims(
      Array.from(this.commanders.values()),
    );
  }

  private budgetedFindPath(state: GameState, from: Vec2i, to: Vec2i): Vec2i[] {
    const key = `${from.x},${from.y}>${to.x},${to.y}`;

    const cached = this.pathMemo.get(key);
    if (cached !== undefined) {
      return cached.map((c) => ({ ...c }));
    }

    if (this.pathfindsRemaining <= 0) {
      return [];
    }
    this.pathfindsRemaining -= 1;

    const path = findPath(state.map, from, to);
    if (path.length > 0) {
      this.storePathMemo(key, path);
    }
    return path;
  }

  private storePathMemo(key: string, path: Vec2i[]): void {
    if (this.pathMemo.has(key)) {
      this.pathMemo.set(key, path.map((c) => ({ ...c })));
      return;
    }
    if (this.pathMemoOrder.length >= PATH_MEMO_MAX) {
      const oldest = this.pathMemoOrder.shift();
      if (oldest !== undefined) {
        this.pathMemo.delete(oldest);
      }
    }
    this.pathMemoOrder.push(key);
    this.pathMemo.set(key, path.map((c) => ({ ...c })));
  }

  private submitCommand(
    state: GameState,
    teamId: number,
    command: Record<string, unknown>,
  ): { success: boolean } {
    const type = command.type as string;

    switch (type) {
      case "move_command": {
        const intent: MoveCommandIntent = {
          type: "move_command",
          matchId: MATCH_ID,
          requestId: `ai-${teamId}-${Date.now()}`,
          teamId: Number(command.teamId),
          soldierId: Number(command.soldierId),
          targetCell: command.targetCell as Vec2i,
          scope: Number(command.scope ?? 0),
          movementMode: Number(command.movementMode ?? 0),
        };
        const result = executeMove(state, intent, teamId);
        return { success: result.moveOrders.length > 0 };
      }

      case "face_command": {
        const intent: FaceCommandIntent = {
          type: "face_command",
          matchId: MATCH_ID,
          requestId: `ai-${teamId}-${Date.now()}`,
          teamId: Number(command.teamId),
          soldierId: Number(command.soldierId),
          targetCell: command.targetCell as Vec2i,
          scope: Number(command.scope ?? 0),
          aimWorld: null,
        };
        const result = executeFace(state, intent, teamId);
        return { success: result.faceUpdates.length > 0 };
      }

      case "fire_at_command": {
        const intent: FireAtCommandIntent = {
          type: "fire_at_command",
          matchId: MATCH_ID,
          requestId: `ai-${teamId}-${Date.now()}`,
          teamId: Number(command.teamId),
          soldierId: Number(command.soldierId),
          targetTeamId: Number(command.targetTeamId ?? -1),
          targetSoldierId: Number(command.targetSoldierId ?? -1),
          scope: Number(command.scope ?? 0),
          targetCell: command.targetCell as Vec2i | undefined,
        };
        const result = executeFireAt(state, intent, teamId);
        return { success: result.targetUpdates.length > 0 };
      }

      case "grenade_command": {
        const intent: GrenadeCommandIntent = {
          type: "grenade_command",
          matchId: MATCH_ID,
          requestId: `ai-${teamId}-${Date.now()}`,
          teamId: Number(command.teamId),
          soldierId: Number(command.soldierId),
          targetCell: command.targetCell as Vec2i,
        };
        const result = executeGrenade(state, intent, teamId);
        return { success: result.success };
      }

      case "position_command": {
        const intent: PositionCommandIntent = {
          type: "position_command",
          matchId: MATCH_ID,
          requestId: `ai-${teamId}-${Date.now()}`,
          teamId: Number(command.teamId),
          soldierId: Number(command.soldierId),
          positionState: Number(command.positionState ?? 0),
        };
        const result = executePosition(state, intent, teamId);
        return { success: result.success };
      }

      default:
        return { success: false };
    }
  }
}
