/**
 * 8-way facing — port of scripts/enums/facing_direction.gd
 * (from_step / toward_cell / toward_world_point).
 */

import { gridToWorld } from "./movement_policy";
import { type Vec2i, vec, vecEq } from "./types";

const AIM_SENTINEL = -90000;
const MIN_AXIS = 2.0;

export function fromStep(step: Vec2i): Vec2i {
  if (step.x === 0 && step.y === 0) {
    return vec(0, -1);
  }
  return vec(clampUnit(step.x), clampUnit(step.y));
}

export function towardCell(fromCell: Vec2i, targetCell: Vec2i): Vec2i {
  return fromStep(vec(targetCell.x - fromCell.x, targetCell.y - fromCell.y));
}

export function towardWorldPoint(
  fromCell: Vec2i,
  targetCell: Vec2i,
  worldPoint: Vec2i | null,
): Vec2i {
  if (!vecEq(targetCell, fromCell)) {
    return towardCell(fromCell, targetCell);
  }
  if (worldPoint === null || worldPoint.x < AIM_SENTINEL) {
    return vec(0, 0);
  }
  const fromWorld = gridToWorld(fromCell);
  const dx = worldPoint.x - fromWorld.x;
  const dy = worldPoint.y - fromWorld.y;
  if (Math.abs(dx) < MIN_AXIS && Math.abs(dy) < MIN_AXIS) {
    return vec(0, 0);
  }
  const step = vec(0, 0);
  if (Math.abs(dx) >= MIN_AXIS) {
    step.x = dx > 0 ? 1 : -1;
  }
  if (Math.abs(dy) >= MIN_AXIS) {
    step.y = dy > 0 ? 1 : -1;
  }
  return fromStep(step);
}

export function facingName(facing: Vec2i): string {
  const n = fromStep(facing);
  if (n.x === 1 && n.y === -1) {
    return "NORTHEAST";
  }
  if (n.x === 1 && n.y === 0) {
    return "EAST";
  }
  if (n.x === 1 && n.y === 1) {
    return "SOUTHEAST";
  }
  if (n.x === 0 && n.y === 1) {
    return "SOUTH";
  }
  if (n.x === -1 && n.y === 1) {
    return "SOUTHWEST";
  }
  if (n.x === -1 && n.y === 0) {
    return "WEST";
  }
  if (n.x === -1 && n.y === -1) {
    return "NORTHWEST";
  }
  return "NORTH";
}

export function teamDisplayName(teamId: number): string {
  return teamId === 2 ? "Germany" : "USA";
}

function clampUnit(value: number): number {
  return Math.max(-1, Math.min(1, value));
}
