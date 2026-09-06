/**
 * One local multiplayer match. Server owns GameState and the sim tick.
 */

import type { WebSocket } from "ws";
import {
  executeFace,
  executeMove,
  executePosition,
  processMovementTick,
  toFaceResultPayload,
  toMoveResultPayload,
  toPositionResultPayload,
} from "./action_resolver";
import { GameState } from "./game_state";
import { MapData } from "./map_data";
import {
  DEFAULT_MAP_ID,
  MATCH_ID,
  type FaceCommandIntent,
  type MoveCommandIntent,
  type PositionCommandIntent,
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
        stanceTransitionOrders: [],
        soldierUpdates: [],
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
        stanceTransitionOrders: [],
        soldierUpdates: [],
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

  handleFace(clientId: string, intent: FaceCommandIntent): void {
    const client = this.clients.get(clientId);
    if (client === undefined || client.teamId === null) {
      this.sendTo(clientId, {
        type: "face_result",
        matchId: this.matchId,
        requestId: intent.requestId,
        success: false,
        statusMessage: "Join a side before issuing orders.",
        faceUpdates: [],
      });
      return;
    }
    if (intent.matchId && intent.matchId !== this.matchId) {
      this.sendTo(clientId, {
        type: "face_result",
        matchId: this.matchId,
        requestId: intent.requestId,
        success: false,
        statusMessage: "Unknown match.",
        faceUpdates: [],
      });
      return;
    }
    const result = executeFace(this.gameState, intent, client.teamId);
    this.broadcast(toFaceResultPayload(this.matchId, intent.requestId, result));
    console.log(
      "Face %s team=%d soldier=%d success=%s",
      intent.requestId,
      client.teamId,
      intent.soldierId,
      result.success,
    );
  }

  handlePosition(clientId: string, intent: PositionCommandIntent): void {
    const client = this.clients.get(clientId);
    if (client === undefined || client.teamId === null) {
      this.sendTo(clientId, {
        type: "position_result",
        matchId: this.matchId,
        requestId: intent.requestId,
        success: false,
        statusMessage: "Join a side before issuing orders.",
        positionState: 0,
        movementHalts: [],
        stanceTransitionOrders: [],
        soldierUpdates: [],
      });
      return;
    }
    if (intent.matchId && intent.matchId !== this.matchId) {
      this.sendTo(clientId, {
        type: "position_result",
        matchId: this.matchId,
        requestId: intent.requestId,
        success: false,
        statusMessage: "Unknown match.",
        positionState: 0,
        movementHalts: [],
        stanceTransitionOrders: [],
        soldierUpdates: [],
      });
      return;
    }
    const result = executePosition(this.gameState, intent, client.teamId);
    this.broadcast(toPositionResultPayload(this.matchId, intent.requestId, result));
    console.log(
      "Position %s team=%d soldier=%d success=%s",
      intent.requestId,
      client.teamId,
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

function parseCell(value: unknown): Vec2i | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const cell = value as Record<string, unknown>;
  return {
    x: Number(cell.x ?? 0),
    y: Number(cell.y ?? 0),
  };
}

export function parseFaceIntent(message: Record<string, unknown>): FaceCommandIntent | null {
  const requestId = typeof message.requestId === "string" ? message.requestId : "";
  if (requestId.length === 0) {
    return null;
  }
  const targetCell = parseCell(message.targetCell);
  if (targetCell === null) {
    return null;
  }
  let aimWorld: Vec2i | null = null;
  if (message.aimWorld !== undefined && message.aimWorld !== null) {
    aimWorld = parseCell(message.aimWorld);
  }
  return {
    type: "face_command",
    matchId: typeof message.matchId === "string" ? message.matchId : MATCH_ID,
    requestId,
    teamId: Number(message.teamId ?? 0),
    soldierId: Number(message.soldierId ?? 0),
    targetCell,
    scope: Number(message.scope ?? 0),
    aimWorld,
  };
}

export function parsePositionIntent(message: Record<string, unknown>): PositionCommandIntent | null {
  const requestId = typeof message.requestId === "string" ? message.requestId : "";
  if (requestId.length === 0) {
    return null;
  }
  return {
    type: "position_command",
    matchId: typeof message.matchId === "string" ? message.matchId : MATCH_ID,
    requestId,
    teamId: Number(message.teamId ?? 0),
    soldierId: Number(message.soldierId ?? 0),
    positionState: Number(message.positionState ?? 0),
  };
}
