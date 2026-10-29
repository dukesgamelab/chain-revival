import type { WebSocket } from "ws";

export type SideName = "USA" | "GERMANY";

export interface ClientRecord {
  ws: WebSocket;
  clientId: string;
  assignedSide: SideName | null;
  /** Supabase user ID, set when the client sends an authToken with hello. */
  userId: string | null;
}

const sideOwners: Record<SideName, string | null> = {
  USA: null,
  GERMANY: null,
};

const clients = new Map<string, ClientRecord>();

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
    sideOwners[record.assignedSide] = null;
    console.log("%s released (client %s disconnected)", record.assignedSide, clientId);
  }
  clients.delete(clientId);
}

export function resetSides(): void {
  sideOwners.USA = null;
  sideOwners.GERMANY = null;
  clients.clear();
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

  const ownerId = sideOwners[side];
  if (ownerId !== null && ownerId !== clientId) {
    return { ok: false, reason: "Side already taken" };
  }

  if (record.assignedSide && record.assignedSide !== side) {
    sideOwners[record.assignedSide] = null;
  }

  record.assignedSide = side;
  sideOwners[side] = clientId;
  console.log("%s assigned to client %s", side, clientId);
  return { ok: true, side };
}

export function bothSidesAssigned(): boolean {
  return sideOwners.USA !== null && sideOwners.GERMANY !== null;
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
