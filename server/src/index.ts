import { WebSocketServer, WebSocket, type RawData } from "ws";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve, extname, join } from "node:path";
import { existsSync, realpathSync } from "node:fs";
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
  bothSidesAssigned,
  getAssignedClients,
  getClient,
  getClientByUserId,
  getTeamSize,
  parseSideName,
  registerClient,
  removeClient,
  requestSide,
  resetSides,
  setClientUserId,
  setTeamSize,
  sideCount,
} from "./side_ownership";
import { recordMatchResult, recordPlayerResult, distributeCoPP, checkBan, setActiveMatch, clearActiveMatch } from "./supabase_client";
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
  END_CAUSE_FORFEIT,
} from "./scenario_rules";

const PORT = parseInt(process.env.PORT ?? "3000", 10);
let match = new LocalMatch();
wireMatchCallbacks(match);

/** Called by the match callback when a match ends. Records results in Supabase. */
function handleMatchEnded(info: MatchEndedInfo): void {
  const usaUserIds: string[] = [];
  const germanyUserIds: string[] = [];

  for (const [clientId, teamId] of info.clientTeams) {
    const record = getClient(clientId);
    if (!record?.userId) continue;
    if (teamId === TEAM_USA) usaUserIds.push(record.userId);
    if (teamId === TEAM_GERMANY) germanyUserIds.push(record.userId);
  }

  if (usaUserIds.length === 0 || germanyUserIds.length === 0) {
    console.log("[MatchEnd] Skipping result recording: missing authenticated player(s). USA=%s GERMANY=%s",
      usaUserIds.join(",") || "(none)", germanyUserIds.join(",") || "(none)");
    return;
  }

  const isDraw = info.winner === WINNER_DRAW;
  const usaWon = info.winner === WINNER_USA;
  const germanyWon = info.winner === WINNER_GERMANY;

  const endCauseStr = info.endCause === END_CAUSE_FORFEIT ? "forfeit"
    : info.endCause === END_CAUSE_EXTERMINATION ? "extermination" : "time";

  const usaPP = info.usaPPEarned;
  const germanyPP = info.germanyPPEarned;
  const currentTeamSize = getTeamSize();

  console.log("[MatchEnd] cause=%s winner=%d teamSize=%d PP: USA=%d GERMANY=%d userIds: USA=[%s] GERMANY=[%s]",
    endCauseStr, info.winner, currentTeamSize, usaPP, germanyPP,
    usaUserIds.join(","), germanyUserIds.join(","));

  if (currentTeamSize <= 1 && usaUserIds.length === 1 && germanyUserIds.length === 1) {
    // 1v1: use the existing paired RPC for backward compatibility.
    recordMatchResult({
      matchId: info.matchId,
      player1Id: usaUserIds[0],
      player1Team: "USA",
      player1Won: usaWon,
      player1Draw: isDraw,
      player1Kill: info.usaKillPoints,
      player1Terrain: info.usaTerrainPoints,
      player1Total: info.usaTotalPoints,
      player1Kills: info.usaKills,
      player1Pp: usaPP,
      player2Id: germanyUserIds[0],
      player2Team: "GERMANY",
      player2Won: germanyWon,
      player2Draw: isDraw,
      player2Kill: info.germanyKillPoints,
      player2Terrain: info.germanyTerrainPoints,
      player2Total: info.germanyTotalPoints,
      player2Kills: info.germanyKills,
      player2Pp: germanyPP,
      endCause: endCauseStr,
    }).then(() => {
      return Promise.all([
        distributeCoPP(info.matchId, usaUserIds[0], usaPP),
        distributeCoPP(info.matchId, germanyUserIds[0], germanyPP),
      ]);
    }).catch((err) => {
      console.error("[MatchEnd] Failed to record result:", err);
    });
  } else {
    // Team game: record each player individually. Each player on a team
    // gets the full team PP (kills and terrain are team-wide for now).
    const promises: Promise<void>[] = [];
    for (const uid of usaUserIds) {
      const opponentId = germanyUserIds[0] ?? null;
      promises.push(recordPlayerResult({
        matchId: info.matchId,
        playerId: uid,
        team: "USA",
        won: usaWon,
        draw: isDraw,
        kills: info.usaKills,
        killPoints: info.usaKillPoints,
        terrainPoints: info.usaTerrainPoints,
        totalPoints: info.usaTotalPoints,
        endCause: endCauseStr,
        opponentId: opponentId,
        pp: usaPP,
      }));
      promises.push(distributeCoPP(info.matchId, uid, usaPP));
    }
    for (const uid of germanyUserIds) {
      const opponentId = usaUserIds[0] ?? null;
      promises.push(recordPlayerResult({
        matchId: info.matchId,
        playerId: uid,
        team: "GERMANY",
        won: germanyWon,
        draw: isDraw,
        kills: info.germanyKills,
        killPoints: info.germanyKillPoints,
        terrainPoints: info.germanyTerrainPoints,
        totalPoints: info.germanyTotalPoints,
        endCause: endCauseStr,
        opponentId: opponentId,
        pp: germanyPP,
      }));
      promises.push(distributeCoPP(info.matchId, uid, germanyPP));
    }
    Promise.all(promises).catch((err) => {
      console.error("[MatchEnd] Failed to record team result:", err);
    });
  }
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
    setTeamSize(1);
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

// Track which userIds are admins or moderators (set on hello, used for kick validation)
const adminUserIds = new Set<string>();
const moderatorUserIds = new Set<string>();

async function handleMessage(ws: WebSocket, clientId: string, raw: string): Promise<void> {
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
        // Check if the user is banned before allowing them in
        const banReason = await checkBan(userId);
        if (banReason !== null) {
          console.log("Banned user %s (%s) rejected: %s", userId, clientName, banReason);
          sendJson(ws, { type: "banned", reason: banReason });
          ws.close();
          return;
        }

        setClientUserId(clientId, userId);
        console.log("Authenticated user %s (%s)", userId, clientName);

        // Track active match in Supabase so the admin panel can see who's in a game
        setActiveMatch(userId, MATCH_ID);

        // Track admin/moderator status if the client reports it (validated server-side for kicks)
        if (message.isAdmin === true) {
          adminUserIds.add(userId);
        }
        if (message.isModerator === true) {
          moderatorUserIds.add(userId);
        }
      } else {
        console.log("Auth token invalid for %s; continuing as guest.", clientName);
      }
    }

    const requestedMap = typeof message.mapId === "string" ? message.mapId : "";
    if (requestedMap !== "" && match.matchPhase === "created" && requestedMap !== match.gameState.map.mapId) {
      try {
        resetSides();
        match = new LocalMatch(requestedMap);
        wireMatchCallbacks(match);
        console.log("Map changed to %s by client request", requestedMap);
      } catch (err) {
        console.error("Failed to load requested map %s, keeping %s: %s", requestedMap, match.gameState.map.mapId, (err as Error).message);
      }
    }

    // Team size: first client to connect with a teamSize sets it.
    const requestedTeamSize = typeof message.teamSize === "number" ? message.teamSize : 0;
    if (requestedTeamSize > 0 && match.matchPhase === "created") {
      const supported = match.gameState.map.metadata.supportedTeamSizes;
      if (supported.includes(requestedTeamSize)) {
        setTeamSize(requestedTeamSize);
        console.log("Team size set to %d by client request", requestedTeamSize);
      } else {
        console.log("Requested team size %d not supported by map %s (supported: %s)",
          requestedTeamSize, match.gameState.map.mapId, supported.join(","));
      }
    }

    match.attachClient(clientId, ws);
    sendJson(ws, {
      type: "welcome",
      message: "Hello Godot client",
      clientId,
      matchId: MATCH_ID,
      userId,
      teamSize: getTeamSize(),
    });
    return;
  }

  // Admin: kick a player from the active game
  if (message.type === "kick_player") {
    const record = getClient(clientId);
    if (!record?.userId || (!adminUserIds.has(record.userId) && !moderatorUserIds.has(record.userId))) {
      sendJson(ws, { type: "kick_result", success: false, reason: "Not authorized" });
      return;
    }

    const targetUserId = typeof message.targetUserId === "string" ? message.targetUserId : "";
    const kickReason = typeof message.reason === "string" ? message.reason : "Kicked by admin";

    if (targetUserId === "") {
      sendJson(ws, { type: "kick_result", success: false, reason: "No target specified" });
      return;
    }

    const target = getClientByUserId(targetUserId);
    if (!target) {
      sendJson(ws, { type: "kick_result", success: false, reason: "Player not connected" });
      return;
    }

    // Moderators cannot kick admins; admins can kick anyone
    const kickerIsAdmin = adminUserIds.has(record.userId);
    if (!kickerIsAdmin && adminUserIds.has(targetUserId)) {
      sendJson(ws, { type: "kick_result", success: false, reason: "Cannot kick an admin" });
      return;
    }

    const kickerRole = kickerIsAdmin ? "Admin" : "Moderator";
    console.log("%s %s kicking player %s: %s", kickerRole, record.userId, targetUserId, kickReason);
    sendJson(target.ws, { type: "kicked", reason: kickReason });

    // Trigger forfeit BEFORE removing records so handleMatchEnded can look up
    // both players' userIds for PP recording.
    const kickedSide = target.assignedSide;
    const kickedWs = target.ws;
    if (kickedSide !== null && match.matchPhase === "running") {
      const kickedTeamId = sideToTeamId(kickedSide);
      console.log("Kicked player was on %s, ending match as forfeit.", kickedSide);
      match.forceEndMatchForfeit(kickedTeamId);
    }
    // Now clean up
    if (target.userId) {
      clearActiveMatch(target.userId);
      adminUserIds.delete(target.userId);
      moderatorUserIds.delete(target.userId);
    }
    match.removeClient(target.clientId);
    removeClient(target.clientId);

    // Delay socket close to let the kicked message arrive before the close frame
    setTimeout(() => { kickedWs.close(); }, 500);

    sendJson(ws, { type: "kick_result", success: true });
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
      usaCount: sideCount("USA"),
      germanyCount: sideCount("GERMANY"),
      teamSize: getTeamSize(),
    });

    // Wait until both sides are assigned before starting.
    if (bothSidesAssigned()) {
      for (const rec of getAssignedClients()) {
        sendJson(rec.ws, { type: "match_ready" });
        match.sendSnapshot(rec.ws);
      }
    }
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

// ── Static file serving ─────────────────────────────────────────────
const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css",
  ".js": "application/javascript",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".webp": "image/webp",
};

const WEBSITE_DIR = resolve(__dirname, "../../website/dist");
const hasWebsite = existsSync(WEBSITE_DIR);
if (hasWebsite) {
  console.log(`Serving website from ${WEBSITE_DIR}`);
} else {
  console.log(`No website directory at ${WEBSITE_DIR} — HTTP serves health check only`);
}

async function serveStatic(req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse) {
  const url = req.url ?? "/";

  if (url === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }

  if (!hasWebsite) {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }

  let filePath: string;
  if (url === "/" || url === "/index.html") {
    filePath = join(WEBSITE_DIR, "index.html");
  } else {
    filePath = join(WEBSITE_DIR, url);
  }

  try {
    const realPath = realpathSync(filePath);
    if (!realPath.startsWith(realpathSync(WEBSITE_DIR))) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }
  } catch {
    // File doesn't exist — fall through to SPA fallback
  }

  try {
    const data = await readFile(filePath);
    const ext = extname(filePath);
    const contentType = MIME_TYPES[ext] ?? "application/octet-stream";
    const cacheControl = ext === ".html" || ext === ""
      ? "no-cache"
      : "public, max-age=31536000, immutable";
    res.writeHead(200, { "Content-Type": contentType, "Cache-Control": cacheControl });
    res.end(data);
  } catch {
    // SPA fallback: serve index.html for client-side routing
    try {
      const indexData = await readFile(join(WEBSITE_DIR, "index.html"));
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
      res.end(indexData);
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Not Found");
    }
  }
}

// HTTP server handles website + health checks; WebSocket upgrades attach to it.
const httpServer = createServer(serveStatic);

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
    const record = getClient(clientId);
    // If this player had an assigned side and the match is running,
    // end the match as a forfeit BEFORE removing records so handleMatchEnded
    // can still look up both players' userIds for PP recording.
    const disconnectedSide = record?.assignedSide ?? null;
    if (disconnectedSide !== null && match.matchPhase === "running") {
      const disconnectedTeamId = sideToTeamId(disconnectedSide);
      console.log("Player on %s disconnected during match, ending as forfeit.", disconnectedSide);
      match.forceEndMatchForfeit(disconnectedTeamId);
    }
    // Now clean up the client record
    if (record?.userId) {
      clearActiveMatch(record.userId);
      adminUserIds.delete(record.userId);
      moderatorUserIds.delete(record.userId);
    }
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
