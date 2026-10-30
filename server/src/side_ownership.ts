import type { WebSocket } from "ws";

export type SideName = "USA" | "GERMANY";

export interface ClientRecord {
  ws: WebSocket;
  clientId: string;
  assignedSide: SideName | null;
  /** Supabase user ID, set when the client sends an authToken with hello. */
  userId: string | null;
}

/** How many players each side needs before the match can start. */
let teamSize = 1;

/** Ordered lists of client IDs assigned to each side. */
const sideSlots: Record<SideName, string[]> = {
  USA: [],
  GERMANY: [],
};

const clients = new Map<string, ClientRecord>();

export function setTeamSize(size: number): void {
  teamSize = Math.max(1, size);
}

export function getTeamSize(): number {
  return teamSize;
}

export function registerClient(ws: WebSocket, clientId: string): ClientRecord {
  const record: ClientRecord = { ws, clientId, assignedSide: null, userId: null };
  clients.set(clientId, record);
  return record;
}

export function setClientUserId(clientId: string, userId: string): void {
  const record = clients.get(clientId);
  if (record) {
    record.userId = userId;
  }
}

export function getClient(clientId: string): ClientRecord | undefined {
  return clients.get(clientId);
}

export function removeClient(clientId: string): void {
  const record = clients.get(clientId);
  if (record?.assignedSide) {
    const slots = sideSlots[record.assignedSide];
    const idx = slots.indexOf(clientId);
    if (idx !== -1) slots.splice(idx, 1);
    console.log("%s released (client %s disconnected), %d/%d on that side",
      record.assignedSide, clientId, slots.length, teamSize);
  }
  clients.delete(clientId);
}

export function resetSides(): void {
  sideSlots.USA = [];
  sideSlots.GERMANY = [];
  for (const [, record] of clients) {
    record.assignedSide = null;
  }
}

export function parseSideName(value: unknown): SideName | null {
  if (value === "USA" || value === "GERMANY") {
    return value;
  }
  return null;
}

export function requestSide(
  clientId: string,
  side: SideName,
): { ok: true; side: SideName } | { ok: false; reason: string } {
  const record = clients.get(clientId);
  if (!record) {
    return { ok: false, reason: "Unknown client" };
  }

  if (record.assignedSide === side) {
    return { ok: true, side };
  }

  const slots = sideSlots[side];
  if (slots.length >= teamSize && !slots.includes(clientId)) {
    return { ok: false, reason: "Side is full" };
  }

  // Remove from previous side if switching.
  if (record.assignedSide && record.assignedSide !== side) {
    const oldSlots = sideSlots[record.assignedSide];
    const oldIdx = oldSlots.indexOf(clientId);
    if (oldIdx !== -1) oldSlots.splice(oldIdx, 1);
  }

  record.assignedSide = side;
  if (!slots.includes(clientId)) {
    slots.push(clientId);
  }
  console.log("%s assigned to client %s (%d/%d on that side)", side, clientId, slots.length, teamSize);
  return { ok: true, side };
}

export function bothSidesAssigned(): boolean {
  return sideSlots.USA.length >= teamSize && sideSlots.GERMANY.length >= teamSize;
}

/** Return the number of players currently assigned to a side. */
export function sideCount(side: SideName): number {
  return sideSlots[side].length;
}

/** Find a client by Supabase user ID. Returns undefined if not found. */
export function getClientByUserId(userId: string): ClientRecord | undefined {
  for (const [, record] of clients) {
    if (record.userId === userId) return record;
  }
  return undefined;
}

/** Return the ClientRecord for each assigned side. */
export function getAssignedClients(): ClientRecord[] {
  const result: ClientRecord[] = [];
  for (const [, record] of clients) {
    if (record.assignedSide !== null) {
      result.push(record);
    }
  }
  return result;
}
