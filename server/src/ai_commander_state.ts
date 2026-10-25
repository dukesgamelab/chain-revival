/**
 * AI Commander state machine states — port of ai_commander_state.gd.
 */

export const PLAN = "plan";
export const MOVE = "move";
export const CONTACT = "contact";
export const FIGHT = "fight";
export const ADVANCE = "advance";
export const OBJECTIVE_COMPLETE = "objective_complete";

export type AiState =
  | typeof PLAN
  | typeof MOVE
  | typeof CONTACT
  | typeof FIGHT
  | typeof ADVANCE
  | typeof OBJECTIVE_COMPLETE;

export function displayName(stateId: string): string {
  switch (stateId) {
    case PLAN:
      return "PLAN";
    case MOVE:
      return "MOVE";
    case CONTACT:
      return "CONTACT";
    case FIGHT:
      return "FIGHT";
    case ADVANCE:
      return "ADVANCE";
    case OBJECTIVE_COMPLETE:
      return "OBJECTIVE COMPLETE";
    default:
      return stateId.toUpperCase();
  }
}
