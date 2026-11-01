/**
 * Runtime victory-point ownership. Chebyshev radius-5 presence capture
 * with a timed capture bar (CAPTURE_TIME_SEC uncontested presence to flip).
 */

import type { GameState } from "./game_state";
import { TEAM_USA, TEAM_GERMANY, chebyshev, type Vec2i } from "./types";

/** Chebyshev radius for presence/contest. */
export const CAPTURE_RADIUS = 5;

/** Seconds of uncontested presence needed to capture a VP. */
export const CAPTURE_TIME_SEC = 20;

export interface VictoryPointEntry {
  x: number;
  y: number;
  holder: string;
  initialHolder: string;
  captureElapsedSec: number;
  usPoints: number;
  gmPoints: number;
  /** 0-1 progress toward capture by the non-holder side. */
  captureProgress?: number;
  /** Which side is currently capturing ("USA" | "Germany" | ""). */
  capturingSide?: string;
}

export function ensureHoldersInitialized(entries: VictoryPointEntry[]): void {
  for (const entry of entries) {
    if (!entry.holder || entry.holder.trim().length === 0) {
      entry.holder = entry.initialHolder || "Germany";
    }
    if (entry.captureElapsedSec === undefined) {
      entry.captureElapsedSec = 0;
    }
    if (entry.captureProgress === undefined) {
      entry.captureProgress = 0;
    }
    if (entry.capturingSide === undefined) {
      entry.capturingSide = "";
    }
  }
}

/**
 * Poll ownership with timed capture. Returns true if any VP holder changed
 * OR capture progress changed (so broadcast can update clients).
 */
export function updateCapture(
  state: GameState,
  vpEntries: VictoryPointEntry[],
  elapsedSec: number,
  tickSec: number,
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

    const progress = entry.captureProgress ?? 0;
    const prevCapSide = entry.capturingSide ?? "";

    // Contested or nobody here: reset capture progress.
    if ((usaHere && gerHere) || (!usaHere && !gerHere)) {
      if (progress > 0) {
        entry.captureProgress = 0;
        entry.capturingSide = "";
        changed = true;
      }
      continue;
    }

    const attackingSide = usaHere ? "USA" : "Germany";

    // If the attacker already holds it, no capture needed - reset any stale progress.
    if (sameHolder(entry.holder, attackingSide)) {
      if (progress > 0) {
        entry.captureProgress = 0;
        entry.capturingSide = "";
        changed = true;
      }
      continue;
    }

    // A different side started capturing - reset progress.
    let newProgress = progress;
    if (prevCapSide !== "" && !sameHolder(prevCapSide, attackingSide)) {
      newProgress = 0;
    }

    entry.capturingSide = attackingSide;
    entry.captureProgress = Math.min(1, newProgress + tickSec / CAPTURE_TIME_SEC);
    changed = true;

    // Capture complete.
    if (entry.captureProgress >= 1) {
      entry.holder = attackingSide;
      entry.captureElapsedSec = elapsedSec;
      entry.captureProgress = 0;
      entry.capturingSide = "";
    }
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
