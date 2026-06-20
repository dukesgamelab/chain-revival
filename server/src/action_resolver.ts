import type { GameState } from "./game_state";
import type { CommandEnvelope } from "./commands/index";

/**
 * Placeholder for authoritative command resolution.
 * Godot ActionResolver is not ported yet.
 */

export interface ActionResult {
  accepted: boolean;
  reason?: string;
}

export class ActionResolver {
  constructor(private readonly gameState: GameState) {}

  resolve(_command: CommandEnvelope): ActionResult {
    return {
      accepted: false,
      reason: "ActionResolver not implemented",
    };
  }
}
