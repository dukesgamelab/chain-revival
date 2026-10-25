/**
 * Per-player AI brain. Issues gameplay commands via a submit callback.
 * Never mutates GameState soldier/map fields directly.
 * Port of ai_commander.gd (standard multiplayer; survival mode excluded).
 */

import type { GameState } from "./game_state";
import type { SoldierState } from "./soldier_state";
import { evaluateTargetCover } from "./los";
import { GRENADE_THROW_RANGE } from "./grenade_system";
import {
  chebyshev,
  MATCH_ID,
  MOVE_SCOPE_SINGLE,
  MOVE_SCOPE_SQUAD,
  MOVEMENT_CRAWL,
  MOVEMENT_RUN,
  POSITION_DOWN,
  POSITION_UP,
  TEAM_GERMANY,
  TEAM_USA,
  vec,
  vecEq,
  type Vec2i,
} from "./types";

// ---------------------------------------------------------------------------
// Snapshot: lightweight per-tick battlefield read shared across commanders
// ---------------------------------------------------------------------------

export interface AiBattlefieldSnapshot {
  visibleFor(playerId: number): SoldierState[];
  knownFor(playerId: number): SoldierState[];
  livingFor(playerId: number): SoldierState[];
  isMoving(playerId: number): boolean;
}

export function buildSnapshot(
  state: GameState,
  aiPlayerIds: number[],
): AiBattlefieldSnapshot {
  const visible = new Map<number, SoldierState[]>();
  const known = new Map<number, SoldierState[]>();
  const living = new Map<number, SoldierState[]>();
  const moving = new Map<number, boolean>();

  for (const pid of aiPlayerIds) {
    const teamId = pid; // In this server, player_id === teamId for AI
    const livingSoldiers: SoldierState[] = [];
    let anyMoving = false;
    for (const s of state.soldiersOnTeam(teamId)) {
      if (s.isDead || s.isStunned(state.clock.getTicksMsec())) continue;
      livingSoldiers.push(s);
      if (s.isMoving) anyMoving = true;
    }
    living.set(pid, livingSoldiers);
    moving.set(pid, anyMoving);

    // Visible: from perception system
    const visibleEnemies: SoldierState[] = [];
    const visPayload = state.perception.visibilityPayload();
    const teamVis = visPayload.find((v) => v.teamId === teamId);
    if (teamVis) {
      for (const ref of teamVis.visible) {
        const enemy = state.getSoldier(ref.teamId, ref.soldierId);
        if (enemy && !enemy.isDead) visibleEnemies.push(enemy);
      }
    }
    visible.set(pid, visibleEnemies);

    // Known: omniscient all living enemies
    const enemyTeam = teamId === TEAM_USA ? TEAM_GERMANY : TEAM_USA;
    const knownEnemies: SoldierState[] = [];
    for (const s of state.soldiersOnTeam(enemyTeam)) {
      if (!s.isDead) knownEnemies.push(s);
    }
    known.set(pid, knownEnemies);
  }

  return {
    visibleFor: (pid) => visible.get(pid) ?? [],
    knownFor: (pid) => known.get(pid) ?? [],
    livingFor: (pid) => living.get(pid) ?? [],
    isMoving: (pid) => moving.get(pid) ?? false,
  };
}

// ---------------------------------------------------------------------------
// Objective
// ---------------------------------------------------------------------------

export interface AiObjective {
  objectiveId: string;
  label: string;
  cell: Vec2i;
  kind: string;
  priority: number;
}

function makeObj(id: string, label: string, cell: Vec2i, kind: string, prio: number): AiObjective {
  return { objectiveId: id, label, cell: { ...cell }, kind, priority: prio };
}

function objValid(obj: AiObjective | null): obj is AiObjective {
  return obj !== null && obj.cell.x > -900 && obj.objectiveId.length > 0;
}

// ---------------------------------------------------------------------------
// Plan constants
// ---------------------------------------------------------------------------

const PLAN_ATTACK_LEFT = "attack_left";
const PLAN_ATTACK_CENTER = "attack_center";
const PLAN_ATTACK_RIGHT = "attack_right";
const PLAN_DEFEND = "defend";
const PLAN_FLANK = "flank";

// State machine
const ST_PLAN = "plan";
const ST_MOVE = "move";
const ST_CONTACT = "contact";
const ST_FIGHT = "fight";
const ST_ADVANCE = "advance";
const ST_OBJECTIVE_COMPLETE = "objective_complete";

// ---------------------------------------------------------------------------
// Tuning constants (from ai_commander.gd)
// ---------------------------------------------------------------------------

const REPLAN_INTERVAL_MSEC = 2000;
const MAX_COMMANDS_PER_TICK = 6;
const OBJECTIVE_ARRIVE_DIST = 2;
const GRENADE_CLUSTER_CHEBYSHEV = 2;
const COVER_SEEK_MAX_DIST = 14;
const CLOSE_RANGE_DIST = 4;
const CLOSE_COVER_SEEK_MAX_DIST = 3;
const ADVANCE_BOUND_MIN_DIST = 6;
const ADVANCE_BOUND_MAX_DIST = 10;
const DEFENSIVE_POST_CLUSTER = 10;
const DEFENSIVE_POST_MIN_SEP = 2;
const FIRETEAM_COHESION_RADIUS = 14;
const STRAGGLER_CHEBYSHEV = 4;
const CONTACT_REACT_DIST = 32;
const CONTACT_THREAT_STANDOFF = 3;
const COVER_THREAT_SHIFT_CHEBYSHEV = 3;
const COVER_RESETTLE_MSEC = 6000;
const STAND_UP_COOLDOWN_MSEC = 1500;
const STRESS_COVER_PRIORITY = 35.0;
const STRESS_HEAVY_FIRE = 55.0;
const OPEN_PRONE_CHANCE = 0.12;
const OPEN_PRONE_COOLDOWN_MSEC = 8000;
const DEDUP_EXPIRE_MSEC = 2000;
const WATCHDOG_IDLE_MSEC = 5000;
const COVER_POST_ARRIVE_DIST = 0;
const MAX_COVER_CHECKS_PER_QUERY = 96;

// ---------------------------------------------------------------------------
// Submit result
// ---------------------------------------------------------------------------

export interface SubmitResult {
  success: boolean;
}

export type SubmitFn = (command: Record<string, unknown>) => SubmitResult;
export type FindPathFn = (from: Vec2i, to: Vec2i) => Vec2i[];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function manhattan(a: Vec2i, b: Vec2i): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

function sign(n: number): number {
  return n > 0 ? 1 : n < 0 ? -1 : 0;
}

function clampWalkable(map: GameState["map"], cell: Vec2i): Vec2i {
  const c = map.clampToBounds(cell);
  if (map.isWalkable(c)) return c;
  for (let r = 1; r < 12; r++) {
    for (let dx = -r; dx <= r; dx++) {
      for (let dy = -r; dy <= r; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        const n = vec(c.x + dx, c.y + dy);
        if (map.isInBounds(n) && map.isWalkable(n)) return n;
      }
    }
  }
  return c;
}

function teamAnchor(state: GameState, teamId: number): Vec2i {
  const spawns = teamId === TEAM_USA ? state.map.team1Spawns : state.map.team2Spawns;
  if (spawns.length === 0) {
    const soldiers = state.soldiersOnTeam(teamId).filter((s) => !s.isDead);
    if (soldiers.length === 0) return vec(Math.floor(state.map.width / 2), Math.floor(state.map.height / 2));
    let sx = 0, sy = 0;
    for (const s of soldiers) { sx += s.gridPosition.x; sy += s.gridPosition.y; }
    return vec(Math.floor(sx / soldiers.length), Math.floor(sy / soldiers.length));
  }
  let sx = 0, sy = 0;
  for (const p of spawns) { sx += p.x; sy += p.y; }
  return vec(Math.floor(sx / spawns.length), Math.floor(sy / spawns.length));
}

function enemyTeamOf(teamId: number): number {
  return teamId === TEAM_USA ? TEAM_GERMANY : TEAM_USA;
}

/** Check if standing at `stand` puts cover between that cell and `threat`. */
function standCoveredVsThreat(stand: Vec2i, threat: Vec2i, map: GameState["map"]): boolean {
  if (threat.x <= -900 || vecEq(stand, threat)) return false;
  const result = evaluateTargetCover(threat, stand, map);
  return result.inCover;
}

function standIsDirectlyBehind(stand: Vec2i, threat: Vec2i, map: GameState["map"]): boolean {
  if (threat.x <= -900) return false;
  const standD = manhattan(stand, threat);
  const offsets = [vec(1, 0), vec(-1, 0), vec(0, 1), vec(0, -1)];
  for (const off of offsets) {
    const objCell = vec(stand.x + off.x, stand.y + off.y);
    const def = map.getObjectDef(objCell);
    if (def === null || !def.providesCover) continue;
    if (manhattan(objCell, threat) < standD) return true;
  }
  return false;
}

/** Find nearest directional cover stand within maxDist of nearCell. */
function nearestCoverWithin(
  state: GameState,
  nearCell: Vec2i,
  faceToward: Vec2i,
  maxDist: number,
  claimed: Vec2i[] = [],
  rejectClaimed = false,
  preferBehind = false,
): Vec2i {
  const none = vec(-999, -999);
  const map = state.map;
  const requireDir = faceToward.x > -900 && !vecEq(faceToward, nearCell);

  // Collect all cover-providing tiles as candidates
  const byDist = new Map<number, Vec2i[]>();
  for (let y = 0; y < map.height; y++) {
    for (let x = 0; x < map.width; x++) {
      const cell = vec(x, y);
      if (!map.isWalkable(cell)) continue;
      // Check adjacent tiles for cover objects
      let hasCover = false;
      for (const off of [vec(1, 0), vec(-1, 0), vec(0, 1), vec(0, -1)]) {
        const adj = vec(x + off.x, y + off.y);
        const def = map.getObjectDef(adj);
        if (def && def.providesCover) { hasCover = true; break; }
      }
      if (!hasCover) continue;
      const dist = manhattan(cell, nearCell);
      if (dist > maxDist || dist <= 0) continue;
      if (rejectClaimed && claimed.some((c) => vecEq(c, cell))) continue;
      if (!byDist.has(dist)) byDist.set(dist, []);
      byDist.get(dist)!.push(cell);
    }
  }
  if (byDist.size === 0) return none;

  const distances = [...byDist.keys()].sort((a, b) => a - b);
  let best = none;
  let bestScore = 999999;
  let checksThisQuery = 0;

  for (let i = 0; i < distances.length; i++) {
    const dist = distances[i];
    const stands = byDist.get(dist)!;
    stands.sort((a, b) => a.x !== b.x ? a.x - b.x : a.y - b.y);

    for (const stand of stands) {
      if (requireDir) {
        if (checksThisQuery >= MAX_COVER_CHECKS_PER_QUERY) break;
        checksThisQuery++;
        if (!standCoveredVsThreat(stand, faceToward, map)) continue;
      }
      let score = dist + claimPenalty(stand, claimed);
      if (preferBehind && requireDir) {
        if (standIsDirectlyBehind(stand, faceToward, map)) {
          score -= 20;
        } else {
          score += 6;
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = stand;
      }
    }
    if (best.x > -900 && !preferBehind) {
      const nextMin = i + 1 < distances.length ? distances[i + 1] : 999999;
      if (bestScore <= nextMin) return clampWalkable(map, best);
    }
    if (checksThisQuery >= MAX_COVER_CHECKS_PER_QUERY) break;
  }
  return best.x > -900 ? clampWalkable(map, best) : none;
}

function claimPenalty(cell: Vec2i, claimed: Vec2i[]): number {
  let penalty = 0;
  for (const other of claimed) {
    penalty += manhattan(cell, other);
    if (vecEq(cell, other)) penalty += 40;
  }
  penalty += Math.abs(cell.x * 3 + cell.y * 7) % 4;
  return penalty;
}

// ---------------------------------------------------------------------------
// Sector objectives (simplified port)
// ---------------------------------------------------------------------------

function sectorCells(
  map: GameState["map"],
  ownAnchor: Vec2i,
  enemyAnchor: Vec2i,
): { left: Vec2i; center: Vec2i; right: Vec2i } {
  const midX = Math.round((ownAnchor.x + enemyAnchor.x) * 0.5);
  const midY = Math.round((ownAnchor.y + enemyAnchor.y) * 0.5);
  const dx = enemyAnchor.x - ownAnchor.x;
  const dy = enemyAnchor.y - ownAnchor.y;
  const px = -dy;
  const py = dx;
  const plen = Math.max(1, Math.sqrt(px * px + py * py));
  const ox = Math.round((px / plen) * 8);
  const oy = Math.round((py / plen) * 8);
  const towardX = Math.round(dx * 0.35);
  const towardY = Math.round(dy * 0.35);
  return {
    center: clampWalkable(map, vec(midX + towardX, midY + towardY)),
    left: clampWalkable(map, vec(midX + towardX + ox, midY + towardY + oy)),
    right: clampWalkable(map, vec(midX + towardX - ox, midY + towardY - oy)),
  };
}

function defendSectorCells(
  map: GameState["map"],
  ownAnchor: Vec2i,
  enemyAnchor: Vec2i,
): { left: Vec2i; center: Vec2i; right: Vec2i } {
  const dx = enemyAnchor.x - ownAnchor.x;
  const dy = enemyAnchor.y - ownAnchor.y;
  const flen = Math.max(1, Math.sqrt(dx * dx + dy * dy));
  const forwardCells = Math.min(10, Math.max(2, Math.round(flen * 0.2)));
  const lateral = Math.min(8, Math.max(2, forwardCells));
  const fx = Math.round((dx / flen) * forwardCells);
  const fy = Math.round((dy / flen) * forwardCells);
  const px = -dy;
  const py = dx;
  const plen = Math.max(1, Math.sqrt(px * px + py * py));
  const ox = Math.round((px / plen) * lateral);
  const oy = Math.round((py / plen) * lateral);
  const base = vec(ownAnchor.x + fx, ownAnchor.y + fy);
  return {
    center: clampWalkable(map, base),
    left: clampWalkable(map, vec(base.x + ox, base.y + oy)),
    right: clampWalkable(map, vec(base.x - ox, base.y - oy)),
  };
}

function objectivesForPlan(
  state: GameState,
  teamId: number,
  planId: string,
  claimed: Vec2i[],
): AiObjective[] {
  const out: AiObjective[] = [];
  const ownAnchor = teamAnchor(state, teamId);
  const enemyTeam = enemyTeamOf(teamId);
  const enemyAnchor = teamAnchor(state, enemyTeam);

  const sectors = sectorCells(state.map, ownAnchor, enemyAnchor);

  switch (planId) {
    case PLAN_ATTACK_LEFT:
      out.push(makeObj("attack_left", "Attack Left", sectors.left, "sector", 10));
      break;
    case PLAN_ATTACK_CENTER:
      out.push(makeObj("attack_center", "Attack Center", sectors.center, "sector", 10));
      break;
    case PLAN_ATTACK_RIGHT:
      out.push(makeObj("attack_right", "Attack Right", sectors.right, "sector", 10));
      break;
    case PLAN_FLANK: {
      const lp = claimPenalty(sectors.left, claimed);
      const rp = claimPenalty(sectors.right, claimed);
      if (lp <= rp) {
        out.push(makeObj("flank_left", "Flank Left", sectors.left, "sector", 12));
      } else {
        out.push(makeObj("flank_right", "Flank Right", sectors.right, "sector", 12));
      }
      break;
    }
    case PLAN_DEFEND: {
      const dSectors = defendSectorCells(state.map, ownAnchor, enemyAnchor);
      const lanes = [
        { id: "defend_center", label: "Defend Center", cell: dSectors.center, prio: 14 },
        { id: "defend_left", label: "Defend Left", cell: dSectors.left, prio: 12 },
        { id: "defend_right", label: "Defend Right", cell: dSectors.right, prio: 12 },
      ];
      for (const lane of lanes) {
        const cover = nearestCoverWithin(state, lane.cell, enemyAnchor, 12, claimed, true, true);
        const cell = cover.x > -900 ? cover : clampWalkable(state.map, lane.cell);
        out.push(makeObj(lane.id, lane.label, cell, "hold", lane.prio));
        if (cell.x > -900) claimed = [...claimed, cell];
      }
      break;
    }
    default:
      out.push(makeObj("attack_center", "Attack Center", sectors.center, "sector", 5));
      break;
  }

  return out;
}

function selectForClaims(options: AiObjective[], claimed: Vec2i[]): AiObjective | null {
  if (options.length === 0) return null;
  let best: AiObjective | null = null;
  let bestScore = 999999;
  for (const opt of options) {
    if (!objValid(opt)) continue;
    const claim = claimPenalty(opt.cell, claimed);
    const score = claim * 100 - opt.priority;
    if (best === null || score < bestScore) {
      best = opt;
      bestScore = score;
    }
  }
  return best ?? options[0];
}

// ---------------------------------------------------------------------------
// AI Commander
// ---------------------------------------------------------------------------

export class AiCommander {
  readonly playerId: number;
  readonly teamId: number;
  private planId: string;

  private stateId = ST_PLAN;
  private currentObjective: AiObjective | null = null;
  private currentTargetKey = "";
  private lastReplanMsec = -999999;
  private needsReplan = true;
  private commandsThisTick = 0;
  private commandBudget = 2;

  // Cover state
  private settledInCover = false;
  private coverBoundMsec = -999999;
  private coverThreatCell = vec(-999, -999);
  private contactBoundActive = false;

  // Dedup
  private lastMoveCell = vec(-999, -999);
  private lastMoveMsec = -999999;
  private lastFaceCell = vec(-999, -999);
  private lastFaceMsec = -999999;
  private lastFireKey = "";
  private lastFireMsec = -999999;
  private lastSuccessMsec = 0;

  // Defensive posts
  private defensivePosts = new Map<number, Vec2i>();
  private lastOpenProneMsec = -999999;
  private lastStandUpMsec = -999999;
  private boundSoldierIdx = 0;

  // Snapshot (set per tick)
  private snapshot: AiBattlefieldSnapshot | null = null;

  constructor(playerId: number, teamId: number, planId = PLAN_ATTACK_CENTER) {
    this.playerId = playerId;
    this.teamId = teamId;
    this.planId = planId;
  }

  requestReplan(_reason = ""): void {
    this.needsReplan = true;
  }

  /** One think step. Returns claimed objective cell. */
  tick(
    state: GameState,
    findPath: FindPathFn,
    submitCommand: SubmitFn,
    claimedObjectives: Vec2i[],
    nowMsec: number,
    snapshot: AiBattlefieldSnapshot | null = null,
  ): Vec2i {
    this.commandsThisTick = 0;
    this.snapshot = snapshot ?? buildSnapshot(state, [this.playerId]);

    const livingN = this.livingSoldiers(state).length;
    this.commandBudget = Math.max(1, Math.min(livingN, MAX_COMMANDS_PER_TICK));

    const visible = this.snapshot.visibleFor(this.playerId);
    const known = this.snapshot.knownFor(this.playerId);
    const reaction = this.threatsForReaction(state, visible, known);

    if (reaction.length === 0) {
      this.currentTargetKey = "";
    } else {
      this.selectBestThreat(state, reaction);
    }

    this.runWatchdog(state, reaction, nowMsec);

    if (this.needsReplan || (nowMsec - this.lastReplanMsec) >= REPLAN_INTERVAL_MSEC) {
      this.replan(state, claimedObjectives, reaction);
      this.lastReplanMsec = nowMsec;
      this.needsReplan = false;
    }

    this.runState(state, findPath, submitCommand, visible, known, reaction);

    if (this.currentObjective && objValid(this.currentObjective)) {
      return this.currentObjective.cell;
    }
    return vec(-999, -999);
  }

  // -------------------------------------------------------------------------
  // Replan
  // -------------------------------------------------------------------------

  private replan(state: GameState, claimed: Vec2i[], visible: SoldierState[]): void {
    const options = objectivesForPlan(state, this.teamId, this.planId, claimed);
    if (options.length === 0) {
      this.currentObjective = null;
      this.stateId = ST_PLAN;
      return;
    }
    const selected = selectForClaims(options, claimed);
    this.currentObjective = selected ?? options[0];

    if (this.isHoldObjective()) {
      this.assignDefensivePosts(state, options);
    } else {
      this.defensivePosts.clear();
    }

    if (visible.length > 0) {
      if ([ST_PLAN, ST_MOVE, ST_ADVANCE, ST_OBJECTIVE_COMPLETE].includes(this.stateId)) {
        this.stateId = ST_CONTACT;
        this.clearCoverSettlement();
      }
    } else if (this.isHoldObjective() && this.defensivePostsReached(state)) {
      this.stateId = ST_FIGHT;
    } else if (this.stateId === ST_OBJECTIVE_COMPLETE || this.stateId === ST_PLAN) {
      this.stateId = ST_MOVE;
    }
  }

  // -------------------------------------------------------------------------
  // State machine
  // -------------------------------------------------------------------------

  private runState(
    state: GameState,
    findPath: FindPathFn,
    submit: SubmitFn,
    visible: SoldierState[],
    known: SoldierState[],
    reaction: SoldierState[],
  ): void {
    switch (this.stateId) {
      case ST_PLAN:
        this.stateId = ST_MOVE;
        break;

      case ST_MOVE:
      case ST_ADVANCE:
        if (this.hasStragglers(state) && this.rallyStragglers(state, findPath, submit)) {
          return;
        }
        if (reaction.length > 0) {
          this.stateId = ST_CONTACT;
          this.clearCoverSettlement();
          this.engageContact(state, findPath, submit, reaction, visible);
        } else if (this.underSuppression(state)) {
          const approach = this.threatCellOrApproach(state, known);
          const center = this.formationCenter(state);
          const cover = nearestCoverWithin(state, center, approach, COVER_SEEK_MAX_DIST, [], false, true);
          this.tryTakeCover(state, findPath, submit, [], COVER_SEEK_MAX_DIST, this.coverApproachMode(state), cover);
        } else if (!this.fireteamIsMoving(state)) {
          if (this.isHoldObjective() && this.defensivePostsReached(state)) {
            this.holdDefensivePost(state, submit, reaction);
            this.stateId = ST_FIGHT;
          } else if (this.isHoldObjective()) {
            this.moveToDefensivePosts(state, findPath, submit);
            if (this.defensivePostsReached(state)) {
              this.holdDefensivePost(state, submit, reaction);
              this.stateId = ST_FIGHT;
            }
          } else {
            this.moveTowardObjective(state, findPath, submit);
            if (this.objectiveReached(state)) {
              this.stateId = ST_OBJECTIVE_COMPLETE;
              this.requestReplan("objective_complete");
            }
          }
        }
        break;

      case ST_CONTACT:
        this.engageContact(state, findPath, submit, reaction, visible);
        this.stateId = ST_FIGHT;
        break;

      case ST_FIGHT:
        if (reaction.length === 0) {
          this.clearCoverSettlement();
          if (this.isHoldObjective()) {
            if (!this.defensivePostsReached(state)) {
              this.moveToDefensivePosts(state, findPath, submit);
            } else {
              this.holdDefensivePost(state, submit, reaction);
            }
          } else {
            this.stateId = ST_ADVANCE;
            this.requestReplan("contact_lost");
          }
        } else {
          this.engageContact(state, findPath, submit, reaction, visible);
        }
        break;

      case ST_OBJECTIVE_COMPLETE:
        this.stateId = this.isHoldObjective() ? ST_FIGHT : ST_PLAN;
        break;

      default:
        this.stateId = ST_PLAN;
    }
  }

  // -------------------------------------------------------------------------
  // Engage contact
  // -------------------------------------------------------------------------

  private engageContact(
    state: GameState,
    findPath: FindPathFn,
    submit: SubmitFn,
    threats: SoldierState[],
    losTargets: SoldierState[],
  ): void {
    if (threats.length === 0) return;
    const threat = this.selectBestThreat(state, threats);
    if (!threat) return;

    const firePool = losTargets.length > 0 ? losTargets : [];
    const center = this.formationCenter(state);
    const threatCell = threat.gridPosition;
    const threatDist = manhattan(center, threatCell);
    const seekMax = threatDist < CLOSE_RANGE_DIST ? CLOSE_COVER_SEEK_MAX_DIST : COVER_SEEK_MAX_DIST;

    // Halt objective runs on first contact
    if (this.fireteamIsMoving(state) && !this.contactBoundActive) {
      this.haltFireteam(state, submit);
    }

    // Rebound cover if threat shifted
    if (this.settledInCover && !this.fireteamIsMoving(state) && this.shouldReboundCover(state, threatCell)) {
      this.settledInCover = false;
      this.contactBoundActive = false;
    }

    // Seek directional cover
    if (!this.settledInCover) {
      if (this.formationInDirectionalCover(state, threatCell)) {
        this.markCoverSettled(state, threatCell);
      } else {
        if (this.takeCoverIndividually(state, findPath, submit, threatCell, seekMax)) return;
        if (this.contactBoundActive && this.fireteamIsMoving(state)) return;

        let nearbyCover = nearestCoverWithin(state, center, threatCell, seekMax, [], false, true);
        if (nearbyCover.x <= -900 && seekMax < COVER_SEEK_MAX_DIST) {
          nearbyCover = nearestCoverWithin(state, center, threatCell, COVER_SEEK_MAX_DIST, [], false, true);
        }
        if (nearbyCover.x > -900 && !vecEq(nearbyCover, center)) {
          if (this.tryTakeCover(state, findPath, submit, threats, seekMax, this.coverApproachMode(state), nearbyCover)) {
            return;
          }
        }
        this.contactBoundActive = false;
        this.tryStandUpOffCover(state, submit, threatCell);
        this.faceThreat(state, submit, threats);
        this.tryFire(state, submit, firePool);
        return;
      }
    }

    // Still bounding
    if (this.fireteamIsMoving(state) && this.contactBoundActive) {
      this.tryFire(state, submit, firePool);
      return;
    }

    // Prone in cover
    if (this.settledInCover && this.formationInDirectionalCover(state, threatCell)) {
      this.tryGoProne(state, submit, threatCell);
    }

    // Face + fire + grenade
    this.faceThreat(state, submit, threats);
    this.tryFire(state, submit, firePool);
    this.tryGrenade(state, submit, firePool.length > 0 ? firePool : threats);

    // Bounding overwatch
    if (
      this.settledInCover &&
      !this.fireteamIsMoving(state) &&
      !this.objectiveReached(state) &&
      threatDist >= CLOSE_RANGE_DIST &&
      this.hasCommandBudget()
    ) {
      if (!this.tryBoundingOverwatch(state, findPath, submit, threats)) {
        this.tryContactBoundForward(state, findPath, submit, threats);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Movement commands
  // -------------------------------------------------------------------------

  private moveTowardObjective(state: GameState, findPath: FindPathFn, submit: SubmitFn): void {
    if (!this.currentObjective || !objValid(this.currentObjective)) return;
    if (!this.hasCommandBudget()) return;
    if (this.hasStragglers(state)) {
      this.rallyStragglers(state, findPath, submit);
      return;
    }
    if (this.fireteamIsMoving(state)) return;
    if (this.isHoldObjective() && this.defensivePostsReached(state)) return;
    if (this.underSuppression(state)) return;

    const lead = this.leadSoldier(state);
    if (!lead) return;
    const objCell = this.currentObjective.cell;
    if (!state.map.isWalkable(objCell)) return;

    const center = this.formationCenter(state);
    const known = this.snapshot ? this.snapshot.knownFor(this.playerId) : [];
    const enemyAnchor = this.threatCellOrApproach(state, known);

    let target = this.nextAdvanceCoverStand(state, center, objCell, enemyAnchor);
    if (target.x <= -900) target = objCell;
    if (this.moveDedupBlocks(target, lead.gridPosition)) return;

    const mode = this.coverApproachMode(state);
    const success = this.submitMove(state, submit, lead.teamId, lead.soldierId, target, MOVE_SCOPE_SQUAD, mode);
    if (success) {
      this.noteMoveDedup(target);
      this.settledInCover = false;
      this.contactBoundActive = false;
    }
  }

  private rallyStragglers(state: GameState, findPath: FindPathFn, submit: SubmitFn): boolean {
    if (!this.hasCommandBudget()) return false;
    const center = this.formationCenter(state);
    let any = false;
    for (const soldier of this.livingSoldiers(state)) {
      if (!this.hasCommandBudget()) break;
      if (soldier.isMoving) continue;
      const d = chebyshev(soldier.gridPosition, center);
      if (d <= STRAGGLER_CHEBYSHEV) continue;
      let target = center;
      if (!state.map.isWalkable(target)) {
        const step = vec(
          soldier.gridPosition.x + sign(center.x - soldier.gridPosition.x),
          soldier.gridPosition.y + sign(center.y - soldier.gridPosition.y),
        );
        if (state.map.isWalkable(step)) target = step;
        else continue;
      }
      if (vecEq(target, soldier.gridPosition)) continue;
      if (this.moveDedupBlocks(target, soldier.gridPosition)) continue;
      if (this.submitMove(state, submit, soldier.teamId, soldier.soldierId, target, MOVE_SCOPE_SINGLE, MOVEMENT_RUN)) {
        this.noteMoveDedup(target);
        any = true;
      }
    }
    return any;
  }

  private haltFireteam(state: GameState, submit: SubmitFn): boolean {
    if (!this.hasCommandBudget() || !this.fireteamIsMoving(state)) return false;
    const lead = this.leadSoldier(state);
    if (!lead) return false;
    // Halt is implemented as a move to current position (scope squad)
    const success = this.submitMove(state, submit, lead.teamId, lead.soldierId, lead.gridPosition, MOVE_SCOPE_SQUAD, MOVEMENT_RUN);
    if (success) {
      this.contactBoundActive = false;
      this.clearMoveDedup();
    }
    return success;
  }

  // -------------------------------------------------------------------------
  // Cover
  // -------------------------------------------------------------------------

  private tryTakeCover(
    state: GameState,
    findPath: FindPathFn,
    submit: SubmitFn,
    _visible: SoldierState[],
    _seekMax: number,
    mode: number,
    precomputed: Vec2i,
  ): boolean {
    if (!this.hasCommandBudget()) return false;
    if (this.contactBoundActive && this.fireteamIsMoving(state)) return true;

    const cover = precomputed;
    if (cover.x <= -900) return false;
    const center = this.formationCenter(state);
    if (vecEq(cover, center)) return false;

    const lead = this.leadSoldier(state);
    if (!lead) return false;

    if (vecEq(cover, this.lastMoveCell) && !this.dedupExpired(this.lastMoveMsec)) return false;

    if (this.submitMove(state, submit, lead.teamId, lead.soldierId, cover, MOVE_SCOPE_SQUAD, mode)) {
      this.noteMoveDedup(cover);
      this.contactBoundActive = true;
      this.coverBoundMsec = state.clock.getTicksMsec();
      return true;
    }
    return false;
  }

  private takeCoverIndividually(
    state: GameState,
    findPath: FindPathFn,
    submit: SubmitFn,
    threatCell: Vec2i,
    seekMax: number,
  ): boolean {
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length === 0 || threatCell.x <= -900) return false;
    const sorted = [...soldiers].sort((a, b) => a.soldierId - b.soldierId);
    const claimed: Vec2i[] = [];
    for (const s of sorted) {
      if (standCoveredVsThreat(s.gridPosition, threatCell, state.map)) {
        claimed.push({ ...s.gridPosition });
      }
    }
    let issued = false;
    for (const soldier of sorted) {
      if (!this.hasCommandBudget()) break;
      if (soldier.isMoving) continue;
      if (standCoveredVsThreat(soldier.gridPosition, threatCell, state.map)) continue;
      const cover = nearestCoverWithin(state, soldier.gridPosition, threatCell, seekMax, claimed, true, true);
      if (cover.x <= -900 || vecEq(cover, soldier.gridPosition)) continue;
      if (!state.map.isWalkable(cover)) continue;
      if (this.submitMove(state, submit, soldier.teamId, soldier.soldierId, cover, MOVE_SCOPE_SINGLE, this.coverApproachMode(state))) {
        claimed.push({ ...cover });
        this.contactBoundActive = true;
        this.coverBoundMsec = state.clock.getTicksMsec();
        issued = true;
      }
    }
    return issued;
  }

  private tryBoundingOverwatch(
    state: GameState,
    findPath: FindPathFn,
    submit: SubmitFn,
    threats: SoldierState[],
  ): boolean {
    if (!this.hasCommandBudget() || this.isHoldObjective()) return false;
    if (!this.currentObjective || !objValid(this.currentObjective)) return false;
    if (threats.length === 0 || this.fireteamIsMoving(state)) return false;

    const threat = this.selectBestThreat(state, threats);
    if (!threat) return false;
    const threatCell = threat.gridPosition;
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length < 2) return false;

    const sorted = [...soldiers].sort((a, b) => a.soldierId - b.soldierId);
    const obj = this.currentObjective.cell;

    for (let offset = 0; offset < sorted.length; offset++) {
      const idx = (this.boundSoldierIdx + offset) % sorted.length;
      const mover = sorted[idx];
      if (mover.isMoving) continue;
      if (!standCoveredVsThreat(mover.gridPosition, threatCell, state.map)) continue;

      const claimed = sorted.filter((s) => s.soldierId !== mover.soldierId).map((s) => ({ ...s.gridPosition }));
      const cover = nearestCoverWithin(state, mover.gridPosition, threatCell, ADVANCE_BOUND_MAX_DIST, claimed, true, true);
      if (cover.x <= -900 || vecEq(cover, mover.gridPosition) || !state.map.isWalkable(cover)) continue;
      if (!this.coverIsShortOfThreat(mover.gridPosition, cover, threatCell)) continue;

      const oldD = manhattan(mover.gridPosition, obj);
      const newD = manhattan(cover, obj);
      if (newD >= oldD) continue;

      if (this.submitMove(state, submit, mover.teamId, mover.soldierId, cover, MOVE_SCOPE_SINGLE, this.coverApproachMode(state))) {
        this.boundSoldierIdx = idx + 1;
        this.contactBoundActive = true;
        this.coverBoundMsec = state.clock.getTicksMsec();
        return true;
      }
    }
    return false;
  }

  private tryContactBoundForward(
    state: GameState,
    findPath: FindPathFn,
    submit: SubmitFn,
    visible: SoldierState[],
  ): boolean {
    if (visible.length === 0 || !this.currentObjective || !objValid(this.currentObjective)) return false;
    if (this.isHoldObjective()) return false;

    const threat = this.selectBestThreat(state, visible);
    if (!threat) return false;
    const center = this.formationCenter(state);
    const obj = this.currentObjective.cell;
    const oldObjDist = manhattan(center, obj);

    const cover = nearestCoverWithin(state, center, threat.gridPosition, 6, []);
    if (cover.x <= -900) return false;
    if (!this.coverIsShortOfThreat(center, cover, threat.gridPosition)) return false;
    if (manhattan(cover, obj) >= oldObjDist) return false;

    return this.tryTakeCover(state, findPath, submit, visible, 6, this.coverApproachMode(state), cover);
  }

  // -------------------------------------------------------------------------
  // Defensive posts
  // -------------------------------------------------------------------------

  private assignDefensivePosts(state: GameState, _options: AiObjective[]): void {
    this.defensivePosts.clear();
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length === 0 || !this.currentObjective || !objValid(this.currentObjective)) return;

    const primary = this.currentObjective.cell;
    const approach = teamAnchor(state, enemyTeamOf(this.teamId));

    // Find covered stands near the objective
    const candidates: Vec2i[] = [];
    for (let y = 0; y < state.map.height; y++) {
      for (let x = 0; x < state.map.width; x++) {
        const cell = vec(x, y);
        if (chebyshev(cell, primary) > DEFENSIVE_POST_CLUSTER) continue;
        if (!state.map.isWalkable(cell)) continue;
        if (approach.x > -900 && !standCoveredVsThreat(cell, approach, state.map)) continue;
        candidates.push(cell);
        if (candidates.length >= 40) break;
      }
      if (candidates.length >= 40) break;
    }

    // Spread posts with min separation
    const posts: Vec2i[] = [];
    const sorted = [...soldiers].sort((a, b) => a.soldierId - b.soldierId);

    if (candidates.length > 0) {
      candidates.sort((a, b) => manhattan(a, primary) - manhattan(b, primary));
      for (const cand of candidates) {
        if (posts.length >= soldiers.length) break;
        if (posts.some((p) => chebyshev(p, cand) < DEFENSIVE_POST_MIN_SEP)) continue;
        if (chebyshev(cand, primary) > DEFENSIVE_POST_CLUSTER) continue;
        posts.push(cand);
      }
    }
    // Fill with fallbacks
    while (posts.length < soldiers.length) {
      posts.push(primary);
    }

    // Assign nearest post to each soldier
    const used = new Set<number>();
    for (const soldier of sorted) {
      let bestI = -1;
      let bestD = 999999;
      for (let i = 0; i < posts.length; i++) {
        if (used.has(i)) continue;
        const d = manhattan(soldier.gridPosition, posts[i]);
        if (d < bestD) {
          bestD = d;
          bestI = i;
        }
      }
      if (bestI >= 0) {
        used.add(bestI);
        this.defensivePosts.set(soldier.soldierId, posts[bestI]);
      } else {
        this.defensivePosts.set(soldier.soldierId, primary);
      }
    }
  }

  private defensivePostsReached(state: GameState): boolean {
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length === 0) return true;
    if (this.defensivePosts.size === 0) return this.objectiveReached(state);
    const approach = teamAnchor(state, enemyTeamOf(this.teamId));
    for (const soldier of soldiers) {
      if (standCoveredVsThreat(soldier.gridPosition, approach, state.map)) continue;
      const post = this.defensivePosts.get(soldier.soldierId);
      if (post && vecEq(soldier.gridPosition, post)) continue;
      return false;
    }
    return true;
  }

  private moveToDefensivePosts(state: GameState, findPath: FindPathFn, submit: SubmitFn): void {
    if (this.defensivePosts.size === 0) {
      this.assignDefensivePosts(state, this.currentObjective ? [this.currentObjective] : []);
    }
    if (this.defensivePosts.size === 0) {
      this.moveTowardObjective(state, findPath, submit);
      return;
    }
    if (!this.hasCommandBudget()) return;
    const approach = teamAnchor(state, enemyTeamOf(this.teamId));
    const sorted = [...this.livingSoldiers(state)].sort((a, b) => a.soldierId - b.soldierId);

    for (const soldier of sorted) {
      if (!this.hasCommandBudget()) return;
      if (soldier.isMoving) continue;
      if (standCoveredVsThreat(soldier.gridPosition, approach, state.map)) continue;
      const post = this.defensivePosts.get(soldier.soldierId);
      if (!post || post.x <= -900) continue;
      if (manhattan(soldier.gridPosition, post) <= COVER_POST_ARRIVE_DIST) continue;
      if (!state.map.isWalkable(post)) continue;
      if (this.submitMove(state, submit, soldier.teamId, soldier.soldierId, post, MOVE_SCOPE_SINGLE, MOVEMENT_RUN)) {
        this.noteMoveDedup(post);
      }
    }
  }

  private holdDefensivePost(state: GameState, submit: SubmitFn, threats: SoldierState[]): void {
    if (threats.length > 0) {
      const threat = this.selectBestThreat(state, threats);
      if (!threat) return;
      this.faceThreat(state, submit, [threat]);
      this.tryGoProne(state, submit, threat.gridPosition);
      return;
    }
    const approach = teamAnchor(state, enemyTeamOf(this.teamId));
    if (approach.x <= -900 || !this.hasCommandBudget()) return;
    const lead = this.leadSoldier(state);
    if (!lead) return;
    if (this.faceDedupBlocks(approach)) return;
    this.submitFace(state, submit, lead.teamId, lead.soldierId, approach, MOVE_SCOPE_SQUAD);
    this.tryGoProne(state, submit, approach);
  }

  // -------------------------------------------------------------------------
  // Combat commands
  // -------------------------------------------------------------------------

  private faceThreat(state: GameState, submit: SubmitFn, visible: SoldierState[]): void {
    if (visible.length === 0 || !this.hasCommandBudget()) return;
    const threat = this.selectBestThreat(state, visible);
    if (!threat) return;
    const lead = this.leadSoldier(state);
    if (!lead) return;
    if (this.faceDedupBlocks(threat.gridPosition)) return;
    this.submitFace(state, submit, lead.teamId, lead.soldierId, threat.gridPosition, MOVE_SCOPE_SQUAD);
  }

  private tryFire(state: GameState, submit: SubmitFn, visible: SoldierState[]): void {
    if (visible.length === 0 || !this.hasCommandBudget()) return;
    const threat = this.selectBestThreat(state, visible);
    if (!threat) return;
    const lead = this.leadSoldier(state);
    if (!lead) return;
    const fireKey = `${threat.teamId}:${threat.soldierId}`;
    if (this.fireteamAlreadyEngaging(state, threat)) {
      this.currentTargetKey = fireKey;
      return;
    }
    if (fireKey === this.lastFireKey && !this.dedupExpired(this.lastFireMsec)) return;

    const success = this.submitAi(submit, {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: `ai-fire-${this.playerId}-${state.clock.getTicksMsec()}`,
      teamId: lead.teamId,
      soldierId: lead.soldierId,
      targetTeamId: threat.teamId,
      targetSoldierId: threat.soldierId,
      scope: MOVE_SCOPE_SQUAD,
    });
    if (success) {
      this.lastFireKey = fireKey;
      this.lastFireMsec = state.clock.getTicksMsec();
      this.clearMoveDedup();
      this.currentTargetKey = fireKey;
    }
  }

  private tryGrenade(state: GameState, submit: SubmitFn, visible: SoldierState[]): void {
    if (visible.length === 0 || !this.hasCommandBudget()) return;
    const threat = this.selectBestThreat(state, visible);
    if (!threat) return;

    const impact = threat.gridPosition;
    let cluster = 0;
    for (const enemy of visible) {
      if (chebyshev(enemy.gridPosition, impact) <= GRENADE_CLUSTER_CHEBYSHEV) {
        cluster++;
      }
    }
    if (cluster < 2) return;

    // Friendly fire check (simplified: check own soldiers in blast)
    for (const own of state.soldiersOnTeam(this.teamId)) {
      if (own.isDead) continue;
      const dist = Math.sqrt(
        (own.gridPosition.x - impact.x) ** 2 + (own.gridPosition.y - impact.y) ** 2,
      );
      if (dist <= 2.0) return; // Would hit friendly
    }

    for (const soldier of this.livingSoldiers(state)) {
      if (soldier.grenadeCount <= 0 || soldier.hasPendingGrenade()) continue;
      if (chebyshev(soldier.gridPosition, impact) > GRENADE_THROW_RANGE) continue;
      this.submitAi(submit, {
        type: "grenade_command",
        matchId: MATCH_ID,
        requestId: `ai-grenade-${this.playerId}-${state.clock.getTicksMsec()}`,
        teamId: soldier.teamId,
        soldierId: soldier.soldierId,
        targetCell: { ...impact },
      });
      break;
    }
  }

  private tryGoProne(state: GameState, submit: SubmitFn, threatOrApproach: Vec2i): void {
    if (!this.hasCommandBudget() || threatOrApproach.x <= -900) return;
    const now = state.clock.getTicksMsec();
    const allowOpenProne =
      this.underHeavyFire(state) &&
      now - this.lastOpenProneMsec >= OPEN_PRONE_COOLDOWN_MSEC &&
      Math.random() < OPEN_PRONE_CHANCE;

    for (const soldier of this.livingSoldiers(state)) {
      if (!this.hasCommandBudget()) return;
      if (soldier.positionState === POSITION_DOWN) continue;
      if (soldier.pendingPositionState >= 0 || soldier.isMoving) continue;
      const covered = standCoveredVsThreat(soldier.gridPosition, threatOrApproach, state.map);
      if (!covered && !allowOpenProne) continue;
      this.submitPosition(state, submit, soldier.teamId, soldier.soldierId, POSITION_DOWN);
    }
  }

  private tryStandUpOffCover(state: GameState, submit: SubmitFn, threatCell: Vec2i): boolean {
    if (!this.hasCommandBudget() || threatCell.x <= -900) return false;
    const now = state.clock.getTicksMsec();
    if (now - this.lastStandUpMsec < STAND_UP_COOLDOWN_MSEC) return false;
    for (const soldier of this.livingSoldiers(state)) {
      if (soldier.positionState !== POSITION_DOWN) continue;
      if (soldier.pendingPositionState >= 0 || soldier.isMoving) continue;
      if (standCoveredVsThreat(soldier.gridPosition, threatCell, state.map)) continue;
      if (this.submitPosition(state, submit, soldier.teamId, soldier.soldierId, POSITION_UP)) {
        this.lastStandUpMsec = now;
        return true;
      }
      return false;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Threat selection
  // -------------------------------------------------------------------------

  private selectBestThreat(state: GameState, visible: SoldierState[]): SoldierState | null {
    if (visible.length === 0) return null;
    const from = this.leadSoldier(state)?.gridPosition ?? this.formationCenter(state);
    let best: SoldierState | null = null;
    let bestScore = -999999;
    let bestTeam = 999;
    let bestSid = 999;

    for (const enemy of visible) {
      if (enemy.isDead) continue;
      let score = 0;
      const dist = manhattan(from, enemy.gridPosition);
      score += Math.max(0, 40 - dist) * 3;
      if (enemy.positionState !== POSITION_DOWN) score += 12;
      const coverResult = evaluateTargetCover(from, enemy.gridPosition, state.map);
      if (!coverResult.inCover) score += 18;
      if (enemy.sustainedFire) {
        for (const ours of this.livingSoldiers(state)) {
          if (enemy.engagedTargetTeamId === ours.teamId && enemy.engagedTargetSoldierId === ours.soldierId) {
            score += 10;
            break;
          }
        }
      }
      if (enemy.stress >= 40 || enemy.ammoCurrent <= 2) score += 6;

      if (
        score > bestScore ||
        (score === bestScore && enemy.teamId < bestTeam) ||
        (score === bestScore && enemy.teamId === bestTeam && enemy.soldierId < bestSid)
      ) {
        best = enemy;
        bestScore = score;
        bestTeam = enemy.teamId;
        bestSid = enemy.soldierId;
      }
    }

    if (best) this.currentTargetKey = `${best.teamId}:${best.soldierId}`;
    return best;
  }

  private threatsForReaction(state: GameState, visible: SoldierState[], known: SoldierState[]): SoldierState[] {
    const out: SoldierState[] = [];
    const seen = new Set<string>();
    for (const enemy of visible) {
      if (enemy.isDead) continue;
      seen.add(`${enemy.teamId}:${enemy.soldierId}`);
      out.push(enemy);
    }
    const center = this.formationCenter(state);
    for (const enemy of known) {
      if (enemy.isDead) continue;
      const key = `${enemy.teamId}:${enemy.soldierId}`;
      if (seen.has(key)) continue;
      if (manhattan(center, enemy.gridPosition) > CONTACT_REACT_DIST) continue;
      out.push(enemy);
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Helper queries
  // -------------------------------------------------------------------------

  private formationCenter(state: GameState): Vec2i {
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length === 0) return vec(0, 0);
    let sx = 0, sy = 0;
    for (const s of soldiers) { sx += s.gridPosition.x; sy += s.gridPosition.y; }
    return vec(Math.floor(sx / soldiers.length), Math.floor(sy / soldiers.length));
  }

  private livingSoldiers(state: GameState): SoldierState[] {
    if (this.snapshot) return this.snapshot.livingFor(this.playerId);
    const nowMsec = state.clock.getTicksMsec();
    return state.soldiersOnTeam(this.teamId).filter((s) => !s.isDead && !s.isStunned(nowMsec));
  }

  private fireteamIsMoving(state: GameState): boolean {
    return this.livingSoldiers(state).some((s) => s.isMoving);
  }

  private leadSoldier(state: GameState): SoldierState | null {
    const soldiers = this.livingSoldiers(state);
    return soldiers.length > 0 ? soldiers[0] : null;
  }

  private objectiveReached(state: GameState): boolean {
    if (!this.currentObjective || !objValid(this.currentObjective)) return false;
    return manhattan(this.formationCenter(state), this.currentObjective.cell) <= OBJECTIVE_ARRIVE_DIST;
  }

  private isHoldObjective(): boolean {
    if (!this.currentObjective || !objValid(this.currentObjective)) return false;
    return this.currentObjective.kind === "hold" || this.currentObjective.kind === "cover";
  }

  private underSuppression(state: GameState): boolean {
    return this.avgStress(state) >= STRESS_COVER_PRIORITY;
  }

  private underHeavyFire(state: GameState): boolean {
    return this.avgStress(state) >= STRESS_HEAVY_FIRE;
  }

  private avgStress(state: GameState): number {
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length === 0) return 0;
    let total = 0;
    for (const s of soldiers) total += s.stress;
    return total / soldiers.length;
  }

  private coverApproachMode(state: GameState): number {
    return this.underHeavyFire(state) ? MOVEMENT_CRAWL : MOVEMENT_RUN;
  }

  private hasStragglers(state: GameState): boolean {
    const center = this.formationCenter(state);
    return this.livingSoldiers(state).some(
      (s) => !s.isMoving && chebyshev(s.gridPosition, center) > STRAGGLER_CHEBYSHEV,
    );
  }

  private fireteamAlreadyEngaging(state: GameState, threat: SoldierState): boolean {
    let engaged = 0;
    let ready = 0;
    for (const s of this.livingSoldiers(state)) {
      if (s.ammoCurrent <= 0) continue;
      ready++;
      if (s.sustainedFire && s.engagedTargetTeamId === threat.teamId && s.engagedTargetSoldierId === threat.soldierId) {
        engaged++;
      }
    }
    return ready > 0 && engaged >= ready;
  }

  private threatCellOrApproach(state: GameState, known: SoldierState[]): Vec2i {
    const threat = this.selectBestThreat(state, known);
    if (threat) return threat.gridPosition;
    return teamAnchor(state, enemyTeamOf(this.teamId));
  }

  private formationInDirectionalCover(state: GameState, threatCell: Vec2i): boolean {
    if (threatCell.x <= -900) return false;
    const soldiers = this.livingSoldiers(state);
    if (soldiers.length === 0) return false;
    return soldiers.every((s) => standCoveredVsThreat(s.gridPosition, threatCell, state.map));
  }

  private nextAdvanceCoverStand(
    state: GameState,
    fromCell: Vec2i,
    objectiveCell: Vec2i,
    enemyAnchor: Vec2i,
  ): Vec2i {
    const oldDist = manhattan(fromCell, objectiveCell);
    if (oldDist <= ADVANCE_BOUND_MAX_DIST) return vec(-999, -999);
    const face = enemyAnchor.x > -900 ? enemyAnchor : objectiveCell;
    const cover = nearestCoverWithin(state, fromCell, face, ADVANCE_BOUND_MAX_DIST);
    if (cover.x <= -900) return vec(-999, -999);
    const step = manhattan(cover, fromCell);
    if (step < ADVANCE_BOUND_MIN_DIST) return vec(-999, -999);
    if (manhattan(cover, objectiveCell) >= oldDist) return vec(-999, -999);
    return cover;
  }

  private coverIsShortOfThreat(fromCell: Vec2i, cover: Vec2i, threatCell: Vec2i): boolean {
    if (cover.x <= -900 || threatCell.x <= -900) return false;
    if (manhattan(cover, threatCell) < CONTACT_THREAT_STANDOFF) return false;
    const toThreat = vec(threatCell.x - fromCell.x, threatCell.y - fromCell.y);
    const threatToCover = vec(cover.x - threatCell.x, cover.y - threatCell.y);
    return (toThreat.x * threatToCover.x + toThreat.y * threatToCover.y) <= 0;
  }

  // -------------------------------------------------------------------------
  // Cover settlement tracking
  // -------------------------------------------------------------------------

  private clearCoverSettlement(): void {
    this.settledInCover = false;
    this.coverThreatCell = vec(-999, -999);
    this.contactBoundActive = false;
  }

  private markCoverSettled(state: GameState, threatCell: Vec2i): void {
    this.settledInCover = true;
    this.contactBoundActive = false;
    this.coverThreatCell = { ...threatCell };
    this.coverBoundMsec = state.clock.getTicksMsec();
  }

  private shouldReboundCover(state: GameState, threatCell: Vec2i): boolean {
    const now = state.clock.getTicksMsec();
    if (now - this.coverBoundMsec < REPLAN_INTERVAL_MSEC) return false;
    if (!this.formationInDirectionalCover(state, threatCell)) return true;
    if (now - this.coverBoundMsec >= COVER_RESETTLE_MSEC) return true;
    if (this.coverThreatCell.x <= -900) return false;
    return chebyshev(threatCell, this.coverThreatCell) >= COVER_THREAT_SHIFT_CHEBYSHEV;
  }

  // -------------------------------------------------------------------------
  // Dedup / watchdog
  // -------------------------------------------------------------------------

  private hasCommandBudget(): boolean {
    return this.commandsThisTick < this.commandBudget;
  }

  private dedupExpired(stampMsec: number): boolean {
    return stampMsec < 0 || Date.now() - stampMsec >= DEDUP_EXPIRE_MSEC;
  }

  private clearMoveDedup(): void {
    this.lastMoveCell = vec(-999, -999);
    this.lastMoveMsec = -999999;
  }

  private noteMoveDedup(cell: Vec2i): void {
    this.lastMoveCell = { ...cell };
    this.lastMoveMsec = Date.now();
  }

  private moveDedupBlocks(target: Vec2i, leadCell: Vec2i): boolean {
    if (!vecEq(target, this.lastMoveCell) || this.dedupExpired(this.lastMoveMsec)) return false;
    if (manhattan(leadCell, target) <= OBJECTIVE_ARRIVE_DIST) return true;
    this.clearMoveDedup();
    return false;
  }

  private faceDedupBlocks(cell: Vec2i): boolean {
    if (!vecEq(cell, this.lastFaceCell) || this.dedupExpired(this.lastFaceMsec)) return false;
    return true;
  }

  private clearAllDedup(): void {
    this.clearMoveDedup();
    this.lastFaceCell = vec(-999, -999);
    this.lastFaceMsec = -999999;
    this.lastFireKey = "";
    this.lastFireMsec = -999999;
  }

  private runWatchdog(state: GameState, visible: SoldierState[], nowMsec: number): void {
    if (this.lastSuccessMsec <= 0) {
      this.lastSuccessMsec = nowMsec;
      return;
    }
    if (nowMsec - this.lastSuccessMsec < WATCHDOG_IDLE_MSEC) return;
    if (this.fireteamIsMoving(state)) return;
    if (visible.length > 0) return;
    this.clearAllDedup();
    this.requestReplan("watchdog");
  }

  // -------------------------------------------------------------------------
  // Submit helpers
  // -------------------------------------------------------------------------

  private submitAi(submit: SubmitFn, command: Record<string, unknown>): boolean {
    if (!this.hasCommandBudget()) return false;
    const result = submit(command);
    if (!result.success) return false;
    this.commandsThisTick++;
    this.lastSuccessMsec = Date.now();
    return true;
  }

  private submitMove(
    state: GameState,
    submit: SubmitFn,
    teamId: number,
    soldierId: number,
    targetCell: Vec2i,
    scope: number,
    mode: number,
  ): boolean {
    return this.submitAi(submit, {
      type: "move_command",
      matchId: MATCH_ID,
      requestId: `ai-move-${this.playerId}-${state.clock.getTicksMsec()}-${soldierId}`,
      teamId,
      soldierId,
      targetCell: { ...targetCell },
      scope,
      movementMode: mode,
    });
  }

  private submitFace(
    state: GameState,
    submit: SubmitFn,
    teamId: number,
    soldierId: number,
    targetCell: Vec2i,
    scope: number,
  ): boolean {
    const success = this.submitAi(submit, {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: `ai-face-${this.playerId}-${state.clock.getTicksMsec()}`,
      teamId,
      soldierId,
      targetCell: { ...targetCell },
      scope,
      aimWorld: null,
    });
    if (success) {
      this.lastFaceCell = { ...targetCell };
      this.lastFaceMsec = Date.now();
    }
    return success;
  }

  private submitPosition(
    state: GameState,
    submit: SubmitFn,
    teamId: number,
    soldierId: number,
    positionState: number,
  ): boolean {
    return this.submitAi(submit, {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: `ai-pos-${this.playerId}-${state.clock.getTicksMsec()}-${soldierId}`,
      teamId,
      soldierId,
      positionState,
    });
  }
}
