import { stepCostMsec } from "./movement_policy";
import {
  FIRE_AT_WILL,
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
  /** Presentation gate mirrored from Godot; gameplay stance is already committed. */
  pendingPositionState = -1;
  pendingStanceUntilMsec = 0;
  fireControlState = FIRE_AT_WILL;
  engagedTargetTeamId = -1;
  engagedTargetSoldierId = -1;
  sustainedFire = false;

  constructor(soldierId: number, teamId: number, gridPosition: Vec2i, facing: Vec2i) {
    this.soldierId = soldierId;
    this.teamId = teamId;
    this.gridPosition = { ...gridPosition };
    this.facing = { ...facing };
  }

  isStunned(nowMsec: number): boolean {
    return nowMsec < this.stunnedUntilMsec;
  }

  clearPendingPosition(): void {
    this.pendingPositionState = -1;
    this.pendingStanceUntilMsec = 0;
  }

  expirePendingStance(nowMsec: number): void {
    if (this.pendingPositionState >= 0 && nowMsec >= this.pendingStanceUntilMsec) {
      this.clearPendingPosition();
    }
  }

  beginPendingStance(target: number, nowMsec: number, gateMsec: number): void {
    this.pendingPositionState = target;
    this.pendingStanceUntilMsec = nowMsec + gateMsec;
  }

  clearPath(): void {
    this.currentPath = [];
    this.isMoving = false;
    this.pathIndex = 0;
    this.moveAccumMsec = 0;
    this.moveStepCostMsec = 0;
    this.moveSpeedMult = 1.0;
  }

  isEngaged(): boolean {
    return this.engagedTargetTeamId >= 0 && this.engagedTargetSoldierId > 0;
  }

  setEngagedTarget(targetTeamId: number, targetSoldierId: number): void {
    this.engagedTargetTeamId = targetTeamId;
    this.engagedTargetSoldierId = targetSoldierId;
  }

  clearEngagedTarget(): void {
    this.engagedTargetTeamId = -1;
    this.engagedTargetSoldierId = -1;
  }

  beginSustainedFire(): void {
    this.sustainedFire = true;
  }

  endSustainedFire(): void {
    this.sustainedFire = false;
    this.clearEngagedTarget();
  }

  clearEngagement(): void {
    this.clearEngagedTarget();
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
      fireControlState: this.fireControlState,
      engagedTargetTeamId: this.engagedTargetTeamId,
      engagedTargetSoldierId: this.engagedTargetSoldierId,
      sustainedFire: this.sustainedFire,
    };
  }
}

export function defaultFacingForTeam(teamId: number): Vec2i {
  return teamId === 2 ? vec(1, 1) : vec(-1, -1);
}
