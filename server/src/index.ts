import { WebSocketServer, WebSocket, type RawData } from "ws";
import { randomUUID } from "node:crypto";
import {
  LocalMatch,
  parseFaceIntent,
  parseFireAtIntent,
  parseFireControlIntent,
  parseGrenadeIntent,
  parseMoveIntent,
  parsePositionIntent,
} from "./match";
import {
  parseSideName,
  registerClient,
  removeClient,
  requestSide,
} from "./side_ownership";
import { MATCH_ID, sideToTeamId } from "./types";

const PORT = 3000;
const match = new LocalMatch();

interface IncomingMessage {
  type?: string;
  [key: string]: unknown;
}

function safeParseJson(raw: string): IncomingMessage | null {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return null;
    }
    return parsed as IncomingMessage;
  } catch {
    return null;
  }
}

function sendJson(ws: WebSocket, payload: unknown): void {
  ws.send(JSON.stringify(payload));
}

function handleMessage(ws: WebSocket, clientId: string, raw: string): void {
  console.log("Received message:", raw);

  const message = safeParseJson(raw);
  if (message === null) {
    console.log("Message is not valid JSON object");
    return;
  }

  if (message.type === "ping") {
    sendJson(ws, { type: "pong", serverTime: Date.now() });
    return;
  }

  if (message.type === "hello") {
    const clientName =
      typeof message.clientName === "string" ? message.clientName : "Unknown client";
    console.log("Hello from %s (%s)", clientName, clientId);
    match.attachClient(clientId, ws);
    sendJson(ws, {
      type: "welcome",
      message: "Hello Godot client",
      clientId,
      matchId: MATCH_ID,
    });
    return;
  }

  if (message.type === "request_side") {
    const side = parseSideName(message.side);
    if (side === null) {
      sendJson(ws, { type: "side_denied", reason: "Invalid side" });
      return;
    }

    console.log("Client requested %s (%s)", side, clientId);
    const result = requestSide(clientId, side);
    if (!result.ok) {
      sendJson(ws, { type: "side_denied", reason: result.reason });
      return;
    }

    const teamId = sideToTeamId(result.side);
    match.setClientTeam(clientId, teamId);
    sendJson(ws, {
      type: "side_assigned",
      side: result.side,
      matchId: MATCH_ID,
      teamId,
    });
    match.sendSnapshot(ws);
    return;
  }

  if (message.type === "join_match") {
    match.attachClient(clientId, ws);
    match.sendSnapshot(ws);
    return;
  }

  if (message.type === "move_command") {
    const intent = parseMoveIntent(message);
    if (intent === null) {
      sendJson(ws, {
        type: "move_result",
        matchId: MATCH_ID,
        requestId: typeof message.requestId === "string" ? message.requestId : "",
        success: false,
        statusMessage: "Invalid move command.",
        moveOrders: [],
        movementHalts: [],
        stanceTransitionOrders: [],
        soldierUpdates: [],
      });
      return;
    }
    match.handleMove(clientId, intent);
    return;
  }

  if (message.type === "face_command") {
    const intent = parseFaceIntent(message);
    if (intent === null) {
      sendJson(ws, {
        type: "face_result",
        matchId: MATCH_ID,
        requestId: typeof message.requestId === "string" ? message.requestId : "",
        success: false,
        statusMessage: "Invalid face command.",
        faceUpdates: [],
      });
      return;
    }
    match.handleFace(clientId, intent);
    return;
  }

  if (message.type === "position_command") {
    const intent = parsePositionIntent(message);
    if (intent === null) {
      sendJson(ws, {
        type: "position_result",
        matchId: MATCH_ID,
        requestId: typeof message.requestId === "string" ? message.requestId : "",
        success: false,
        statusMessage: "Invalid position command.",
        positionState: 0,
        movementHalts: [],
        stanceTransitionOrders: [],
        soldierUpdates: [],
      });
      return;
    }
    match.handlePosition(clientId, intent);
    return;
  }

  if (message.type === "fire_control_command") {
    const intent = parseFireControlIntent(message);
    if (intent === null) {
      sendJson(ws, {
        type: "fire_control_result",
        matchId: MATCH_ID,
        requestId: typeof message.requestId === "string" ? message.requestId : "",
        success: false,
        statusMessage: "Invalid fire-control command.",
        syncFireAtUi: false,
        targetUpdates: [],
      });
      return;
    }
    match.handleFireControl(clientId, intent);
    return;
  }

  if (message.type === "fire_at_command") {
    const intent = parseFireAtIntent(message);
    if (intent === null) {
      sendJson(ws, {
        type: "fire_at_result",
        matchId: MATCH_ID,
        requestId: typeof message.requestId === "string" ? message.requestId : "",
        success: false,
        statusMessage: "Invalid Fire At command.",
        syncFireAtUi: false,
        movementHalts: [],
        faceUpdates: [],
        targetUpdates: [],
      });
      return;
    }
    match.handleFireAt(clientId, intent);
    return;
  }

  if (message.type === "grenade_command") {
    const intent = parseGrenadeIntent(message);
    if (intent === null) {
      sendJson(ws, {
        type: "grenade_result",
        matchId: MATCH_ID,
        requestId: typeof message.requestId === "string" ? message.requestId : "",
        success: false,
        statusMessage: "Invalid grenade command.",
        throwerTeamId: 0,
        throwerId: 0,
        targetCell: { x: 0, y: 0 },
        grenadeCount: 0,
        facing: { x: 0, y: 0 },
      });
      return;
    }
    match.handleGrenade(clientId, intent);
  }
}

const wss = new WebSocketServer({ port: PORT });

console.log(`Chain Revival local multiplayer server running on ws://localhost:${PORT}`);
console.log(`Authoritative match ${MATCH_ID} ready`);

wss.on("connection", (ws: WebSocket) => {
  const clientId = randomUUID();
  registerClient(ws, clientId);
  match.attachClient(clientId, ws);
  console.log("Client connected (%s)", clientId);

  ws.on("message", (data: RawData) => {
    handleMessage(ws, clientId, data.toString());
  });

  ws.on("close", () => {
    removeClient(clientId);
    match.removeClient(clientId);
    console.log("Client disconnected (%s)", clientId);
  });

  ws.on("error", (error: Error) => {
    console.error("WebSocket error (%s): %s", clientId, error.message);
  });
});

wss.on("error", (error: Error) => {
  console.error("Server error:", error.message);
});
