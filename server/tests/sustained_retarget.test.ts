import assert from "node:assert/strict";
import { test } from "node:test";
import { processMovementTick } from "../src/action_resolver";
import { processCombatTick } from "../src/combat_system";
import { GameState } from "../src/game_state";
import { MapData } from "../src/map_data";
import { COMBAT_SCAN_TICKS } from "../src/perception";
import { FIRE_AT_WILL, FIRE_HOLD, TEAM_GERMANY, TEAM_USA, vec, type Vec2i } from "../src/types";

function pump(state: GameState, msec: number): void {
  let left = msec;
  while (left > 0) {
    const slice = Math.min(500, left);
    state.clock.consumeRealtime(slice, (tickId) => {
      processMovementTick(state);
      state.perception.processTick(state, tickId);
      if (tickId % COMBAT_SCAN_TICKS === 0) {
        processCombatTick(state);
      }
    });
    left -= slice;
  }
}

// USA 1 on sustained Fire At at GER 1, who stands behind a wall (visible, not hittable).
function setup(withOpenEnemy: boolean): GameState {
  const state = new GameState(MapData.empty(24, 24));
  for (const s of state.soldiers) {
    s.isDead = true;
  }
  for (const y of [2, 3, 4]) {
    state.map.placeObject(vec(7, y), "wall_straight", "SWAL");
  }
  const place = (teamId: number, id: number, cell: Vec2i, facing: Vec2i) => {
    const s = state.getSoldier(teamId, id);
    assert.ok(s);
    s.isDead = false;
    s.gridPosition = cell;
    s.facing = facing;
    s.fireControlState = FIRE_HOLD;
    return s;
  };
  const shooter = place(TEAM_USA, 1, vec(4, 4), vec(1, 0));
  place(TEAM_GERMANY, 1, vec(10, 3), vec(-1, 0));
  if (withOpenEnemy) {
    place(TEAM_GERMANY, 2, vec(8, 9), vec(-1, -1));
  }
  shooter.fireControlState = FIRE_AT_WILL;
  shooter.beginSustainedFire();
  shooter.setEngagedTarget(TEAM_GERMANY, 1);
  state.markPerceptionDirty();
  return state;
}

test("Fire At on a blocked target switches to a hittable enemy", () => {
  const state = setup(true);
  pump(state, 4000);
  const shooter = state.getSoldier(TEAM_USA, 1)!;
  assert.equal(shooter.engagedTargetTeamId, TEAM_GERMANY);
  assert.equal(shooter.engagedTargetSoldierId, 2);
});

test("Fire At on a blocked target holds it when nothing else is hittable", () => {
  const state = setup(false);
  pump(state, 4000);
  const shooter = state.getSoldier(TEAM_USA, 1)!;
  assert.equal(shooter.engagedTargetSoldierId, 1);
  assert.equal(shooter.sustainedFire, true);
});
