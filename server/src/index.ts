import { WebSocketServer, WebSocket, type RawData } from "ws";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import {
  LocalMatch,
  parseFaceIntent,
  parseFireAtIntent,
  parseFireControlIntent,
  parseGrenadeIntent,
  parseMoveIntent,
  parsePositionIntent,
  type MatchEndedInfo,
} from "./match";
import { getUserId } from "./supabase_auth";
import {
  getClient,
  parseSideName,
  registerClient,
  removeClient,
  requestSide,
  resetSides,
  setClientUserId,
} from "./side_ownership";
import { recordMatchResult } from "./supabase_client";
import {
  MATCH_ID,
  sideToTeamId,
  teamIdToSide,
  TEAM_USA,
  TEAM_GERMANY,
} from "./types";
import {
  WINNER_USA,
  WINNER_GERMANY,
  WINNER_DRAW,
  END_CAUSE_TIME_GONE,
  END_CAUSE_EXTERMINATION,
} from "./scenario_rules";

const PORT = parseInt(process.env.PORT ?? "3000", 10);
let match = new LocalMatch();
wireMatchCallbacks(match);

/** Called by the match callback when a match ends. Records results in Supabase. */
function handleMatchEnded(info: MatchEndedInfo): void {
  // Find the user IDs for each team from side_ownership
  let usaUserId: string | null = null;
  let germanyUserId: string | null = null;

  for (const [clientId, teamId] of info.clientTeams) {
    const record = getClient(clientId);
    if (!record?.userId) continue;
    if (teamId === TEAM_USA) usaUserId = record.userId;
    if (teamId === TEAM_GERMANY) germanyUserId = record.userId;
  }

  if (!usaUserId || !germanyUserId) {
    console.log("[MatchEnd] Skipping result recording: missing authenticated player(s). USA=%s GERMANY=%s",
      usaUserId ?? "(none)", germanyUserId ?? "(none)");
    return;
  }

  const isDraw = info.winner === WINNER_DRAW;
  const usaWon = info.winner === WINNER_USA;
  const germanyWon = info.winner === WINNER_GERMANY;

  const endCauseStr = info.endCause === END_CAUSE_EXTERMINATION ? "extermination" : "time";

  recordMatchResult({
    matchId: info.matchId,
    player1Id: usaUserId,
    player1Team: "USA",
    player1Won: usaWon,
    player1Draw: isDraw,
    player1Kill: info.usaKillPoints,
    player1Terrain: info.usaTerrainPoints,
    player1Total: info.usaTotalPoints,
    player1Kills: info.usaKills,
    player2Id: germanyUserId,
    player2Team: "GERMANY",
    player2Won: germanyWon,
    player2Draw: isDraw,
    player2Kill: info.germanyKillPoints,
    player2Terrain: info.germanyTerrainPoints,
    player2Total: info.germanyTotalPoints,
    player2Kills: info.germanyKills,
    endCause: endCauseStr,
  }).catch((err) => {
    console.error("[MatchEnd] Failed to record result:", err);
  });
}

/** Wire the match-ended callback on a fresh match instance. */
function wireMatchCallbacks(m: LocalMatch): void {
  m.onMatchEnded = handleMatchEnded;
}

/** Reset to a fresh match when the previous one has ended. */
function ensureFreshMatch(): void {
  if (match.matchPhase === "ended") {
    console.log("Previous match ended, creating a fresh match.");
    resetSides();
    match = new LocalMatch();
    wireMatchCallbacks(match);
  }
}

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
    ensureFreshMatch();
    const clientName =
      typeof message.clientName === "string" ? message.clientName : "Unknown client";
    console.log("Hello from %s (%s)", clientName, clientId);

    // Optional Supabase auth: if the client sends an authToken, verify it
    // and associate the user ID with this connection.  LAN play works
    // without a token.
    let userId: string | null = null;
    if (typeof message.authToken === "string" && message.authToken !== "") {
      userId = getUserId(message.authToken);
      if (userId !== null) {
        setClientUserId(clientId, userId);
        console.log("Authenticated user %s (%s)", userId, clientName);
      } else {
        console.log("Auth token invalid for %s; continuing as guest.", clientName);
      }
    }

    match.attachClient(clientId, ws);
    sendJson(ws, {
      type: "welcome",
      message: "Hello Godot client",
      clientId,
      matchId: MATCH_ID,
      userId,
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

const HOST = process.env.BIND_HOST ?? "0.0.0.0";

// HTTP server handles health checks; WebSocket upgrades attach to it.
const httpServer = createServer((_req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("ok");
});

const wss = new WebSocketServer({ server: httpServer });

httpServer.listen(PORT, HOST, () => {
  console.log(`Chain Revival multiplayer server running on ws://${HOST}:${PORT}`);
  console.log(`Authoritative match ${MATCH_ID} ready`);
  if (HOST === "0.0.0.0") {
    console.log("LAN enabled — other machines can connect using this PC's IP address.");
  }
});

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
