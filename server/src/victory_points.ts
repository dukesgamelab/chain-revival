/**
 * Runtime victory-point ownership. Chebyshev radius-5 presence capture.
 * Port of VictoryPointSystem.gd.
 */

import type { GameState } from "./game_state";
import { TEAM_USA, TEAM_GERMANY, chebyshev, type Vec2i } from "./types";

/** Chebyshev radius for presence/contest. */
export const CAPTURE_RADIUS = 5;

export interface VictoryPointEntry {
  x: number;
  y: number;
  holder: string;
  initialHolder: string;
  captureElapsedSec: number;
  usPoints: number;
  gmPoints: number;
}

export function ensureHoldersInitialized(entries: VictoryPointEntry[]): void {
  for (const entry of entries) {
    if (!entry.holder || entry.holder.trim().length === 0) {
      entry.holder = entry.initialHolder || "Germany";
    }
    if (entry.captureElapsedSec === undefined) {
      entry.captureElapsedSec = 0;
    }
  }
}

/**
 * Poll ownership. Holder = side with living soldiers in radius and no living enemy contesting.
 * Returns true if any VP holder changed.
 */
export function updateCapture(
  state: GameState,
  vpEntries: VictoryPointEntry[],
  elapsedSec: number,
): boolean {
  ensureHoldersInitialized(vpEntries);
  let changed = false;

  for (const entry of vpEntries) {
    if (entry.x <= -900) {
      continue;
    }
    const cell: Vec2i = { x: entry.x, y: entry.y };
    const usaHere = teamSoldierWithin(state, TEAM_USA, cell, CAPTURE_RADIUS);
    const gerHere = teamSoldierWithin(state, TEAM_GERMANY, cell, CAPTURE_RADIUS);

    // Contested: no ownership change.
    if (usaHere && gerHere) {
      continue;
    }

    let newHolder = "";
    if (usaHere) {
      newHolder = "USA";
    } else if (gerHere) {
      newHolder = "Germany";
    } else {
      continue;
    }

    if (sameHolder(entry.holder, newHolder)) {
      continue;
    }

    entry.holder = newHolder;
    entry.captureElapsedSec = elapsedSec;
    changed = true;
  }

  return changed;
}

export function holderIsUsa(holder: string): boolean {
  const key = holder.trim().toLowerCase();
  return key === "usa" || key === "us" || key.includes("american");
}

export function holderTeamId(holder: string): number {
  return holderIsUsa(holder) ? TEAM_USA : TEAM_GERMANY;
}

function teamSoldierWithin(
  state: GameState,
  teamId: number,
  cell: Vec2i,
  radius: number,
): boolean {
  for (const soldier of state.soldiersOnTeam(teamId)) {
    if (soldier.isDead) {
      continue;
    }
    if (chebyshev(soldier.gridPosition, cell) <= radius) {
      return true;
    }
  }
  return false;
}

function sameHolder(a: string, b: string): boolean {
  return holderIsUsa(a) === holderIsUsa(b);
}
