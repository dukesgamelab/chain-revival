/**
 * Walkability + gameplay obstruction grid from map JSON / asset-registry gameplay.
 * No sprites, hotspots, or render offsets.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  COVER_COMPLETE,
  COVER_MODERATE,
  COVER_NONE,
  getObjectDef,
  loadFamilyGameplay,
  normalizeTypeId,
  parseTerrainClass,
  TERRAIN_CLIMB,
  TERRAIN_EVEN,
  TERRAIN_NO_PASS,
  type ObjectDef,
} from "./map_objects";
import { type Vec2i, vec, vecKey } from "./types";

export interface MapMetadata {
  displayName: string;
  description: string;
  supportedTeamSizes: number[];
  soldiersPerPlayer: number;
}

export interface TileGameplay {
  typeId: string;
  family: string;
  height: number;
  terrainClass: number;
  blocksLos: boolean;
  providesCover: boolean;
  coverType: number;
}

export class MapData {
  readonly mapId: string;
  readonly width: number;
  readonly height: number;
  readonly team1Spawns: Vec2i[];
  readonly team2Spawns: Vec2i[];
  readonly metadata: MapMetadata;
  readonly victoryPoints: Array<{
    x: number;
    y: number;
    holder: string;
    initialHolder: string;
    captureElapsedSec: number;
    usPoints: number;
    gmPoints: number;
  }>;
  private readonly blocked = new Set<string>();
  private readonly tiles = new Map<string, TileGameplay>();

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
    this.metadata = { displayName: mapId, description: "", supportedTeamSizes: [1], soldiersPerPlayer: 4 };
    this.victoryPoints = [];
    for (const cell of blockedTiles) {
      this.blocked.add(vecKey(cell));
    }
  }

  static empty(width = 24, height = 24, mapId = "test_los"): MapData {
    return new MapData(
      mapId,
      width,
      height,
      [],
      [vec(2, 2), vec(3, 2), vec(4, 2), vec(5, 2)],
      [vec(2, 10), vec(3, 10), vec(4, 10), vec(5, 10)],
    );
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
    const map = new MapData(mapId, width, height, blockedTiles, team1, team2);
    // Parse metadata from map JSON.
    const meta = raw.metadata;
    if (typeof meta === "object" && meta !== null) {
      const m = meta as Record<string, unknown>;
      map.metadata.displayName = String(m.display_name ?? mapId);
      map.metadata.description = String(m.description ?? "");
      if (Array.isArray(m.supported_team_sizes)) {
        map.metadata.supportedTeamSizes = m.supported_team_sizes.map(Number);
      }
      if (m.soldiers_per_player !== undefined) {
        map.metadata.soldiersPerPlayer = Number(m.soldiers_per_player);
      }
    }
    // Parse victory points from map JSON.
    const vpRaw = raw.victory_points;
    if (Array.isArray(vpRaw)) {
      for (const entry of vpRaw) {
        if (typeof entry !== "object" || entry === null) continue;
        const vp = entry as Record<string, unknown>;
        map.victoryPoints.push({
          x: Number(vp.x ?? -999),
          y: Number(vp.y ?? -999),
          holder: String(vp.holder ?? vp.initial_holder ?? "Germany"),
          initialHolder: String(vp.initial_holder ?? "Germany"),
          captureElapsedSec: 0,
          usPoints: Number(vp.us_points ?? 0),
          gmPoints: Number(vp.gm_points ?? 0),
        });
      }
    }
    const objects = raw.map_objects;
    if (Array.isArray(objects) && objects.length > 0) {
      for (const entry of objects) {
        if (typeof entry !== "object" || entry === null) {
          continue;
        }
        map.ingestObject(entry as Record<string, unknown>);
      }
    } else if (raw.apply_terrain_gameplay !== false) {
      for (const cell of blockedTiles) {
        map.placeObject(cell, "tree", "");
      }
    }
    return map;
  }

  /** Test/helper: author a gameplay tile without presentation data. */
  placeObject(cell: Vec2i, typeId: string, family = "", overrides: Record<string, unknown> = {}): void {
    const tile = resolveTile(typeId, family, overrides);
    if (tile !== null) {
      this.tiles.set(vecKey(cell), tile);
    }
  }

  private ingestObject(entry: Record<string, unknown>): void {
    const grid = entry.grid_position;
    let x = Number(entry.x ?? 0);
    let y = Number(entry.y ?? 0);
    if (typeof grid === "object" && grid !== null) {
      const rec = grid as Record<string, unknown>;
      x = Number(rec.x ?? x);
      y = Number(rec.y ?? y);
    }
    const cell = vec(x, y);
    if (!this.isInBounds(cell)) {
      return;
    }
    const typeId = String(entry.object_type ?? entry.type ?? "coc_blocker");
    const source =
      typeof entry.source === "object" && entry.source !== null
        ? (entry.source as Record<string, unknown>)
        : {};
    const family = String(source.image ?? "").toUpperCase();
    const overrides =
      typeof entry.gameplay_overrides === "object" && entry.gameplay_overrides !== null
        ? (entry.gameplay_overrides as Record<string, unknown>)
        : typeof source.gameplay_overrides === "object" && source.gameplay_overrides !== null
          ? (source.gameplay_overrides as Record<string, unknown>)
          : {};
    this.placeObject(cell, typeId, family, overrides);
  }

  isInBounds(cell: Vec2i): boolean {
    return cell.x >= 0 && cell.y >= 0 && cell.x < this.width && cell.y < this.height;
  }

  clampToBounds(cell: Vec2i): Vec2i {
    if (this.width <= 0 || this.height <= 0) {
      return cell;
    }
    return vec(clampInt(cell.x, 0, this.width - 1), clampInt(cell.y, 0, this.height - 1));
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

  hasObject(cell: Vec2i): boolean {
    return this.tiles.has(vecKey(cell));
  }

  getTile(cell: Vec2i): TileGameplay | null {
    return this.tiles.get(vecKey(cell)) ?? null;
  }

  getObjectDef(cell: Vec2i): ObjectDef | null {
    const tile = this.getTile(cell);
    if (tile === null) {
      return null;
    }
    return {
      typeId: tile.typeId,
      blocksLos: tile.blocksLos,
      providesCover: tile.providesCover,
      coverType: tile.coverType,
    };
  }

  obstructionHeight(cell: Vec2i): number {
    if (!this.isInBounds(cell)) {
      return 0;
    }
    return this.getTile(cell)?.height ?? 0;
  }

  terrainClass(cell: Vec2i): number {
    if (!this.isInBounds(cell)) {
      return TERRAIN_EVEN;
    }
    return this.getTile(cell)?.terrainClass ?? TERRAIN_EVEN;
  }

  /** Height 2 always blocks. Height 1 blocks only a prone observer. */
  blocksVision(cell: Vec2i, observerProne = false, _targetProne = false): boolean {
    const height = this.obstructionHeight(cell);
    if (height >= 2) {
      return true;
    }
    if (height === 1) {
      return observerProne;
    }
    return false;
  }
}

function resolveTile(
  typeId: string,
  family: string,
  overrides: Record<string, unknown>,
): TileGameplay | null {
  const id = normalizeTypeId(typeId);
  const fam = family.toUpperCase();
  const familyGp = fam.length > 0 ? loadFamilyGameplay().get(fam) : undefined;
  const def = getObjectDef(id);
  if (def === null && familyGp === undefined) {
    return null;
  }
  const blocksLos = boolOverride(
    overrides.blocks_los,
    familyGp?.blocksLos ?? def?.blocksLos ?? true,
  );
  const providesCover = boolOverride(
    overrides.provides_cover,
    familyGp?.providesCover ?? def?.providesCover ?? true,
  );
  const coverType = intOverride(
    overrides.cover_type,
    familyGp?.coverType ?? def?.coverType ?? COVER_NONE,
    0,
    2,
  );
  let terrainClass = familyGp?.terrainClass ?? TERRAIN_EVEN;
  if (typeof overrides.terrain === "string") {
    terrainClass = parseTerrainClass(overrides.terrain);
  }
  let height: number;
  if (overrides.terrain_height !== undefined) {
    height = clampInt(Number(overrides.terrain_height), 0, 2);
  } else if (familyGp?.terrainHeight !== undefined) {
    height = familyGp.terrainHeight;
  } else if (def !== null) {
    if (def.blocksLos || def.coverType >= COVER_COMPLETE) {
      height = 2;
    } else if (def.providesCover) {
      height = 1;
    } else if (terrainClass === TERRAIN_NO_PASS) {
      height = 2;
    } else if (terrainClass === TERRAIN_CLIMB) {
      height = 1;
    } else {
      height = 0;
    }
  } else if (terrainClass === TERRAIN_NO_PASS) {
    height = 2;
  } else if (terrainClass === TERRAIN_CLIMB) {
    height = 1;
  } else {
    height = 0;
  }
  return {
    typeId: def?.typeId ?? id,
    family: fam,
    height,
    terrainClass,
    blocksLos,
    providesCover,
    coverType: coverType === COVER_MODERATE || coverType === COVER_COMPLETE ? coverType : COVER_NONE,
  };
}

function boolOverride(raw: unknown, fallback: boolean): boolean {
  return raw !== undefined ? Boolean(raw) : fallback;
}

function intOverride(raw: unknown, fallback: number, lo: number, hi: number): number {
  return raw !== undefined ? clampInt(Number(raw), lo, hi) : fallback;
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
