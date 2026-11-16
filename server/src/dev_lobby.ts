/**
 * In-memory rooms for development guest play.
 * Nothing here is written to Supabase. The HTTP routes stay closed unless
 * ALLOW_DEV_GUESTS=1.
 */

import type { IncomingMessage, ServerResponse } from "node:http";

export const DEV_GUEST_ID_PATTERN = /^dev-guest-[A-Za-z0-9_-]{6,64}$/;
const ROOM_MIN = 1;
const ROOM_MAX = 16;
const TEAM_SIZES = [1, 2, 4];
const MATCH_LENGTHS = [600, 900, 1200];
const MAP_ID_PATTERN = /^[a-zA-Z0-9_-]{1,40}$/;

export interface DevRoom {
  id: string;
  host_id: string;
  host_display_name: string;
  match_name: string;
  status: "waiting" | "in_progress";
  current_players: number;
  team_size: number;
  max_players: number;
  room_number: number;
  server_url: string;
  map_id: string;
  match_length_sec: number;
  guest_ids: string[];
}

const rooms = new Map<number, DevRoom>();

export function devGuestsAllowed(): boolean {
  return process.env.ALLOW_DEV_GUESTS === "1";
}

export function isValidDevGuestId(id: string): boolean {
  return DEV_GUEST_ID_PATTERN.test(id);
}

export function listDevRooms(): DevRoom[] {
  return [...rooms.values()].map(publicRoom);
}

export function clearDevRooms(): void {
  rooms.clear();
}

export function hostDevRoom(input: {
  devGuestId: string;
  displayName: string;
  roomNumber: number;
  matchName: string;
  mapId: string;
  teamSize: number;
  matchLengthSec: number;
  serverUrl: string;
}): { ok: true; room: DevRoom } | { ok: false; error: string } {
  if (!isValidDevGuestId(input.devGuestId)) {
    return { ok: false, error: "Invalid dev guest id" };
  }
  if (!Number.isInteger(input.roomNumber) || input.roomNumber < ROOM_MIN || input.roomNumber > ROOM_MAX) {
    return { ok: false, error: "Invalid room" };
  }
  if (!TEAM_SIZES.includes(input.teamSize)) {
    return { ok: false, error: "Invalid team size" };
  }
  if (!MATCH_LENGTHS.includes(input.matchLengthSec)) {
    return { ok: false, error: "Invalid match length" };
  }
  if (!MAP_ID_PATTERN.test(input.mapId)) {
    return { ok: false, error: "Invalid map" };
  }
  const serverUrl = cleanServerUrl(input.serverUrl);
  if (serverUrl === null) {
    return { ok: false, error: "Invalid server URL" };
  }
  dropGuest(input.devGuestId);
  const room: DevRoom = {
    id: `dev-room-${input.roomNumber}`,
    host_id: input.devGuestId,
    host_display_name: cleanName(input.displayName),
    match_name: cleanName(input.matchName),
    status: "waiting",
    current_players: 1,
    team_size: input.teamSize,
    max_players: input.teamSize * 2,
    room_number: input.roomNumber,
    server_url: serverUrl,
    map_id: input.mapId,
    match_length_sec: input.matchLengthSec,
    guest_ids: [input.devGuestId],
  };
  rooms.set(input.roomNumber, room);
  return { ok: true, room: publicRoom(room) };
}

export function joinDevRoom(devGuestId: string, displayName: string, roomNumber: number): { ok: true; room: DevRoom } | { ok: false; error: string } {
  if (!isValidDevGuestId(devGuestId)) {
    return { ok: false, error: "Invalid dev guest id" };
  }
  const room = rooms.get(roomNumber);
  if (!room || room.status !== "waiting") {
    return { ok: false, error: "That room is not open" };
  }
  if (room.guest_ids.includes(devGuestId)) {
    return { ok: true, room: publicRoom(room) };
  }
  if (room.current_players >= room.max_players) {
    return { ok: false, error: "That room is full" };
  }
  dropGuest(devGuestId);
  const target = rooms.get(roomNumber);
  if (!target || target.status !== "waiting") {
    return { ok: false, error: "That room is not open" };
  }
  target.guest_ids.push(devGuestId);
  target.current_players = target.guest_ids.length;
  if (target.current_players >= target.max_players) {
    target.status = "in_progress";
  }
  if (displayName.trim() !== "" && target.host_display_name === "") {
    target.host_display_name = cleanName(displayName);
  }
  return { ok: true, room: publicRoom(target) };
}

export function leaveDevRoom(devGuestId: string): { ok: true } | { ok: false; error: string } {
  if (!isValidDevGuestId(devGuestId)) {
    return { ok: false, error: "Invalid dev guest id" };
  }
  dropGuest(devGuestId);
  return { ok: true };
}

export async function handleDevLobbyHttp(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
  const url = (req.url ?? "").split("?")[0];
  if (url !== "/dev/lobby" && url !== "/dev/lobby/host" && url !== "/dev/lobby/join" && url !== "/dev/lobby/leave") {
    return false;
  }
  if (!devGuestsAllowed()) {
    sendJson(res, 404, { error: "Not found" });
    return true;
  }
  if (url === "/dev/lobby" && req.method === "GET") {
    sendJson(res, 200, { rooms: listDevRooms() });
    return true;
  }
  if (req.method !== "POST") {
    sendJson(res, 405, { error: "Method not allowed" });
    return true;
  }
  const body = await readJson(req);
  if (body === null) {
    sendJson(res, 400, { error: "Expected JSON" });
    return true;
  }
  const devGuestId = typeof body.devGuestId === "string" ? body.devGuestId : "";
  if (url === "/dev/lobby/host") {
    const result = hostDevRoom({
      devGuestId,
      displayName: typeof body.displayName === "string" ? body.displayName : "",
      roomNumber: Number(body.roomNumber),
      matchName: typeof body.matchName === "string" ? body.matchName : "",
      mapId: typeof body.mapId === "string" ? body.mapId : "",
      teamSize: Number(body.teamSize),
      matchLengthSec: Number(body.matchLengthSec),
      serverUrl: typeof body.serverUrl === "string" ? body.serverUrl : "",
    });
    sendJson(res, result.ok ? 200 : 400, result.ok ? { room: result.room } : { error: result.error });
    return true;
  }
  if (url === "/dev/lobby/join") {
    const result = joinDevRoom(devGuestId, typeof body.displayName === "string" ? body.displayName : "", Number(body.roomNumber));
    sendJson(res, result.ok ? 200 : 400, result.ok ? { room: result.room } : { error: result.error });
    return true;
  }
  const result = leaveDevRoom(devGuestId);
  sendJson(res, result.ok ? 200 : 400, result.ok ? { ok: true } : { error: result.error });
  return true;
}

function dropGuest(devGuestId: string): void {
  for (const [roomNumber, room] of rooms) {
    if (!room.guest_ids.includes(devGuestId)) {
      continue;
    }
    if (room.host_id === devGuestId) {
      rooms.delete(roomNumber);
      continue;
    }
    room.guest_ids = room.guest_ids.filter((id) => id !== devGuestId);
    room.current_players = room.guest_ids.length;
    if (room.status === "in_progress") {
      room.status = "waiting";
    }
  }
}

function publicRoom(room: DevRoom): DevRoom {
  return {
    ...room,
    guest_ids: [...room.guest_ids],
  };
}

function cleanName(value: string): string {
  const trimmed = value.replace(/[\u0000-\u001f]/g, "").trim();
  return trimmed.slice(0, 40) || "Guest";
}

function cleanServerUrl(value: string): string | null {
  const trimmed = value.trim();
  if (/^wss?:\/\/[A-Za-z0-9._:-]{1,200}$/.test(trimmed)) {
    return trimmed;
  }
  return null;
}

function sendJson(res: ServerResponse, status: number, payload: unknown): void {
  const body = JSON.stringify(payload);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) });
  res.end(body);
}

function readJson(req: IncomingMessage): Promise<Record<string, unknown> | null> {
  return new Promise((resolvePromise) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > 8192) {
        resolvePromise(null);
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
        if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
          resolvePromise(parsed as Record<string, unknown>);
          return;
        }
      } catch {
        /* fall through */
      }
      resolvePromise(null);
    });
    req.on("error", () => resolvePromise(null));
  });
}
