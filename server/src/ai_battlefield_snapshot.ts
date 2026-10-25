/**
 * Per-tick battlefield snapshot for all AI commanders — port of ai_battlefield_snapshot.gd.
 * Built once per framework tick, never per-commander.
 *
 * visible_enemies: fog/LOS limited (use for firing decisions).
 * known_enemies: omniscient living enemies (use for contact, cover, facing decisions).
 */

import type { GameState } from "./game_state";
import type { SoldierState } from "./soldier_state";
import { TEAM_USA, TEAM_GERMANY } from "./types";

export class AiBattlefieldSnapshot {
  private readonly visibleEnemies = new Map<number, SoldierState[]>();
  private readonly knownEnemies = new Map<number, SoldierState[]>();
  private readonly livingSoldiers = new Map<number, SoldierState[]>();
  private readonly fireteamMoving = new Map<number, boolean>();

  visibleFor(playerId: number): SoldierState[] {
    return this.visibleEnemies.get(playerId) ?? [];
  }

  knownFor(playerId: number): SoldierState[] {
    return this.knownEnemies.get(playerId) ?? [];
  }

  livingFor(playerId: number): SoldierState[] {
    return this.livingSoldiers.get(playerId) ?? [];
  }

  isMoving(playerId: number): boolean {
    return this.fireteamMoving.get(playerId) ?? false;
  }

  /**
   * Build a read-only snapshot. Does NOT force visibility rebuild (combat scan owns that).
   * Each AI player is identified by a playerId that maps to a teamId.
   *
   * In the current server, playerId and teamId are the same (one player per side).
   * The snapshot still takes a teamId resolver for future multi-AI support.
   */
  static build(
    state: GameState,
    aiPlayers: Array<{ playerId: number; teamId: number }>,
  ): AiBattlefieldSnapshot {
    const snap = new AiBattlefieldSnapshot();

    for (const { playerId, teamId } of aiPlayers) {
      // Living, non-stunned soldiers for this AI player
      const living: SoldierState[] = [];
      let moving = false;
      const nowMsec = state.clock.getTicksMsec();
      for (const soldier of state.soldiersOnTeam(teamId)) {
        if (soldier.isDead || soldier.isStunned(nowMsec)) {
          continue;
        }
        living.push(soldier);
        if (soldier.isMoving) {
          moving = true;
        }
      }
      snap.livingSoldiers.set(playerId, living);
      snap.fireteamMoving.set(playerId, moving);

      // Visible enemies: LOS-gated from perception system
      const visible: SoldierState[] = [];
      const enemyTeamId = teamId === TEAM_USA ? TEAM_GERMANY : TEAM_USA;
      for (const enemy of state.soldiersOnTeam(enemyTeamId)) {
        if (enemy.isDead) {
          continue;
        }
        if (state.perception.isVisibleToTeam(teamId, enemy.teamId, enemy.soldierId)) {
          visible.push(enemy);
        }
      }
      snap.visibleEnemies.set(playerId, visible);

      // Known enemies: omniscient (every living enemy on the opposing side)
      const known: SoldierState[] = [];
      for (const enemy of state.soldiersOnTeam(enemyTeamId)) {
        if (!enemy.isDead) {
          known.push(enemy);
        }
      }
      snap.knownEnemies.set(playerId, known);
    }

    return snap;
  }
}
