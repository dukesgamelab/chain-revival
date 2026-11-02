# Chain Revival - Game Systems Reference

Technical reference for gameplay mechanics, combat formulas, and tuning values. All values are loaded from `assets/data/gameplay_policies.json` at startup and can be overridden there without code changes.

## Combat Resolution

There is no separate hit/wound model - a "hit" is an instant kill. The formula per round fired:

```
P(kill per round) = final_hit_chance * LETHALITY_MULTIPLIER
P(kill per attack) = 1 - (1 - P(kill per round)) ^ rounds_per_attack
```

`LETHALITY_MULTIPLIER` is currently **0.60** (original was 0.20, was temporarily 0.90 - tuned to balance lethality without a wound state).

### Hit Chance Polynomial

```
D = max(0.25, euclidean_range)

numerator   = aim_factor_sqr * AimTime^2
denominator = range_const_cub * D^3 + range_const_pent * D^5

base_hit = clamp(0.060 * numerator / denominator, 0.0, 1.0)
```

- Rifles use `D^3` denominator - smooth falloff with range
- SMGs use `D^5` denominator - devastating close, useless at distance ("SMG cliff")
- LMGs have 4x the rifle numerator (8000 vs 2000) - 4x base accuracy at any range

### Final Hit Chance Modifiers

Applied multiplicatively to base hit:

```
final = base_hit
        * cover_modifier (or open_ground_mult * movement_modifiers)
        * stress_mult
        * shooter_prone_mult
        * target_prone_mult
clamped to [0.0, 1.0]
then: if range <= 2 tiles, floor at 0.92
```

### Hit Chance Constants

| Parameter | Value | Notes |
|-----------|-------|-------|
| HIT_SCALE | 0.060 | Absolute scale on polynomial |
| AIM_TIME | 1.0 | Fixed aim time input |
| RANGE_EPSILON | 0.25 | Floor on D to prevent div-by-zero |
| LETHALITY_MULTIPLIER | 0.60 | Multiplies hit chance for kill roll (original 0.20) |
| OPEN_GROUND_HIT_MULT | 1.15 | +15% hit when target not in cover |
| SHOOTER_PRONE_ACCURACY_MULT | 1.15 | +15% accuracy when shooter is prone |
| TARGET_PRONE_HIT_MULT | 0.55 | -45% hit chance vs prone target |
| POINT_BLANK_TILES | 2.0 | Range at which minimum hit applies |
| POINT_BLANK_MIN_HIT | 0.92 | Floor hit chance at point blank |
| BASE_FIRE_CYCLE_SEC | 5.0 | Seconds between shots (aim + fire) |
| MAX_ENGAGEMENT_TILES | 40 | Maximum engagement range |

### Approximate Kill Probabilities (no cover, no stress)

| Range | Rifle (1 rnd) | SMG (4 rnds) | LMG (7 rnds) |
|-------|---------------|--------------|---------------|
| 2 tiles | ~55% | ~96% | ~99.9% |
| 5 tiles | ~58% | ~99% | ~99.9% |
| 8 tiles | ~14% | ~36% | ~82% |
| 11 tiles | ~5% | ~5% | ~82% |
| 20 tiles | ~0.9% | ~0% | ~23% |

## Weapons

| Weapon | Type | aim_factor_sqr | range_const_cub | range_const_pent | rounds/attack | ammo | suppression_gen | stress_limit_tiles | stress_aim_factor |
|--------|------|----------------|-----------------|------------------|---------------|------|-----------------|--------------------|--------------------|
| M1 Garand | Rifle | 2000 | 1.0 | 0.0 | 1 | 70 | 0.25 | 25 | 0.5 |
| Kar98k | Rifle | 2000 | 1.0 | 0.0 | 1 | 70 | 0.25 | 25 | 0.5 |
| Thompson | SMG | 2000 | 0.0 | 0.02 | 4 | 200 | 2.0 | 13 | 1.5 |
| MP40 | SMG | 2000 | 0.0 | 0.02 | 5 | 200 | 2.0 | 13 | 1.5 |
| BAR | LMG | 8000 | 1.0 | 0.0 | 7 | 900 | 0.6 | 25 | 2.0 |
| MG42 | LMG | 8000 | 1.0 | 0.0 | 6 | 900 | 0.6 | 25 | 2.0 |

**Squad limits:** Rifles unlimited, SMGs max 2, LMGs max 1 per squad.

## Cover System

**Cover types:** NONE, MODERATE (obstruction in adjacent cell toward shooter), COMPLETE (wall - blocks all shots).

**Cover detection:** 8-directional compass lookup. The cell adjacent to the target, toward the shooter, is checked for an obstruction.

**Cover hit multiplier curve:**

| Range | Multiplier | Effect |
|-------|------------|--------|
| 1 tile | 1.0 | No effect at melee range |
| 2-4 tiles | 0.5 (floor) | 50% hit reduction during ramp |
| 5+ tiles | 0.005 | 99.5% hit reduction - cover is extremely effective at range |

**Cover and suppression:** MODERATE cover reduces suppression gain by 35% (mult 0.65).

### Open Ground Modifiers

When NOT in cover, hit chance gets 1.15x bonus plus movement modifiers:

| Movement | Type Mult | Move Mult | Notes |
|----------|-----------|-----------|-------|
| Running | 1.05 | 0.8 | Slightly easier to hit, crossing dodge |
| Walking | 1.15 | 0.9 | Easier to hit |
| Crawling | 0.4 | 1.0 | Hard to hit (low profile) |

- **Angle factor:** `1 - move_mult * |sin(heading_delta)|` - crossing targets harder to hit
- **Approach bonus:** 1.35x when target heads toward shooter (dot product >= 0.7)

### Prone Effects

| Effect | Value |
|--------|-------|
| Shooter prone accuracy | +15% (1.15x) |
| Target prone hit chance | -45% (0.55x) |
| Prone suppression received | 75% of standing |
| Prone stress decay | 2x faster |

## Grenades

| Parameter | Value |
|-----------|-------|
| Starting count | 5 per soldier |
| Throw range | 5 tiles (Chebyshev) |
| Blast radius | 2.0 tiles (Euclidean) |
| Fuse | 1800 ms |

**Casualty chance:** `VAR_A / max(distance + VAR_B, 0.5) / 100` then multiplied by LETHALITY_MULTIPLIER.

| Distance | Casualty % | Kill % (x0.60) |
|----------|------------|-----------------|
| 0-0.5 tiles | 60% | 36% |
| 1.0 tile | 30% | 18% |
| 1.5 tiles | 20% | 12% |
| 2.0 tiles | 15% | 9% |

**Stun:** Every survivor in blast radius is stunned (no roll). Duration: `30 / (distance + 5)` seconds. At ground zero: 6s. At 2 tiles: 4.3s. Stun forces prone, crawl mode, aborts grenade throws, ends sustained fire, resets fire prep.

**Friendly fire:** Enabled - grenades can kill and stun same-team soldiers. The throw preview line turns yellow (warning) when friendlies are in the blast radius. AI avoids friendly fire automatically.

**Wall blocking:** Blast is blocked by walls (stricter than shot LOS - no cover exceptions, no corner peeks).

## Suppression and Stress

Stress runs 0-100 (original game used 0-7, converted via STRESS_SCALE = 100/7).

### Stress Gain

```
gain = (stress_limit_tiles - range) * suppression_generated * STRESS_SCALE * cover_mult * stance_mult
```

Beyond `stress_limit_tiles` (25 for rifles/LMGs, 13 for SMGs), the weapon generates zero suppression.

**Sustained fire bonus:** Shots from a sustained Fire At order multiply suppression gain by 1.5x (`sustained_fire_suppression_mult`). This is the primary pinning mechanic - focused fire builds stress faster than auto-fire.

**Examples:**
- Rifle at 10 tiles: ~53.6 stress per shot (~80.4 sustained)
- SMG at 5 tiles: ~228.6 (capped at 100)
- LMG at 10 tiles: ~128.6 (capped at 100)
- LMG at 10 tiles: ~128.6 (capped at 100)

### Stress Bands

| Band | Threshold | Movement Speed | Fire Delay |
|------|-----------|----------------|------------|
| Calm | < 10 | 1.0x | 1.0x |
| Nervous | 10-25 | 0.9x | 1.05x |
| Suppressed | 25-45 | 0.75x | 1.15x |
| Pinned | 45-70 | 0.5x | 1.3x |
| Panicked | 70+ | 0.35x | 1.5x |

**Panicked restrictions:** Panicked soldiers (stress >= 70) cannot use Fire At. Orders are rejected with a notice. This restriction is enforced both client-side and server-side. Grenades can still be thrown when panicked.

**Visual feedback:** Stress is shown in the command row as band name + percentage with color coding (white/yellow/orange/red/dark red). Soldier sprites get a subtle warm tint at pinned and panicked thresholds. Fire At button greys out when a soldier is panicked.

### Stress Accuracy

Uses a recovered Experience-Stress x Range table with 5 tiers and 7 range bands (from `assets/data/stress_accuracy_table.json`). At zero stress the multiplier is ~1.0. As stress increases, accuracy degrades especially at longer ranges. The `stress_aim_factor` per weapon scales how much degradation affects that weapon (rifles: 0.5, SMGs: 1.5, LMGs: 2.0).

### Stress Decay

Exponential: `stress *= (0.3) ^ (dt / 5.5)`. After 5.5 seconds of no incoming fire, stress drops to 30% of its value (standing) or 15% (prone).

## Rank System

13 ranks with PP thresholds for ranks 0-9. Ranks 10-12 are regiment-assigned only.

| # | Rank | Abbrev | PP Threshold |
|---|------|--------|-------------|
| 0 | Private | PVT | 0 |
| 1 | Private First Class | PFC | 500 |
| 2 | Corporal | CPL | 2,500 |
| 3 | Sergeant | SGT | 7,500 |
| 4 | Staff Sergeant | SSG | 17,500 |
| 5 | Sergeant First Class | SFC | 35,500 |
| 6 | Master Sergeant | MSG | 65,500 |
| 7 | Second Lieutenant | 2LT | 115,500 |
| 8 | First Lieutenant | 1LT | 195,500 |
| 9 | Captain | CPT | 315,500 |
| 10 | Major | MAJ | Regiment-assigned |
| 11 | Lieutenant Colonel | LT COL | Regiment-assigned |
| 12 | Colonel | COL | Regiment-assigned |

Display rank uses the regiment-assigned rank when set, otherwise falls back to PP rank.

## Victory Point Capture

- Capture takes 20 seconds of continuous uncontested presence
- Progress resets if contested, nobody present, or a different side starts capturing
- Server broadcasts `vp_update` messages whenever VP state changes
- Client mirrors server logic for offline/singleplayer, skips local capture in multiplayer

## Deployment Zone

- 15-second deployment phase at match start
- Server validates DZ boundaries - moves outside your team's DZ are blocked
- Client-side pre-validation gives instant feedback without waiting for server round-trip

## Key Config Files

| File | Purpose |
|------|---------|
| `assets/data/gameplay_policies.json` | All tuning values - edit here to rebalance |
| `assets/data/stress_accuracy_table.json` | Stress x Range accuracy weight table |
| `scripts/gameplay_policies/` | GDScript policy objects (load from JSON) |
| `server/src/hit_resolution.ts` | Server-side hit chance calculation |
| `server/src/combat_system.ts` | Server-side combat resolution |
| `server/src/grenade_system.ts` | Server-side grenade resolution |
| `scripts/combat/combat_system.gd` | Client-side combat resolution |
