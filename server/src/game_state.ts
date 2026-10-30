/**
 * Authoritative multiplayer GameState (movement slice).
 * Lives only on the Node server in LOCAL_MULTIPLAYER.
 */

import { GameRandom } from "./game_random";
import type { LosOccupant } from "./los";
import type { MapData } from "./map_data";
import { PerceptionSystem } from "./perception";
import { SimTimers } from "./sim_timers";
import { SimulationClock } from "./simulation_clock";
import { SoldierState, defaultFacingForTeam } from "./soldier_state";
import {
  MATCH_ID,
  TEAM_GERMANY,
  TEAM_USA,
  type MatchSnapshot,
  type Vec2i,
} from "./types";
import {
  createScenarioState,
  type ScenarioState,
  type VictoryPointEntry,
} from "./scenario_rules";

const SOLDIERS_PER_SIDE = 4;

export class GameState {
  readonly matchId = MATCH_ID;
  readonly map: MapData;
  readonly clock = new SimulationClock();
  readonly timers = new SimTimers();
  readonly soldiers: SoldierState[] = [];
  readonly perception = new PerceptionSystem();
  readonly rng = new GameRandom(1);
  nextShotId = 0;
  readonly scenario: ScenarioState;

  constructor(map: MapData) {
    this.map = map;
    this.scenario = createScenarioState(map.victoryPoints ?? []);
    this.spawnSides();
    this.faceOpposites();
    this.perception.rebuildVisibility(this);
    this.perception.acknowledge();
  }

  private spawnSides(): void {
    spawnTeam(this.soldiers, TEAM_USA, this.map.team1Spawns);
    spawnTeam(this.soldiers, TEAM_GERMANY, this.map.team2Spawns);
  }

  private faceOpposites(): void {
    const usa = this.soldiers.filter((s) => s.teamId === TEAM_USA);
    const ger = this.soldiers.filter((s) => s.teamId === TEAM_GERMANY);
    const n = Math.min(usa.length, ger.length);
    for (let i = 0; i < n; i += 1) {
      usa[i].facing = towardCell(usa[i].gridPosition, ger[i].gridPosition);
      ger[i].facing = towardCell(ger[i].gridPosition, usa[i].gridPosition);
    }
  }

  getSoldier(teamId: number, soldierId: number): SoldierState | null {
    return (
      this.soldiers.find((s) => s.teamId === teamId && s.soldierId === soldierId) ?? null
    );
  }

  soldiersOnTeam(teamId: number): SoldierState[] {
    return this.soldiers.filter((s) => s.teamId === teamId);
  }

  findLivingSoldierAtCell(cell: Vec2i): SoldierState | null {
    return (
      this.soldiers.find(
        (s) => !s.isDead && s.gridPosition.x === cell.x && s.gridPosition.y === cell.y,
      ) ?? null
    );
  }

  losOccupants(): LosOccupant[] {
    return this.soldiers.map((s) => ({
      cell: s.gridPosition,
      isDead: s.isDead,
      positionState: s.positionState,
    }));
  }

  markPerceptionDirty(): void {
    this.perception.markDirty();
  }

  getSnapshot(matchPhase = "running"): MatchSnapshot {
    return {
      type: "match_snapshot",
      matchId: this.matchId,
      mapId: this.map.mapId,
      mapDisplayName: this.map.metadata.displayName,
      supportedTeamSizes: this.map.metadata.supportedTeamSizes,
      simMsec: this.clock.getTicksMsec(),
      tickId: this.clock.getTickId(),
      simRunning: this.clock.isRunning(),
      matchPhase,
      soldiers: this.soldiers.map((s) => s.toSnapshot()),
      visibility: this.perception.visibilityPayload(),
      scenarioTimeRemainingSec: this.scenario.timeRemainingSec,
      scenarioElapsedSec: this.scenario.elapsedSec,
      scenarioEnded: this.scenario.ended,
      usaTotalPoints: (this.scenario.killPoints[1] ?? 0) + (this.scenario.terrainPoints[1] ?? 0),
      germanyTotalPoints: (this.scenario.killPoints[2] ?? 0) + (this.scenario.terrainPoints[2] ?? 0),
    };
  }
}

function spawnTeam(out: SoldierState[], teamId: number, spawns: Vec2i[]): void {
  const facing = defaultFacingForTeam(teamId);
  for (let i = 0; i < SOLDIERS_PER_SIDE; i += 1) {
    const cell = spawns[i] ?? { x: 2 + i, y: teamId === TEAM_USA ? 2 : 10 };
    out.push(new SoldierState(i + 1, teamId, cell, facing));
  }
}

function towardCell(from: Vec2i, to: Vec2i): Vec2i {
  const dx = Math.max(-1, Math.min(1, to.x - from.x));
  const dy = Math.max(-1, Math.min(1, to.y - from.y));
  if (dx === 0 && dy === 0) {
    return { x: 0, y: -1 };
  }
  return { x: dx, y: dy };
}
