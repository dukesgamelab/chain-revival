/**
 * One local multiplayer match. Server owns GameState and the sim tick.
 */

import type { WebSocket } from "ws";
import { executeMove, processMovementTick, toMoveResultPayload } from "./action_resolver";
import { GameState } from "./game_state";
import { MapData } from "./map_data";
import {
  DEFAULT_MAP_ID,
  MATCH_ID,
  type MoveCommandIntent,
  type Vec2i,
} from "./types";

export interface MatchClient {
  clientId: string;
  ws: WebSocket;
  teamId: number | null;
}

export class LocalMatch {
  readonly matchId = MATCH_ID;
  readonly gameState: GameState;
  private readonly clients = new Map<string, MatchClient>();
  private tickTimer: NodeJS.Timeout | null = null;

  constructor(mapId = DEFAULT_MAP_ID) {
    const map = MapData.loadFromRepo(mapId);
    this.gameState = new GameState(map);
    this.startTick();
    console.log(
      "Match %s created map=%s soldiers=%d",
      this.matchId,
      map.mapId,
      this.gameState.soldiers.length,
    );
  }

  attachClient(clientId: string, ws: WebSocket): void {
    this.clients.set(clientId, { clientId, ws, teamId: null });
  }

  setClientTeam(clientId: string, teamId: number): void {
    const client = this.clients.get(clientId);
    if (client !== undefined) {
      client.teamId = teamId;
    }
  }

  removeClient(clientId: string): void {
    this.clients.delete(clientId);
  }

  sendSnapshot(ws: WebSocket): void {
    ws.send(JSON.stringify(this.gameState.getSnapshot()));
  }

  handleMove(clientId: string, intent: MoveCommandIntent): void {
    const client = this.clients.get(clientId);
    if (client === undefined || client.teamId === null) {
      this.sendTo(clientId, {
        type: "move_result",
        matchId: this.matchId,
        requestId: intent.requestId,
        success: false,
        statusMessage: "Join a side before issuing orders.",
        moveOrders: [],
        movementHalts: [],
      });
      return;
    }
    if (intent.matchId && intent.matchId !== this.matchId) {
      this.sendTo(clientId, {
        type: "move_result",
        matchId: this.matchId,
        requestId: intent.requestId,
        success: false,
        statusMessage: "Unknown match.",
        moveOrders: [],
        movementHalts: [],
      });
      return;
    }

    const result = executeMove(this.gameState, intent, client.teamId);
    const payload = toMoveResultPayload(this.matchId, intent.requestId, result);
    this.broadcast(payload);
    console.log(
      "Move %s team=%d soldier=%d success=%s",
      intent.requestId,
      intent.teamId,
      intent.soldierId,
      result.success,
    );
  }

  private startTick(): void {
    const period = this.gameState.clock.tickMsec();
    this.tickTimer = setInterval(() => {
      this.gameState.clock.advanceTick();
      const tick = processMovementTick(this.gameState);
      if (tick.movementSteps.length === 0 && tick.movementCompletions.length === 0) {
        return;
      }
      this.broadcast({
        type: "movement_tick",
        matchId: this.matchId,
        simMsec: this.gameState.clock.getTicksMsec(),
        movementSteps: tick.movementSteps,
        movementCompletions: tick.movementCompletions,
      });
    }, period);
    this.tickTimer.unref?.();
  }

  private sendTo(clientId: string, payload: unknown): void {
    const client = this.clients.get(clientId);
    if (client !== undefined && client.ws.readyState === client.ws.OPEN) {
      client.ws.send(JSON.stringify(payload));
    }
  }

  private broadcast(payload: unknown): void {
    const text = JSON.stringify(payload);
    for (const client of this.clients.values()) {
      if (client.ws.readyState === client.ws.OPEN) {
        client.ws.send(text);
      }
    }
  }
}

export function parseMoveIntent(message: Record<string, unknown>): MoveCommandIntent | null {
  const requestId = typeof message.requestId === "string" ? message.requestId : "";
  if (requestId.length === 0) {
    return null;
  }
  const target = message.targetCell;
  if (typeof target !== "object" || target === null) {
    return null;
  }
  const cell = target as Record<string, unknown>;
  const targetCell: Vec2i = {
    x: Number(cell.x ?? 0),
    y: Number(cell.y ?? 0),
  };
  return {
    type: "move_command",
    matchId: typeof message.matchId === "string" ? message.matchId : MATCH_ID,
    requestId,
    teamId: Number(message.teamId ?? 0),
    soldierId: Number(message.soldierId ?? 0),
    targetCell,
    scope: Number(message.scope ?? 0),
    movementMode: Number(message.movementMode ?? 0),
  };
}
