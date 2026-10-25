/**
 * Soft multi-AI coordination — port of ai_team_coordinator.gd.
 * Tracks claimed objectives per player, nudges duplicates to replan.
 */

import type { Vec2i } from "./types";

/** Minimal interface for a commander that can be asked to replan. */
export interface ReplanTarget {
  playerId: number;
  requestReplan(reason: string): void;
}

export class AiTeamCoordinator {
  private readonly claims = new Map<number, Vec2i>();

  clear(): void {
    this.claims.clear();
  }

  /** All claimed cells except this player's own. */
  claimedCellsFor(playerId: number): Vec2i[] {
    const out: Vec2i[] = [];
    for (const [pid, cell] of this.claims) {
      if (pid === playerId) {
        continue;
      }
      if (cell.x > -900) {
        out.push({ ...cell });
      }
    }
    return out;
  }

  setClaim(playerId: number, cell: Vec2i): void {
    if (cell.x > -900) {
      this.claims.set(playerId, { ...cell });
    } else {
      this.claims.delete(playerId);
    }
  }

  /**
   * If two AIs claim nearly the same cell (Manhattan <= 3),
   * nudge the later one (higher player_id) to replan.
   */
  resolveDuplicateClaims(commanders: ReplanTarget[]): void {
    const cells: Vec2i[] = [];
    for (const commander of commanders) {
      const claim = this.claims.get(commander.playerId);
      if (claim === undefined || claim.x <= -900) {
        continue;
      }
      for (const other of cells) {
        const dist = Math.abs(claim.x - other.x) + Math.abs(claim.y - other.y);
        if (dist <= 3) {
          commander.requestReplan("duplicate_objective");
          break;
        }
      }
      cells.push({ ...claim });
    }
  }
}
