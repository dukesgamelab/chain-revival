# Fog of War Plan (Phase 48)

Goal: you only see, and your client only receives, the enemies your side has spotted.

- **Branch:** `fog-of-war` off `develop`.
- **Status (2026-11-05):** code complete and checked in a local two-machine 1v1 and in single-player. Server and client suites pass apart from known old failures. Open: one survival report (see "Found along the way").
- **Status key:** `[ ]` open, `[x]` done.
- **No SQL migrations needed.**

**Done when:** at the start of a match neither player can see the other team's deployment, an unspotted enemy is not drawn, and the server never sends a team the position or state of an enemy it can't see.

---

## What's there now

**Spotting already works.** The server's `PerceptionSystem` (`server/src/perception.ts`) builds a per-team visible set: one spotter reveals an enemy to the whole side. It rebuilds every 0.5s combat scan, or sooner when an order marks it dirty. A soldier counts as spotted when the enemy faces him, has line of sight, and `100 - 4 x distance` (plus +15 running, +10 walking, +25 for 2s after firing, minus moderate cover) stays at 0 or above. In practice that's about 25 tiles for a standing soldier and about 31 for one who just fired. Single-player uses the same formula in `CombatSystem`.

**The client draws everyone in 1v1.** `main.gd` `_fog_visual_for_enemy` returns GHOST for any unspotted enemy when `_is_one_v_one_match()`, in single-player and multiplayer alike. The ghost follows the enemy's true position. 2v2 already uses HIDDEN.

**The server sends everything to everyone.** `match.ts` `broadcast()` sends every message to both clients. What leaks:

| Message | What it gives away |
|---|---|
| `match_snapshot` (join, match_ready, reconnect) | Every soldier's cell, facing, stance, **current path**, stress, ammo, grenades |
| `move_result` | The enemy's **full path to the destination** at the moment the order is given |
| `movement_tick` | Every enemy step, every 50ms |
| `soldier_sync` (0.5s) | Every enemy's stance, facing, stress, ammo, grenades, stun, Fire At target |
| `face_result`, `position_result`, `fire_control_result`, `fire_at_result` | Enemy facing, stance, halts (with cell), targets |
| `target_sync` | Every enemy's engaged target |
| `visibility_update` | Both teams' visible lists, so you also learn which of your soldiers the enemy can see |
| `combat_shots` | Shooter, target, enemy ammo, hit breakdown |
| `grenade_thrown`, `grenade_explode` | Thrower, target cell, enemy grenade count, stunned enemies |

`join_match` also sends a full snapshot before the client is on a side.

**Deployment zones are far apart.** On every current map the two zones are at least 41 tiles apart (Manhattan distance; The Fortress is closest), well past the ~25 tile spotting reach, so nobody is spotted at deployment by the normal rules. Once the client hides enemies and the server stops sending them, the "see the enemy deployment" bug is gone. The only thing a modified client can still learn is the map's spawn cells, which are public map data.

---

## Design decisions (Richard)

Decided 2026-11-05:

1. **Last-known marker:** yes. When a spotted enemy drops out of sight, a frozen ghost silhouette stays at his last seen cell (last seen stance and facing) and fades out over about 8 seconds. If he's spotted again it's replaced at once by the real soldier.
2. **Start of the match:** normal spotting rules from the first tick (no special case), plus the enemy's deployment zone cells are highlighted on the map during the deployment countdown. That's map data only, no soldiers. The highlight goes when deployment ends. No soldiers are seen at deployment on current maps, because the zones are 41+ tiles apart.
3. **Shots and grenades from out of sight:** the tracer comes from the shooter's real cell and a last-known marker (as in 1) appears there, but he is not spotted: he isn't drawn and isn't in your visible set unless normal spotting picks him up (firing already gives +25 to spotting for 2s). Grenades work the same way: the throw arc starts at the thrower's cell and the marker appears there. Only the team being shot at or in the blast gets the cell, and only for that shot.
4. **Single-player too:** yes, the same hiding and marker in every mode. The single-player 1v1 ghosts that follow the AI's true position go away.

Defaults I'll take unless you say otherwise:
- **Deaths are always sent.** Kill points are already public in `scenario_time`, so hiding the kill gains nothing. The body is drawn where the soldier fell.
- **Enemy stress tint, stance and facing** are sent only while the enemy is spotted. Enemy ammo and grenade count are never sent (only the owner's command bar uses them).
- **Replays keep the full unfiltered stream.** The recorder logs before filtering, and replays are only viewed after the match.
- **Enemy paths are never sent.** Spotted enemies animate step by step from `movement_tick` (the single-player chase path, `sync_movement_chase_from_state`) instead of following a path. This needs an in-game check for choppy movement.

---

## Step 1 - Server: per-team sending

- [x] `match.ts`: replace the blanket `broadcast()` for game-state messages with `sendPerTeam(build: (teamId) => payload | null)`. The recorder still logs the full payload once. Lobby and scenario messages (`scenario_time`, `vp_update`, `match_ended`, `deployment_ended`) stay broadcast.
- [x] New `server/src/fog_filter.ts` with one filter per message type. Each filter is given the receiving team and the perception system. Rules:
  - own soldiers: unchanged
  - spotted enemy: position, facing, stance, movement mode, stun, stress, engaged target. No path, ammo or grenades.
  - unspotted enemy: dropped. In the snapshot, only `soldierId`, `teamId`, `weaponId`, `isDead` (plus the body cell if dead), so the client still has the roster.
  - no team assigned (`join_match` before a side): no enemy data for either side.
- [x] **Order of a tick:** rebuild perception right after movement and before sending `movement_tick`, so a soldier stepping into view arrives with the step that revealed him and nothing goes out early.
- [x] **Reveal:** when an enemy enters a team's visible set, that team's `visibility_update` carries his full current state in `revealed` (cell, facing, stance, movement mode, moving flag, speed, stress, stun, target). When he leaves it, the same message drops him from the list.
- [x] `visibility_update`: each team gets only its own side's list.
- [x] Order results (`move_result`, `face_result`, `position_result`, `fire_control_result`, `fire_at_result`): the issuing team gets the full result. The other team gets a cut-down copy without request status, limited to spotted soldiers, with no paths, or nothing at all if nothing is left.
- [x] `combat_shots`, `grenade_thrown`, `grenade_explode`: shots and throws by or at your own soldiers are always sent. A hidden enemy shooter or thrower comes with only his cell at that moment (for the tracer, arc and marker): no stance, facing, ammo, hit breakdown or grenade count. Stunned enemies in a blast are listed only if spotted. The explosion cell is always sent.
- [x] **Tests (`server/tests/fog_of_war.test.ts`, 9 cases):** fake sockets record every message per team. Script hidden and spotted moves, orders, AI-free shots and grenades, plus a reconnect snapshot. Then assert that no message to a team contains an unspotted enemy's cell or state. Plus one test per filter, and the reveal/hide transitions.

## Step 2 - Client: draw only what you know

- [x] `main.gd` `_fog_visual_for_enemy`: unspotted means HIDDEN in every mode (drop the 1v1 GHOST branch), apart from the last-known marker in decision 1.
- [x] **Last-known marker** (if kept): when an enemy goes from spotted to unspotted, remember his last cell, stance and facing, and draw the existing GHOST silhouette there, frozen, fading out over the agreed time. It uses only what the client already saw, so it leaks nothing. Clicking it for Fire At follows the existing server rule (`canAssignManualPriority`: within 2 tiles, within 2s of last seen).
- [x] `authoritative_sync.gd`: apply `revealed` (`apply_revealed`). Accept a snapshot that leaves out enemy positions (keep the soldier, mark him unknown). Keep hidden enemies' stale cells out of local UI: Fire At hover and click targets, hit % column, corner idle pose, LOS-occupant previews.
- [x] Enemy movement in multiplayer: step chase from `movement_tick` instead of `follow_path`.
- [x] Shots and grenades from hidden enemies: tracer or throw arc from the cell in the message, and the last-known marker placed there. The hidden soldier's view stays hidden.
- [x] Enemy deployment zone highlight: tint the enemy's deployment cells during the countdown, cleared on `deployment_ended` (and in single-player when timed deployment ends).
- [x] **Tests:** new `scripts/tests/fog_of_war_tests.tscn`: snapshot without enemy cells, dead hidden enemy, reveal, hidden shooter, grenade body cell, marker lifetime, step chase, deployment overlay, and main.gd compiling with autoloads.

## Step 3 - Checks and docs

- [x] Full server and client suites (known old failures: server "lethality is applied to hit chance", client "Pinned (not panicked) soldier can still throw").
- [x] **Local 1v1, two clients:** neither side sees the other's soldiers at deployment, but the enemy zone highlight shows and clears when deployment ends; an enemy walking into view appears where he really is and moves smoothly; one walking out leaves the marker and it fades in ~8s; a shot from out of sight shows a tracer from his cell plus a marker, with the shooter still hidden; reconnect mid-match shows only spotted enemies.
  - **2026-11-05 run (Richard, two machines):** deployment, before contact, spotting, losing sight, hidden fire, hidden grenade, kills out of sight and normal orders all confirmed. Found: a seen German stood still on his own screen but played his run in place on the US screen. Cause: a full view sync mid-chase snapped the view without settling the run clip, and nothing told the client he had stopped. Fixed: full syncs leave a step chase alone, ending a chase always settles, and `soldier_sync` now carries `isMoving` so a stuck chase settles within 0.5s. Needs a recheck. Reconnect not tested yet.
  - **Second run (fix 4cbf6ef9):** reconnect works. The USA side still showed Germans running in place and not playing their firing animation while the German screen showed them shooting. Open: check the USA machine had the fix, and whether the Germans were only spotted because they fired (spotting updates every 0.5s, so each shot arrives while the shooter is still hidden).
- [x] Single-player 1v1 vs AI: enemies hidden until spotted (Richard, 2026-11-05: visuals look right).
- [x] `game-systems.md`: new "Spotting and Fog of War" section with the spotting formula and the decisions.
- [x] `changelog.md`: move "No effective fog of war" from Known Bugs to fixed; Phase 48 notes.
- [x] `handoff.md`: Current Work becomes Phase 48. Phase 47 is merged to `develop` (PR #11, 2026-11-05) and not released.

---

## Release note

This changes the wire protocol again (`revealed` in `visibility_update`, per-team payloads), so server and client must ship together. Phase 47 also changed it and hasn't been released. Shipping 47 and 48 as one release, **0.23.0**, would need only one forced client update and would keep 0.23.0 for fog of war as planned. Your call at release time.

## Risks

- **Enemy movement may look choppier** without a path. Needs the in-game check; the fallback is to send spotted enemies the next few cells of their path only.
- **Up to 0.5s before an enemy appears.** Perception rebuilds every 0.5s, or every tick while dirty. Steps mark it dirty, so this should be one tick, but it's worth measuring.
- **Old clients:** a 0.22.x client on the new server would show hidden enemies frozen at their spawn cells. The version check and auto-updater handle this.

## Found along the way

- **Survival (1 v All), open:** Richard once couldn't move a soldier. Log (2026-11-05): a move was armed for USA Soldier 2 (tile 13,16, Germans 6-9 tiles away) but no order followed; he was then stunned by three grenades in a row and killed. Stun is the only thing that blocks moving. Not yet tied to fog of war. To check next time: which soldier, the status bar text, and where the click was.
- **Corner firing on the opponent's screen:** Germans firing or stopped at building corners looked wrong on the USA screen (shifting poses, run in place, no firing animation). The same happens on `develop`, so it predates fog of war. Logged in the changelog Known Bugs as "Corner pose stutters on the opponent's screen".

- **Reconnect never re-attached the player** (`server/src/index.ts` resume path): since the v0.22.9 security hardening removed the attach-on-connect, a reconnected socket was never added to the match. It got the snapshot, then no match messages, and every order was refused ("Join a side before issuing orders."). Fixed on this branch. It's live on `main`, so it's worth a `hotfix/` branch if a release with 47 + 48 is not close.
