import type { FaceCommandIntent, MoveCommandIntent, PositionCommandIntent } from "../types";

export type CommandType =
  | "ping"
  | "hello"
  | "request_side"
  | "join_match"
  | "move_command"
  | "face_command"
  | "position_command";

export type CommandEnvelope =
  | MoveCommandIntent
  | FaceCommandIntent
  | PositionCommandIntent
  | { type: CommandType; [key: string]: unknown };

export function isCommandEnvelope(value: unknown): value is CommandEnvelope {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const record = value as Record<string, unknown>;
  return typeof record.type === "string";
}
