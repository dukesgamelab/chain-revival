/**
 * Placeholder command types for future multiplayer routing.
 * Godot command classes are not ported yet.
 */

export type CommandType =
  | "ping"
  | "hello"
  | "move"
  | "face"
  | "fire"
  | "grenade"
  | "position";

export interface CommandEnvelope {
  type: CommandType;
  payload?: Record<string, unknown>;
}

export function isCommandEnvelope(value: unknown): value is CommandEnvelope {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const record = value as Record<string, unknown>;
  return typeof record.type === "string";
}
