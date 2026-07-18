# SOLDIER ANIMATION MANIFEST — Chain of Command
Machine manifest: soldier_animation_manifest.json (same content, keyed American/German).

## Source of truth
138 eight-direction families recovered from cocSc.MDL (`bmp - <code> <static|action> mag 8 frame N <dir>`),
art in magall.MBm via the already-recovered decode chain (formats, palette, hotspots identical to terrain).
File naming: `8{CODE}{A|S}{dir 1-8}{frame A..}.BMP`; direction digits 3=e 4=se 5=s 6=sw 7=w 8=nw 1=n 2=ne;
facet selection uses the recovered 8-facet quantizer `((heading−90·camera+22)%360)/45`.
American (A-prefix) and German (G-prefix) sets are exact structural mirrors (one G-only extra: GSAP 10f, G-side aim-pose transition).

## Canonical animation set (per side — swap A/G prefix)
| State | Family | Frames | Loop | FPS* | Conf |
|---|---|---|---|---|---|
| Idle stand | .SAX (alt .SID) | 1 | yes | – | 90 |
| Idle kneel | .KNL | 1 | yes | – | 85 |
| Idle prone | .PLA / .PRA (+H/I variants) | 1 | yes | – | 70 |
| Walk | .SWK | 20 | yes | 12 | 90 |
| Run | .SRW | 20 | yes | 15 | 75 |
| Stalk/sneak | .SSS | 20 | yes | 10 | 70 |
| Assault/sprint | .SPR | 20 | yes | 15 | 70 |
| Crawl (prone move) | .PMO | 22 | yes | 10 | 85 |
| Fire SMG (single/burst) | .SFX / .SFB | 3 / 12 | no | 12/15 | 80 |
| Rifle aim/fire (stand) | .RBY / .RBX | 1 / 3 | – | 12 | 70 |
| LMG aim/fire (stand) | .LBY / .LBX | 1 / 3 | – | 12 | 70 |
| Rifle/LMG kneel aim+fire | .RCA/.RCF, .LCA/.LCF (+CI idle, +CP 3f action) | 1/3 | – | 12 | 60 |
| Prone fire | .PLF / .PRF (+PLD/PRD 2f settle, .PRN 5f reload-inferred) | 3 | no | 12 | 65 |
| Grenade throw | .BRL (21f) — **or** .LPK; assignment INFERRED, verify | 21 | no | 15 | 55 |
| Reload (long) | .LPK (16f) — see grenade note | 16 | no | 12 | 55 |
| Stand→Kneel / Kneel→Stand | .SKN / .KUP (alt .KST) | 4 / 4 | no | 15 | 85 |
| Prone→Kneel | .PKN | 7 | no | 15 | 80 |
| Stand→Prone / Prone→Stand | .STG / .SUP | 24 | no | 18 | 80 |
| Hit front / back / leg | .HTF / .HTB / .HTL | 19/20/23 | no | 15 | 80 |
| Wounded locomotion | .WLG (+static), alt .WSD (+static) | 12 | yes | 8 | 80 |
| Death fall | .FAL (frames 0-6 & 10-14 = two variants) | 20 | no | 15 | 90 |
| Corpse persistent | .DFU (face-up) / .DFD (face-down); extras .DOA/.DHH/.PDD; 2f diers .DHP/.PDP | 1 | yes | – | 90 |
*FPS values are recommendations (original tick rate not recovered) — tune against footage.

## Weapon model (recovered structure, 85%)
Movement, transitions, hits, deaths are weapon-agnostic and SHARED. Only aim/fire swaps per weapon
class: SMG uses the base S-set fire; Rifle = R-group; LMG = L-group (standing B-poses, kneeling
C-poses). The scenario weapon lists (aw1: Thompson; gw1: MP40) bind soldiers to a class at spawn.

## State diagram
```
                      ┌────────────── hit (HTF/HTB) ──────────────┐
                      ▼                                            │
  IdleStand ⇄ Walk/Run/Stalk/Assault (loops)                       │
   │  ▲  │ SKN                          ▲ KUP                      │
   │  │  ▼                              │                          │
   │ SUP IdleKneel ⇄ (kneel aim RCA/LCA → fire RCF/LCF → kneel)    │
   │  ▲  │  ▲ PKN                                                  │
  STG │  ▼  │                                                      │
   ▼  │ IdleProne ⇄ Crawl (PMO loop)                               │
  IdleProne — prone aim (PLA/PRA) → prone fire (PLF/PRF) → prone   │
                                                                   │
  IdleStand → Aim (SAX/RBY/LBY) → Fire (SFX|SFB/RBX/LBX) → Aim → Idle
  IdleStand → GrenadeThrow (BRL†) → IdleStand
  Any → HitLeg (HTL) → WoundedWalk (WLG loop, WSD alt)
  Any → DeathFall (FAL) → Corpse (DFU/DFD persistent)
  † BRL/LPK grenade-vs-reload assignment needs one visual check.
```
Valid transitions are stance-adjacent only (stand⇄kneel⇄prone); fire requires an aim pose of the
current stance+weapon; wounded replaces all locomotion; death is terminal to a persistent corpse.

## Open items (do not implement as fact)
1. BRL vs LPK = grenade-throw vs reload (55%) — one frame-strip view settles it.
2. PL* vs PR* prone pose pairs (left/right lean?) — cosmetic choice.
3. E*/U* auxiliary sets and L000-LC30 dummies — purpose unknown; exclude from soldiers.
4. ASID missing s-facing: use se (irregular_fallbacks.json rule).
