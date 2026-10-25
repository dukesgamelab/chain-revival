/**
 * AI objective data — port of ai_objective.gd.
 * Replaceable objective for an AI Commander. Map-agnostic cell + label.
 */

import type { Vec2i } from "./types";

export interface AiObjective {
  objectiveId: string;
  label: string;
  cell: Vec2i;
  /** sector | cover | retreat | hold | order | custom */
  kind: string;
  priority: number;
}

export function makeObjective(
  id: string,
  label: string,
  cell: Vec2i,
  kind = "sector",
  priority = 0,
): AiObjective {
  return {
    objectiveId: id,
    label,
    cell: { ...cell },
    kind,
    priority,
  };
}

export function isValid(obj: AiObjective | null): obj is AiObjective {
  if (obj === null) {
    return false;
  }
  return obj.cell.x > -900 && obj.objectiveId.length > 0;
}
