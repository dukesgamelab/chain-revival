import type { GameState } from "./game_state";
import type { Vec2i } from "./types";

export interface ReplayEvent {
  t: number;
  type: string;
  data: unknown;
}

export interface ReplayInitialState {
  map: {
    id: string;
    width: number;
    height: number;
    blockedTiles: Vec2i[];
    tiles: Array<{ x: number; y: number; type: string; blocksLos: boolean; cover: number }>;
    victoryPoints: Array<{ x: number; y: number; holder: string }>;
  };
  soldiers: Array<{
    id: number;
    teamId: number;
    position: Vec2i;
    facing: Vec2i;
  }>;
}

export interface ReplayData {
  initialState: ReplayInitialState;
  events: ReplayEvent[];
  durationMs: number;
}

const RECORDED_EVENT_TYPES = new Set([
  "move_result",
  "face_result",
  "position_result",
  "fire_at_result",
  "fire_control_result",
  "grenade_result",
  "grenade_explode",
  "combat_shots",
  "deployment_ended",
  "match_ended",
]);

export class ReplayRecorder {
  private events: ReplayEvent[] = [];
  private initialState: ReplayInitialState | null = null;
  private startMs = 0;

  captureInitialState(gs: GameState): void {
    const map = gs.map;
    const blockedTiles: Vec2i[] = [];
    const tiles: ReplayInitialState["map"]["tiles"] = [];

    for (let y = 0; y < map.height; y++) {
      for (let x = 0; x < map.width; x++) {
        const cell = { x, y };
        if (map.isBlocked(cell)) {
          blockedTiles.push(cell);
          const tile = map.getTile(cell);
          if (tile) {
            tiles.push({ x, y, type: tile.typeId, blocksLos: tile.blocksLos, cover: tile.coverType });
          }
        }
      }
    }

    this.initialState = {
      map: {
        id: map.mapId,
        width: map.width,
        height: map.height,
        blockedTiles,
        tiles,
        victoryPoints: map.victoryPoints.map(vp => ({
          x: vp.x,
          y: vp.y,
          holder: vp.holder,
        })),
      },
      soldiers: gs.soldiers.map(s => ({
        id: s.soldierId,
        teamId: s.teamId,
        position: { ...s.gridPosition },
        facing: { ...s.facing },
      })),
    };
    this.startMs = gs.clock.getTicksMsec();
  }

  recordBroadcast(payload: unknown): void {
    if (typeof payload !== "object" || payload === null) return;
    const msg = payload as Record<string, unknown>;
    const type = msg.type as string;
    if (!RECORDED_EVENT_TYPES.has(type)) return;

    this.events.push({
      t: (msg.simMsec as number) ?? 0,
      type,
      data: payload,
    });
  }

  getReplayData(): ReplayData | null {
    if (!this.initialState) return null;
    const lastEvent = this.events[this.events.length - 1];
    const durationMs = lastEvent ? lastEvent.t - this.startMs : 0;
    return {
      initialState: this.initialState,
      events: this.events,
      durationMs: Math.max(0, durationMs),
    };
  }
}
