/**
 * Gameplay-only object defs + CoC family heights.
 * No sprites, hotspots, or render offsets.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export const COVER_NONE = 0;
export const COVER_MODERATE = 1;
export const COVER_COMPLETE = 2;

export const TERRAIN_EVEN = 0;
export const TERRAIN_CLIMB = 1;
export const TERRAIN_NO_PASS = 2;

export interface ObjectDef {
  typeId: string;
  blocksLos: boolean;
  providesCover: boolean;
  coverType: number;
}

export interface FamilyGameplay {
  terrainHeight?: number;
  terrainClass?: number;
  blocksLos?: boolean;
  providesCover?: boolean;
  coverType?: number;
}

const DEFS = new Map<string, ObjectDef>();

function def(
  typeId: string,
  blocksLos: boolean,
  providesCover: boolean,
  coverType: number,
): ObjectDef {
  return { typeId, blocksLos, providesCover, coverType };
}

function seedDefs(): void {
  if (DEFS.size > 0) {
    return;
  }
  DEFS.set("tree", def("tree", true, true, COVER_MODERATE));
  DEFS.set("haybail", def("haybail", false, true, COVER_MODERATE));
  DEFS.set("haybale", def("haybail", false, true, COVER_MODERATE));
  DEFS.set("wall_straight", def("wall_straight", true, true, COVER_COMPLETE));
  DEFS.set("wall_corner", def("wall_corner", true, true, COVER_COMPLETE));
  DEFS.set("wall", def("wall_straight", true, true, COVER_COMPLETE));
  DEFS.set("wall_straight_long_ne", def("wall_straight", true, true, COVER_COMPLETE));
  DEFS.set("building", def("building", true, true, COVER_COMPLETE));
  for (const id of [
    "coc_window",
    "coc_door_wood",
    "coc_bush",
    "coc_cw01",
    "coc_cw02",
    "coc_swin",
    "coc_wh11",
    "coc_swal",
  ]) {
    DEFS.set(id, def(id, false, true, COVER_MODERATE));
  }
  DEFS.set("coc_tree", def("coc_tree", true, true, COVER_MODERATE));
  DEFS.set("coc_bush_cluster", def("coc_bush_cluster", true, true, COVER_MODERATE));
  DEFS.set("coc_blocker", def("coc_blocker", true, false, COVER_NONE));
}

export function normalizeTypeId(typeId: string): string {
  if (typeId === "wall" || typeId === "wall_straight_long_ne") {
    return "wall_straight";
  }
  if (typeId === "haybale") {
    return "haybail";
  }
  return typeId;
}

export function getObjectDef(typeId: string): ObjectDef | null {
  seedDefs();
  const id = normalizeTypeId(typeId);
  const known = DEFS.get(id);
  if (known !== undefined) {
    return known;
  }
  if (id.startsWith("coc_")) {
    return def(id, true, true, COVER_COMPLETE);
  }
  return null;
}

export function parseTerrainClass(raw: string): number {
  const token = raw.toUpperCase();
  if (token.includes("NOPASS") || token.includes("NO_PASS")) {
    return TERRAIN_NO_PASS;
  }
  if (token.includes("CLIMB")) {
    return TERRAIN_CLIMB;
  }
  return TERRAIN_EVEN;
}

let familyCache: Map<string, FamilyGameplay> | null = null;

export function loadFamilyGameplay(): Map<string, FamilyGameplay> {
  if (familyCache !== null) {
    return familyCache;
  }
  familyCache = new Map();
  const repoRoot = resolve(__dirname, "../..");
  const path = resolve(repoRoot, "assets/data/map_asset_registry.json");
  try {
    const raw = JSON.parse(readFileSync(path, "utf8")) as {
      families?: Record<string, { gameplay?: Record<string, unknown> }>;
    };
    for (const [family, entry] of Object.entries(raw.families ?? {})) {
      const gp = entry.gameplay;
      if (gp === undefined) {
        continue;
      }
      const terrain = typeof gp.terrain === "string" ? parseTerrainClass(gp.terrain) : undefined;
      familyCache.set(family.toUpperCase(), {
        terrainHeight:
          gp.terrain_height !== undefined ? clampHeight(Number(gp.terrain_height)) : undefined,
        terrainClass: terrain,
        blocksLos: gp.blocks_los !== undefined ? Boolean(gp.blocks_los) : undefined,
        providesCover: gp.provides_cover !== undefined ? Boolean(gp.provides_cover) : undefined,
        coverType: gp.cover_type !== undefined ? clampCover(Number(gp.cover_type)) : undefined,
      });
    }
  } catch {
    /* tests may run without the asset file */
  }
  return familyCache;
}

function clampHeight(value: number): number {
  return Math.max(0, Math.min(2, Math.round(value)));
}

function clampCover(value: number): number {
  return Math.max(0, Math.min(2, Math.round(value)));
}
