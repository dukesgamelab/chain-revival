# Chain of Command — Recovered Original Behaviour

Reference for Chain Revival. Everything here was extracted from the original game's files or
measured from original gameplay footage.

**Read the confidence tag on every claim.** Three levels are used, and they are not
interchangeable:

- **VERIFIED** — read directly out of the original's files, or measured from its assets or
  footage. Reproducible. Safe to implement against.
- **INFERRED** — the underlying data is real, but its meaning or application is my
  interpretation. Test it; do not treat it as ground truth.
- **UNRESOLVED** — known to exist, not recovered. Listed so nobody assumes it was settled.

There is also a **Retractions** section at the end recording claims that were made during
research and later disproved. Read it before acting on any older note — several of those wrong
claims are individually plausible and will otherwise be rediscovered.

## Sources

| file | what it is |
|---|---|
| `cocSc.MDL` | The game's object database — properties, values, and script bytecode. Primary source. |
| `creation.exe` | The 2AM Creation engine (generic runtime + script VM). Contains no game logic; used only to recover operator opcodes. |
| `Creation.mdf` | Lobby/ladder database — accounts, ranks, promotion points. No combat or soldier data. |
| recovered sprites | 8,381 soldier sprites, `<nation><stance><action><variant><dir><frame>`. |
| gameplay footage | Original recordings, used for cadence, hit rates, and stress values. |

---

# 1. Combat model

## 1.1 Base hit chance — VERIFIED

Decoded from the script expression tree:

```
                aim_factor_sqr·AimTime²  +  aim_factor·AimTime  +  aim_plus
AuxDecimal  =  ────────────────────────────────────────────────────────────
                cub·D³  +  sqr·D²  +  pent·D⁵            where D = Range − MarksMan
```

`HitFinal` is a probability in 0–1 (confirmed: the game computes `PassHit = HitFinal × 100` for
display).

Consequences: range falloff is a **polynomial whose degree is per-weapon**, and `MarksMan`
(a per-soldier skill) subtracts from effective range. There is **no weapon range cap anywhere** —
an SMG is short-ranged purely because its denominator is 5th-power.

## 1.2 Weapon constants — VERIFIED

| | Garand | Mauser | Thompson | MP40 | BAR | MG42 |
|---|---|---|---|---|---|---|
| `AmmoMax` | 70 | 70 | 200 | 200 | 900 | 900 |
| `BulletsPerShoot` | 1 | 1 | 4 | 5 | 7 | 6 |
| `BulletSpeed` | 6 | 6 | 6 | 6 | 6 | 7 |
| `Automatic` | – | – | 1 | 1 | 1 | 1 |
| `range_const_cub` | 1.0 | 1.0 | 0.0 | 0.0 | 1.0 | 1.0 |
| `range_const_sqr` | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| `range_const_pent` | 0.0 | 0.0 | 0.02 | 0.02 | 0.0 | 0.0 |
| `aim_factor_sqr` | 2000 | 2000 | 2000 | 2000 | 8000 | 8000 |
| `aim_factor` | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| `aim-plus` | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| `stress_aim_factor` | 0.5 | 0.5 | 1.5 | 1.5 | 2.0 | 2.0 |
| `StressLimit` (tiles) | 25 | 25 | 13 | 13 | 25 | 25 |
| `StressFactor` | 0.25 | 0.25 | 2.0 | 2.0 | 0.6 | 0.6 |
| `INIT_LimitPerSquad` | – | – | 2 | 2 | 1 | 1 |

The complete `$weapon` property list is 21 entries and contains **nothing** about animation,
movement, or weight. Grenade: `VarA=30, VarB=0, VarC=30, VarD=5`, `BlowTouch="before"`.

## 1.3 Global constants — VERIFIED

```
INITKilledProbability   20      INITCoverHitMultiplier   0.005
INITKillOn               1      INITCoverInMultiplier    1.0
INITShortRange           5      INITCoverRangeLimit      3
INITChangeTarget        20      INITMinDuckingRange      4
INITGetTargetOnLongProb 100     INITStressBase           0.8
INITLongDMinSearch       5      INITStressInitial        0.0
INITLongDMaxSearch      20      INITStressFallMultiplier 0.3
INITShortDMinSearch      1      INITMaxStressOut         7
INITShortDMaxSearch      4      INITMaxGranadeDistance   5
Shift RightCorner     0.25      GranadeHitDistance       2
```

## 1.4 Cover — VERIFIED

```
IF in_cover AND range >= INITCoverRangeLimit (3):
    cover_mult = INITCoverHitMultiplier            # flat 0.005
ELSE IF in_cover:
    cover_mult = (INITCoverHitMultiplier − 1) × (range − 1) / INITCoverRangeLimit + 1
```

| range | multiplier |
|---|---|
| 1 | 1.000 — cover is useless at point blank |
| 2 | 0.668 |
| 3 | 0.337 |
| ≥ 3–4 | **0.005** |

Beyond ~4 tiles a man in cover is effectively unhittable by direct fire. This is why the original
forces flanking and grenades. There is **no per-cover-object strength** — a wall and a hedge
behave identically.

## 1.5 Movement and the angle mechanic — VERIFIED

When the target has **no** cover:

```
HitFinal ×= MoveType.TypeMultipler
HitFinal ×= 1 − MoveType.MoveMultipler × |sin(DEG2RAD × (shooter.Direction − target.Direction))|
```

applied when the target is moving and its Move Type is running. The trig function is confirmed
as sine; the constant `0.0174533` (π/180) is present in the script.

| target movement relative to shooter | multiplier at `MoveMultipler = 0.8` |
|---|---|
| straight toward or away | 1.00 |
| 45° off axis | 0.43 |
| perpendicular | **0.20** |

Movement-state objects are `_HG_Running`, `_HG_Stalking`, `_HG_Crawling`, carrying
`TypeMultipler` ∈ {1.0, 1.0, 0.4} and `MoveMultipler` ∈ {0.8, 0.9, 1.0}.
*(INFERRED: which value belongs to which state — the object-name table and data section are
offset by one position and I could not pin the direction.)*

## 1.6 Lethality — VERIFIED

```
KIA = if randBetween(1, 101) <= INITKilledProbability then 1
```

That expression references **nothing else**. Lethality is flat 20% — it does not vary with range,
stance, weapon, or cover. Point-blank shots are deadly in the original because hit chance
saturates, cover contributes nothing at range 1, and automatic weapons fire often — not because
each hit is more lethal.

Non-kills become wounds (`WIA`), with a wound subtype rolled (leg / side).

## 1.7 Suppression — VERIFIED

```
IF ShootTarget != OldTarget AND Range < weapon.StressLimit:
    GivenStress = (weapon.StressLimit − Range) × weapon.StressFactor
```

| weapon | R=5 | R=12 | R=20 | cutoff |
|---|---|---|---|---|
| Garand / Mauser | 5.0 | 3.25 | 1.25 | 25 |
| Thompson / MP40 | **16.0** | 2.0 | — | 13 |
| BAR / MG42 | 12.0 | 7.8 | 3.0 | 25 |

Decay involves `Expirience × INITStressFallMultiplier`; idle soldiers recover at
`INITStressBase`. Break threshold is `INITMaxStressOut = 7`.

**Observed in footage:** stress values of **0.8, 5.7, 7.2** during a normal corner firefight,
with 7.2 rendered in a distinct colour (above the break threshold). The scale runs 0–~7, not
0–100.

## 1.8 Aim time — VERIFIED structure

```
Aux3Int = Expirience − Stress
AimTime = 1 / ( ObjectNamed("Exp-Str" + bucket).prop("Range" + floor(Range/4)) − ShootingSpeed )
IF AssaultProduced: AimTime = 1
```

Five bucket objects exist: `Exp-Str-8`, `Exp-Str-4`, `Exp-Str0`, `Exp-Str4`, `Exp-Str8`. Since
`AimTime` enters the hit formula **squared**, stress is quadratically punishing.

## 1.9 Target acquisition — VERIFIED constants

Two search bands: 1–4 (short) and 5–20 (long), with `INITGetTargetOnLongProb = 100` and
`INITChangeTarget = 20` (probabilistic target switching, producing sticky targeting).
`INITAbolFireAtShort` cancels Fire At orders inside 5 tiles.

## 1.10 Measured hit rates — VERIFIED

From original footage, calibrating screen→tile against labelled map positions
(residual 0.12 tiles). All four soldiers 10.5–11.4 tiles from their nearest enemy, stationary,
stress 0:

| weapon | Hit % at ~11 tiles |
|---|---|
| rifle | **9%** |
| SMG | **3%** |
| heavy MG | **25%** |

Use these as calibration anchors.

## 1.11 Fire cadence — VERIFIED

Measured from tracer events with per-soldier attribution via the ammo counter:

| segment | interval | SD |
|---|---|---|
| heavy MG, solo | 5.05s | 0.07 |
| heavy MG, solo (later) | 6.09s | 0.14 |
| SMG | 5.05s / 6.08s | — |
| rifle | 5.05s / 6.03s | — |

**Cadence is not per-weapon.** All weapon types fire at the same interval, and the interval shifts
together (5.05 → 6.09) with conditions while stress stays at 0. **No rate-of-fire property exists
anywhere in the original's data.** Burst rounds emerge within 0.15–0.22s.

Independently corroborated by audio: burst sizes of 1 / 4 / 5 / 6 exactly match
`BulletsPerShoot`.

---

# 2. Grenades — VERIFIED

```
# casualty — once per soldier in radius, LOS-checked
AuxDecimal = VarA / (distance + VarB)          # 30 / distance, as a percentage
IF randBetween(0,100) <= AuxDecimal: → shared KIA/WIA block

# stun — every survivor, no roll
IF Death != 1:
    AuxDecimal    = VarC / (distance + VarD)   # 30 / (distance + 5)
    Path State    = "Stop"
    UMoveMode     = "_HG_Crawl"
    Blocking      = 1
    UStateCurrent = "Stuned" → UStateNext = "AfterStunned"
```

| distance | casualty | killed (×0.20) | stun duration |
|---|---|---|---|
| ~0 | 100% (capped) | 20% | 6.0 |
| 1 | 30% | 6% | 5.0 |
| 2 | 15% | 3% | 4.3 |
| 3 | 10% | 2% | — |

**A grenade landing directly on a man kills him one time in five.** Grenades are a disruption and
wounding weapon; their value is that every survivor in radius is knocked flat with no saving
throw.

Radius `GranadeHitDistance = 2`; throw range `INITMaxGranadeDistance = 5`.

**Two separate gates:** the **throw** is distance-only with **no LOS requirement** — any point
within 5 tiles is legal, visible or not. The **blast** is LOS-checked from the detonation point to
each soldier. So blind-throwing into a building works, and a grenade over a wall works because
LOS is evaluated from where it lands.

An in-progress throw is cancelled if the thrower is stunned.

## Windows — VERIFIED

Windows have `blocks_los: false`, `blocks_bullets: false`, `blocks_movement: true`,
`terrain: _HG_Climb`. Solid walls block all three. You can shoot and grenade through windows, and
soldiers can climb through them.

---

# 3. Corner behaviour — VERIFIED

The original tracks two **independent** properties on the soldier:

| property | meaning |
|---|---|
| `BehindCorner` (int) | Am I at a corner at all? Set **when taking cover**. |
| `CoverCorner` (string) | `"LeftCorner"` / `"RightCorner"`. Side only. |

Animation selection reads both. Critically, **neither involves the target, the shot line, or line
of sight** — the corner pose is a property of *standing at a corner*, not of *shooting through
one*.

Render offset toward the corner: **0.5 tiles** left, **0.25 tiles** right
(`Shift RightCorner`), scaled by **0.7** while running. The two sides use different magnitudes;
this is in the data, not a mistake.

**INFERRED:** the exact left/right rule. The script compares the cover's position against the
soldier's sub-tile position (`fx`/`fy`), under a source label reading `### y cover > fy`, but the
compared temporaries are assigned from an engine builtin that could not be decoded.

---

# 4. Animation system

## 4.1 Structure — VERIFIED

Four-level tree: `img` (490) → `mag` (449) → `clip` (1,604) → `bmp` (8,074). Two authored zoom
levels only, x1 and x8. Eight directions. Leaf bitmaps carry hotspot **(-50, -73)**.

Animation objects hold `iFrame0`–`iFrame23` — a **24-frame hard maximum**. The longest asset in
the game is exactly 24.

Filename convention `<nation A|G><stance S|P><action><variant A|S><dir 1-8><frame A-X>`, with
direction digits `1→w, 2→sw, 3→s, 4→se, 5→e, 6→ne, 7→n, 8→nw`.

## 4.2 Animations are not weapon-specific — VERIFIED

All 82 `UMImage*` animation slots belong to the **soldier** class, not the weapon class. The
21-entry `$weapon` list contains no animation, movement, or weight property. Not one
weapon-specific sprite exists in the 8,381-file library. **Every weapon uses the same animation
set, and heavy weapons do not move slower** — `Speed` is a per-soldier property.

## 4.3 Fire cycle frame roles — VERIFIED

For the 3-frame fire assets (`ASFI`/`GSFI`, `APFI`/`GPFI`):

- **frame A** carries the muzzle flash (33 bright-yellow px; B and C have none)
- **frame C is pixel-identical to the aim-idle asset** (`ASAIS`) — 0 px difference

So the cycle is aim (C) → flash (A) → settle (B) → aim (C). Playing `[A, B, C]` ends on a pose
that *is* the aim hold, making the hand-off seamless. Ending on A leaves a permanently held
muzzle flash.

## 4.4 Duplicate assets — VERIFIED

The original ships identical artwork under multiple names. Pixel-identical pairs:

- `APFI` == `APLF` == `APRF` (and the German set) — **there is no distinct prone corner art**
- `APDP` == `APLP` == `APRP`
- `APLA` == `APRA`, `GPID` == `GPRI`, `GPLD` == `GPRD`
- `APID` vs `APRI` — identical in 7 of 8 directions, differing only at direction 8

Do not wire prone corner animations. The generic prone art is what the original used.

## 4.5 Weapon-only overlays — VERIFIED

`ASFX`/`ASAX` and the corner variants `ALBX`/`ARBX` are **rifle-and-muzzle-flash overlays**, not
soldier poses — measured at 4–113 opaque pixels against ~500 for a full soldier, positioned at the
barrel end. Used when the body is occluded behind cover and only the weapon protrudes. They have
partial direction coverage (5–6 of 8), consistent with that purpose. `ALBY`/`ARBY` are entirely
blank (0 opaque pixels).

## 4.6 Loop boundaries — VERIFIED method, not recorded in the original

**The original's files do not contain a recoverable per-animation playback list.** The `iFrame`
objects are bulk frame storage that runs across direction boundaries. Frame *counts* are
verifiable; which frames are in a loop is not.

Loop boundaries must be established empirically, by pixel-delta continuity: the wrap transition
(last frame → first frame) should be no larger than a typical mid-cycle transition.

Applying this to the walk cycle: **walk is 7 frames (A–G), not 8.** Verified across all 8
directions and both nations, 16 of 16 — the 7-frame wrap is the *smallest* transition in the
sequence, the 8-frame wrap is one of the largest. Frame H is outside the loop.

`crawl` at 22 frames is a genuine full cycle, not two 11-frame halves (frame *i* vs *i+11*
differs by ~490 against a consecutive median of ~270).

## 4.7 Data quality — VERIFIED

**Direction 8 (nw) has systematic mislabelling in the extraction.** Known bad: `ADOAS8A` (a
standing soldier in a corpse family), `ASFXA8C`, `ASAXS8A`. `APRIS8A` differs from `APIDS8A` where
the other seven directions are identical. Check direction 8 visually for every asset imported.

## 4.8 Soldier animation slots — VERIFIED

82 slots. Notable structure: left and right corner work are **fully separate** sets, not runtime
mirrors; prone has its own complete parallel set; and there are 11 wound animations including
being carried by a squadmate.

---

# 5. Not in the original

- **A stress pose.** Stress degrades aim time and feeds the Take Cover decision; it is not
  rendered as its own animation. The duck/cower set is what a stressed soldier uses.
- **Weapon-specific animations** (§4.2).
- **A weapon rate-of-fire property** (§1.11).
- **Per-cover-object strength** (§1.4).
- **Distinct prone corner art** (§4.4).

The ducking condition is VERIFIED:

```
IF EnemyKilled != 1 AND ( Move Type != _HG_Crawling
                          AND IseeHim == 0
                          AND Stress > 0
                          AND range / INITMinDuckingRange ... )
   → "Take Cover"
```

Two details worth preserving: a soldier already crawling does not duck, and ducking triggers when
stressed **and sight of the enemy is lost** — not merely when under fire.

---

# 6. UNRESOLVED

| item | status |
|---|---|
| **`hit_scale` absolute calibration** | The formula's absolute scale was never recovered. Relative relationships between weapons and ranges are exact; the anchor must be fitted against the §1.10 measurements. |
| **`AimTime` units** | The `Range` table values (63…2000) cannot feed `AimTime²` and keep `HitFinal` in 0–1. A scale factor is missing. |
| **Range table count** | Seven `Range0`–`Range25` tables recovered; only five `Exp-Str` objects exist. |
| **Heavy MG hit ratio** | Recovered `aim_factor_sqr` implies 4× the rifle; the original's own HUD implies ~2.8× at 11 tiles. Do not adjust the recovered constant to force the ratio. |
| **Binary opcodes 10 and 11** | Unnamed in the engine's annotation switch. |
| **Prone grenade assets** | The original has `LyPrepGr`/`LyThrowGr` slots; the backing assets were not identified. |
| **`LCAimEnd` asset** | Slot exists; no unused corner asset corresponds to it. |
| **Soldier skill distributions** | `MarksMan` / `ShootingSpeed` / `Expirience` are copied at spawn from a template. Prototype defaults are `Expirience 1.0, MarksMan 0, ShootingSpeed 0, Speed 5.0`; real per-scenario values were not found. |
| **Unidentified stems** | `AMAR`, `ACTL`, `ATTL`, `AKST`, `ASFB`, `ASTH` partially identified by eye; German-only `GEAR`, `GOAL`, `GOTO`, `GREX`, `GRSC`, `GSRX`, `GSRZ` unidentified. |

---

# 7. Retractions

Claims made during research and later **disproved**. Recorded so they are not rediscovered.

| claim | correction |
|---|---|
| "Weapon max range band = 25 rifle / 13 SMG" | That property is `StressLimit$weapon` — a suppression **range cutoff**. No weapon range cap exists. |
| "Weapon fire rate = 0.5 / 1.5 / 2.0" | That property is `stress_aim_factor$weapon`. No ROF property exists. |
| "Cover strength is per obstruction type" | The `TypeMultipler` objects are **movement states** (`_HG_Running` etc.), not cover types. |
| "Prone corner art is distinct and unused" | `APFI`, `APLF`, `APRF` are pixel-identical. There is no prone corner art. |
| "`ALBX`/`ALBY`/`ARBX`/`ARBY` are heavy-weapon poses" | They are barrel-only **overlays** for corner poses. `ALBY`/`ARBY` are blank. |
| "We are ~2× more accurate than the original" | Measured properly: ~1.3× for rifles at 11 tiles. |
| "The combat formulas need `creation.exe`" | The formulas are in `cocSc.MDL` as script bytecode. `creation.exe` was needed only for operator opcodes. |
| "Walk should use all 8 ASMO frames" | 7 frames (A–G). Frame H is outside the loop; including it produces visible jitter. |
| "`INITMinDuckingRange` gates the prone hit bonus" | It is an AI threshold for the Take Cover decision, not a combat modifier. |
