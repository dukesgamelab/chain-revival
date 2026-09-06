import { stepCostMsec } from "./movement_policy";
import {
  MOVEMENT_RUN,
  POSITION_UP,
  type SoldierSnapshot,
  type Vec2i,
  vec,
} from "./types";

export class SoldierState {
  readonly soldierId: number;
  readonly teamId: number;
  gridPosition: Vec2i;
  facing: Vec2i;
  positionState = POSITION_UP;
  movementMode = MOVEMENT_RUN;
  isDead = false;
  isMoving = false;
  currentPath: Vec2i[] = [];
  pathIndex = 0;
  moveAccumMsec = 0;
  moveStepCostMsec = 0;
  moveSpeedMult = 1.0;
  stunnedUntilMsec = 0;

  constructor(soldierId: number, teamId: number, gridPosition: Vec2i, facing: Vec2i) {
    this.soldierId = soldierId;
    this.teamId = teamId;
    this.gridPosition = { ...gridPosition };
    this.facing = { ...facing };
  }

  isStunned(nowMsec: number): boolean {
    return nowMsec < this.stunnedUntilMsec;
  }

  clearPath(): void {
    this.currentPath = [];
    this.isMoving = false;
    this.pathIndex = 0;
    this.moveAccumMsec = 0;
    this.moveStepCostMsec = 0;
    this.moveSpeedMult = 1.0;
  }

  assignPath(path: Vec2i[], speedMult: number): void {
    if (this.isDead) {
      return;
    }
    this.currentPath = path.map((cell) => ({ ...cell }));
    this.moveSpeedMult = speedMult;
    this.moveAccumMsec = 0;
    this.pathIndex = 1;
    this.isMoving = this.currentPath.length > 1;
    if (this.isMoving) {
      this.moveStepCostMsec = stepCostMsec(this.currentPath[0], this.currentPath[1], this.moveSpeedMult);
    } else {
      this.moveStepCostMsec = 0;
      this.pathIndex = 0;
    }
  }

  toSnapshot(): SoldierSnapshot {
    return {
      soldierId: this.soldierId,
      teamId: this.teamId,
      gridPosition: { ...this.gridPosition },
      facing: { ...this.facing },
      positionState: this.positionState,
      movementMode: this.movementMode,
      isDead: this.isDead,
      isMoving: this.isMoving,
      currentPath: this.currentPath.map((cell) => ({ ...cell })),
      pathIndex: this.pathIndex,
      moveSpeedMult: this.moveSpeedMult,
    };
  }
}

export function defaultFacingForTeam(teamId: number): Vec2i {
  return teamId === 2 ? vec(1, 1) : vec(-1, -1);
}
