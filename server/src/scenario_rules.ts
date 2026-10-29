/**
 * Authoritative scenario clock, kill/VP scoring, and end resolution.
 * Driven from SimulationClock ticks, never wall-clock time.
 * Port of ScenarioRules.gd.
 */

import type { GameState } from "./game_state";
import type { SoldierState } from "./soldier_state";
import { TEAM_USA, TEAM_GERMANY } from "./types";
import {
  ensureHoldersInitialized,
  holderIsUsa,
  updateCapture,
  type VictoryPointEntry,
} from "./victory_points";

export type { VictoryPointEntry };

// --- End cause / winner constants ---

export const END_CAUSE_NONE = 0;
export const END_CAUSE_TIME_GONE = 1;
export const END_CAUSE_EXTERMINATION = 4;
export const END_CAUSE_FORFEIT = 5;

export const WINNER_NONE = 0;
export const WINNER_USA = 1;
export const WINNER_GERMANY = 2;
export const WINNER_DRAW = 3;

// --- Recovered / tuned constants ---

/** RECOVERED TimeBased = 15 minutes. */
export const SCENARIO_TIME_SEC = 15 * 60;
/** RECOVERED INITPPconstOnKill. */
export const KILL_POINTS = 4;
/** RECOVERED INITPPLostOnKilledSoldier. */
export const PP_LOST_PER_SOLDIER = 1;
/** RECOVERED SpecArea->PP_const. */
export const SPEC_AREA_POINTS = 1;
/** VP poll interval in seconds. */
const VP_POLL_INTERVAL_SEC = 1.0;
/** Decay floor at end of mission. */
const VP_DECAY_FLOOR = 0.25;

// --- Scenario state (lives on GameState via ScenarioState) ---

export interface ScenarioState {
  scenarioTimeSec: number;
  elapsedSec: number;
  timeRemainingSec: number;
  ended: boolean;
  endCause: number;
  winner: number;
  killPoints: Record<number, number>;
  killCounts: Record<number, number>;
  terrainPoints: Record<number, number>;
  vpPollAccumSec: number;
  vpEntries: VictoryPointEntry[];
}

export function createScenarioState(vpEntries: VictoryPointEntry[] = []): ScenarioState {
  ensureHoldersInitialized(vpEntries);
  return {
    scenarioTimeSec: SCENARIO_TIME_SEC,
    elapsedSec: 0,
    timeRemainingSec: SCENARIO_TIME_SEC,
    ended: false,
    endCause: END_CAUSE_NONE,
    winner: WINNER_NONE,
    killPoints: { [TEAM_USA]: 0, [TEAM_GERMANY]: 0 },
    killCounts: { [TEAM_USA]: 0, [TEAM_GERMANY]: 0 },
    terrainPoints: { [TEAM_USA]: 0, [TEAM_GERMANY]: 0 },
    vpPollAccumSec: 0,
    vpEntries,
  };
}

/**
 * Advance clock + VP poll from one simulation tick.
 * Returns true if the scenario just ended.
 */
export function processTick(
  state: GameState,
  scenario: ScenarioState,
  tickSec: number,
): boolean {
  if (scenario.ended) {
    return false;
  }

  scenario.elapsedSec += tickSec;
  scenario.timeRemainingSec = Math.max(0, scenario.scenarioTimeSec - scenario.elapsedSec);

  // VP poll
  scenario.vpPollAccumSec += tickSec;
  if (scenario.vpPollAccumSec >= VP_POLL_INTERVAL_SEC) {
    scenario.vpPollAccumSec = 0;
    updateCapture(state, scenario.vpEntries, scenario.elapsedSec);
  }

  // Extermination check
  if (livingSoldierCount(state, TEAM_USA) <= 0) {
    awardHeldVictoryPoints(scenario);
    return endScenario(scenario, END_CAUSE_EXTERMINATION, WINNER_GERMANY);
  }
  if (livingSoldierCount(state, TEAM_GERMANY) <= 0) {
    awardHeldVictoryPoints(scenario);
    return endScenario(scenario, END_CAUSE_EXTERMINATION, WINNER_USA);
  }

  // Time expired
  if (scenario.timeRemainingSec <= 0) {
    return endByScore(scenario);
  }

  return false;
}

/** Call after a soldier is killed to update scoring. */
export function onSoldierKilled(
  scenario: ScenarioState,
  killerTeamId: number,
  victim: SoldierState,
): void {
  if (scenario.ended) {
    return;
  }
  if (killerTeamId === TEAM_USA || killerTeamId === TEAM_GERMANY) {
    addKillPoints(scenario, killerTeamId, KILL_POINTS);
    scenario.killCounts[killerTeamId] = (scenario.killCounts[killerTeamId] ?? 0) + 1;
  }
  addKillPoints(scenario, victim.teamId, -PP_LOST_PER_SOLDIER);
}

export function totalPoints(scenario: ScenarioState, teamId: number): number {
  return (scenario.killPoints[teamId] ?? 0) + (scenario.terrainPoints[teamId] ?? 0);
}

export function livingSoldierCount(state: GameState, teamId: number): number {
  let count = 0;
  for (const s of state.soldiersOnTeam(teamId)) {
    if (!s.isDead) {
      count += 1;
    }
  }
  return count;
}

export function winnerDisplayName(winner: number): string {
  switch (winner) {
    case WINNER_USA:
      return "American victory";
    case WINNER_GERMANY:
      return "German victory";
    case WINNER_DRAW:
      return "Draw";
    default:
      return "No winner";
  }
}

export function endCauseMessage(cause: number): string {
  switch (cause) {
    case END_CAUSE_TIME_GONE:
      return "The mission ended because the mission time is up.";
    case END_CAUSE_EXTERMINATION:
      return "The mission ended because one side was wiped out.";
    case END_CAUSE_FORFEIT:
      return "The mission ended because a player disconnected.";
    default:
      return "The mission has ended.";
  }
}

// --- Internal ---

function endScenario(scenario: ScenarioState, cause: number, winner: number): boolean {
  if (scenario.ended) {
    return false;
  }
  scenario.ended = true;
  scenario.endCause = cause;
  scenario.winner = winner;
  scenario.timeRemainingSec = Math.max(0, scenario.timeRemainingSec);
  console.log(
    "[Scenario] END cause=%s winner=%s usa=%d ger=%d",
    cause,
    winner,
    totalPoints(scenario, TEAM_USA),
    totalPoints(scenario, TEAM_GERMANY),
  );
  return true;
}

function endByScore(scenario: ScenarioState): boolean {
  awardHeldVictoryPoints(scenario);
  const usa = totalPoints(scenario, TEAM_USA);
  const ger = totalPoints(scenario, TEAM_GERMANY);
  let winner = WINNER_DRAW;
  if (usa > ger) {
    winner = WINNER_USA;
  } else if (ger > usa) {
    winner = WINNER_GERMANY;
  }
  return endScenario(scenario, END_CAUSE_TIME_GONE, winner);
}

function vpDecayFactor(elapsedSec: number): number {
  const t = Math.min(Math.max(elapsedSec / SCENARIO_TIME_SEC, 0), 1);
  return 1.0 + (VP_DECAY_FLOOR - 1.0) * t;
}

function effectiveVpAward(basePoints: number, captureElapsedSec: number): number {
  const scaled = basePoints * vpDecayFactor(captureElapsedSec) * SPEC_AREA_POINTS;
  return Math.round(scaled);
}

function awardHeldVictoryPoints(scenario: ScenarioState): void {
  ensureHoldersInitialized(scenario.vpEntries);
  scenario.terrainPoints[TEAM_USA] = 0;
  scenario.terrainPoints[TEAM_GERMANY] = 0;

  for (const entry of scenario.vpEntries) {
    const holder = entry.holder || entry.initialHolder || "Germany";
    const captureT = entry.captureElapsedSec ?? scenario.elapsedSec;
    const teamId = holderIsUsa(holder) ? TEAM_USA : TEAM_GERMANY;
    const base = teamId === TEAM_USA ? (entry.usPoints ?? 0) : (entry.gmPoints ?? 0);
    const award = effectiveVpAward(base, captureT);
    scenario.terrainPoints[teamId] = (scenario.terrainPoints[teamId] ?? 0) + award;
  }
}

function addKillPoints(scenario: ScenarioState, teamId: number, delta: number): void {
  scenario.killPoints[teamId] = (scenario.killPoints[teamId] ?? 0) + delta;
}
