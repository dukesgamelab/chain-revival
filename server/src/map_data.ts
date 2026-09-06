/**
 * Walkability grid loaded from the existing map JSON.
 * Clients load the same map locally by mapId — we do not send tile art.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { type Vec2i, vec, vecKey } from "./types";

export class MapData {
  readonly mapId: string;
  readonly width: number;
  readonly height: number;
  readonly team1Spawns: Vec2i[];
  readonly team2Spawns: Vec2i[];
  private readonly blocked = new Set<string>();

  constructor(
    mapId: string,
    width: number,
    height: number,
    blockedTiles: Vec2i[],
    team1Spawns: Vec2i[],
    team2Spawns: Vec2i[],
  ) {
    this.mapId = mapId;
    this.width = width;
    this.height = height;
    this.team1Spawns = team1Spawns;
    this.team2Spawns = team2Spawns;
    for (const cell of blockedTiles) {
      this.blocked.add(vecKey(cell));
    }
  }

  static loadFromRepo(mapId: string): MapData {
    const repoRoot = resolve(__dirname, "../..");
    const filePath = resolve(repoRoot, "maps", `${mapId}.json`);
    const raw = JSON.parse(readFileSync(filePath, "utf8")) as Record<string, unknown>;
    const width = Number(raw.width ?? 0);
    const height = Number(raw.height ?? 0);
    const blockedTiles = cellsFromJson(raw.blocked_tiles);
    const team1 = cellsFromJson(raw.team_1_spawn_points);
    const team2 = cellsFromJson(raw.team_2_spawn_points);
    return new MapData(mapId, width, height, blockedTiles, team1, team2);
  }

  isInBounds(cell: Vec2i): boolean {
    return cell.x >= 0 && cell.y >= 0 && cell.x < this.width && cell.y < this.height;
  }

  clampToBounds(cell: Vec2i): Vec2i {
    if (this.width <= 0 || this.height <= 0) {
      return cell;
    }
    return vec(
      clampInt(cell.x, 0, this.width - 1),
      clampInt(cell.y, 0, this.height - 1),
    );
  }

  isBlocked(cell: Vec2i): boolean {
    if (!this.isInBounds(cell)) {
      return true;
    }
    return this.blocked.has(vecKey(cell));
  }

  isWalkable(cell: Vec2i): boolean {
    return this.isInBounds(cell) && !this.isBlocked(cell);
  }
}

function clampInt(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value));
}

function cellsFromJson(value: unknown): Vec2i[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const out: Vec2i[] = [];
  for (const entry of value) {
    if (typeof entry !== "object" || entry === null) {
      continue;
    }
    const rec = entry as Record<string, unknown>;
    out.push(vec(Number(rec.x ?? 0), Number(rec.y ?? 0)));
  }
  return out;
}
