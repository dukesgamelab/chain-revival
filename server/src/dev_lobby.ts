/**
 * In-memory rooms for development guest play.
 * Nothing here is written to Supabase. The HTTP routes stay closed unless
 * ALLOW_DEV_GUESTS=1.
 */

import type { IncomingMessage, ServerResponse } from "node:http";

export const DEV_GUEST_ID_PATTERN = /^dev-guest-[A-Za-z0-9_-]{6,64}$/;
const ROOM_MIN = 1;
const ROOM_MAX = 16;
const TEAM_SIZES = [1, 2, 3, 5];
const MATCH_LENGTHS = [600, 900, 1200];
const MAP_ID_PATTERN = /^[a-zA-Z0-9_-]{1,40}$/;
const ONLINE_MS = 30_000;
const DROP_MS = 90_000;

export interface DevPlayer {
  id: string;
  display_name: string;
  side: "USA" | "GERMANY" | null;
  connected: boolean;
}

export interface DevPresence {
  id: string;
  display_name: string;
  connected: boolean;
  last_seen: number;
}

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
  players: DevPlayer[];
}

interface StoredRoom extends Omit<DevRoom, "guest_ids" | "current_players"> {
  players: DevPlayer[];
}

const rooms = new Map<number, StoredRoom>();
const presence = new Map<string, DevPresence>();

export function devGuestsAllowed(): boolean {
  return process.env.ALLOW_DEV_GUESTS === "1";
}

export function isValidDevGuestId(id: string): boolean {
  return DEV_GUEST_ID_PATTERN.test(id);
}

export function listDevRooms(now = Date.now()): DevRoom[] {
  sweepDevLobby(now);
  return [...rooms.values()].map(publicRoom);
}

export function listDevOnline(now = Date.now()): DevPresence[] {
  sweepDevLobby(now);
  return [...presence.values()].map((row) => ({ ...row }));
}

export function clearDevRooms(): void {
  rooms.clear();
}

export function clearDevLobbyState(): void {
  rooms.clear();
  presence.clear();
}

export function touchDevPresence(
  devGuestId: string,
  displayName: string,
  now = Date.now(),
): { ok: true } | { ok: false; error: string } {
  if (!isValidDevGuestId(devGuestId)) {
    return { ok: false, error: "Invalid dev guest id" };
  }
  presence.set(devGuestId, {
    id: devGuestId,
    display_name: cleanName(displayName),
    connected: true,
    last_seen: now,
  });
  sweepDevLobby(now);
  return { ok: true };
}

export function leaveDevPresence(devGuestId: string, now = Date.now()): { ok: true } | { ok: false; error: string } {
  if (!isValidDevGuestId(devGuestId)) {
    return { ok: false, error: "Invalid dev guest id" };
  }
  const row = presence.get(devGuestId);
  if (row) {
    row.connected = false;
    row.last_seen = now;
  }
  return { ok: true };
}

export function setDevPlayerSide(devGuestId: string, side: "USA" | "GERMANY"): void {
  if (!isValidDevGuestId(devGuestId)) return;
  for (const room of rooms.values()) {
    const player = room.players.find((entry) => entry.id === devGuestId);
    if (!player) continue;
    player.side = side;
    player.connected = true;
  }
}

export function setDevPlayerConnected(devGuestId: string, connected: boolean): void {
  if (!isValidDevGuestId(devGuestId)) return;
  for (const room of rooms.values()) {
    const player = room.players.find((entry) => entry.id === devGuestId);
    if (player) player.connected = connected;
  }
}

export function sweepDevLobby(now = Date.now()): void {
  for (const [id, row] of presence) {
    if (now - row.last_seen > DROP_MS) {
      presence.delete(id);
      continue;
    }
    if (now - row.last_seen > ONLINE_MS) {
      row.connected = false;
    }
  }
  for (const [roomNumber, room] of rooms) {
    const host = presence.get(room.host_id);
    const hostGone = room.status === "waiting" && host !== undefined && now - host.last_seen > DROP_MS;
    if (hostGone) {
      rooms.delete(roomNumber);
      continue;
    }
    if (room.status !== "waiting") continue;
    room.players = room.players.filter((player) => player.id === room.host_id || presenceOnline(player.id, now));
  }
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
}, now = Date.now()): { ok: true; room: DevRoom } | { ok: false; error: string } {
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
  const name = cleanName(input.displayName);
  const room: StoredRoom = {
    id: `dev-room-${input.roomNumber}`,
    host_id: input.devGuestId,
    host_display_name: name,
    match_name: cleanName(input.matchName),
    status: "waiting",
    team_size: input.teamSize,
    max_players: input.teamSize * 2,
    room_number: input.roomNumber,
    server_url: serverUrl,
    map_id: input.mapId,
    match_length_sec: input.matchLengthSec,
    players: [playerRow(input.devGuestId, name)],
  };
  rooms.set(input.roomNumber, room);
  touchDevPresence(input.devGuestId, name, now);
  return { ok: true, room: publicRoom(room) };
}

export function joinDevRoom(
  devGuestId: string,
  displayName: string,
  roomNumber: number,
  now = Date.now(),
): { ok: true; room: DevRoom } | { ok: false; error: string } {
  if (!isValidDevGuestId(devGuestId)) {
    return { ok: false, error: "Invalid dev guest id" };
  }
  const room = rooms.get(roomNumber);
  if (!room || room.status !== "waiting") {
    return { ok: false, error: "That room is not open" };
  }
  const existing = room.players.find((player) => player.id === devGuestId);
  if (existing) {
    existing.connected = true;
    existing.display_name = cleanName(displayName);
    touchDevPresence(devGuestId, displayName, now);
    return { ok: true, room: publicRoom(room) };
  }
  if (room.players.length >= room.max_players) {
    return { ok: false, error: "That room is full" };
  }
  dropGuest(devGuestId);
  const target = rooms.get(roomNumber);
  if (!target || target.status !== "waiting") {
    return { ok: false, error: "That room is not open" };
  }
  const name = cleanName(displayName);
  target.players.push(playerRow(devGuestId, name));
  if (target.players.length >= target.max_players) {
    target.status = "in_progress";
  }
  touchDevPresence(devGuestId, name, now);
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
  const routes = ["/dev/lobby", "/dev/lobby/host", "/dev/lobby/join", "/dev/lobby/leave", "/dev/lobby/presence", "/dev/lobby/presence/leave"];
  if (!routes.includes(url)) {
    return false;
  }
  if (!devGuestsAllowed()) {
    sendJson(res, 404, { error: "Not found" });
    return true;
  }
  if (url === "/dev/lobby" && req.method === "GET") {
    const now = Date.now();
    sendJson(res, 200, { rooms: listDevRooms(now), online: listDevOnline(now) });
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
  const displayName = typeof body.displayName === "string" ? body.displayName : "";
  if (url === "/dev/lobby/presence") {
    const result = touchDevPresence(devGuestId, displayName);
    sendJson(res, result.ok ? 200 : 400, result.ok ? { ok: true, online: listDevOnline() } : { error: result.error });
    return true;
  }
  if (url === "/dev/lobby/presence/leave") {
    const result = leaveDevPresence(devGuestId);
    sendJson(res, result.ok ? 200 : 400, result.ok ? { ok: true } : { error: result.error });
    return true;
  }
  if (url === "/dev/lobby/host") {
    const result = hostDevRoom({
      devGuestId,
      displayName,
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
    const result = joinDevRoom(devGuestId, displayName, Number(body.roomNumber));
    sendJson(res, result.ok ? 200 : 400, result.ok ? { room: result.room } : { error: result.error });
    return true;
  }
  const result = leaveDevRoom(devGuestId);
  sendJson(res, result.ok ? 200 : 400, result.ok ? { ok: true } : { error: result.error });
  return true;
}

function playerRow(id: string, displayName: string): DevPlayer {
  return { id, display_name: displayName, side: null, connected: true };
}

function presenceOnline(id: string, now: number): boolean {
  const row = presence.get(id);
  return row !== undefined && row.connected && now - row.last_seen <= ONLINE_MS;
}

function dropGuest(devGuestId: string): void {
  for (const [roomNumber, room] of rooms) {
    const player = room.players.find((entry) => entry.id === devGuestId);
    if (!player) continue;
    if (room.status === "in_progress") {
      player.connected = false;
      continue;
    }
    if (room.host_id === devGuestId) {
      rooms.delete(roomNumber);
      continue;
    }
    room.players = room.players.filter((entry) => entry.id !== devGuestId);
  }
}

function publicRoom(room: StoredRoom): DevRoom {
  return {
    ...room,
    current_players: room.players.length,
    guest_ids: room.players.map((player) => player.id),
    players: room.players.map((player) => ({ ...player })),
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
