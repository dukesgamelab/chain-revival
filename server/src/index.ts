import { WebSocketServer, WebSocket, type RawData } from "ws";
import { randomUUID } from "node:crypto";
import {
  parseSideName,
  registerClient,
  removeClient,
  requestSide,
} from "./side_ownership";

const PORT = 3000;

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
    sendJson(ws, {
      type: "welcome",
      message: "Hello Godot client",
      clientId,
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

    sendJson(ws, { type: "side_assigned", side: result.side });
  }
}

const wss = new WebSocketServer({ port: PORT });

console.log(`Chain Revival local multiplayer server running on ws://localhost:${PORT}`);

wss.on("connection", (ws: WebSocket) => {
  const clientId = randomUUID();
  registerClient(ws, clientId);
  console.log("Client connected (%s)", clientId);

  ws.on("message", (data: RawData) => {
    handleMessage(ws, clientId, data.toString());
  });

  ws.on("close", () => {
    removeClient(clientId);
    console.log("Client disconnected (%s)", clientId);
  });

  ws.on("error", (error: Error) => {
    console.error("WebSocket error (%s): %s", clientId, error.message);
  });
});

wss.on("error", (error: Error) => {
  console.error("Server error:", error.message);
});
