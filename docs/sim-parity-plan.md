# Sim Parity Plan

Goal: multiplayer plays the same as single-player.

Single-player runs one simulation (GDScript, `scripts/`). Multiplayer runs a second copy of the rules on the server (TypeScript, `server/src/`) and streams results to the client. Most multiplayer-only bugs come from:

- **Drift** - the server copy behaves differently from the GDScript.
- **Missing sync** - the server changes something but never tells the client.

Single-player is the reference. The server is brought in line with it, not the other way around.

- **Branch:** `sim-parity` off `develop` (after the Phase 46 PR is merged and the security lockdown is done).
- **Status key:** `[ ]` open, `[x]` done.

---

## Step 1 - Safety-net soldier sync

One periodic message fixes the whole "client never heard about it" class of bugs, including future ones.

- [x] Server: every combat scan (0.5s), broadcast a compact `soldier_sync` with, for each living soldier:
  - position state and movement mode (pending stance left out: the client treats pending differently and a mismatch is cleared when the stance itself differs)
  - facing (client ignores it while the soldier is moving; `movement_tick` owns facing then)
  - stress
  - grenade count, ammo
  - stunned / stun-until
  - fire control state, engaged target, sustained-fire flag
  - Location: `server/src/match.ts` `broadcastSoldierSync()`, sent during deployment and the running match.
- [x] Client: apply in `scripts/network/authoritative_sync.gd` `apply_soldier_sync()`. `main.gd` `_on_network_soldier_sync()` animates stance changes and redraws only soldiers whose view changed; stress/ammo/grenades only refresh the command bar.
- [x] Remove the now-redundant stress list from `scenario_time`.
- [x] In-game check (local 1v1, 2026-11-05): no flicker at corners or in the open; grenade count, stun recovery, stress decay and stance all show on the other client.

**Deploy note:** server and client must ship together. A 0.22.9 client on the new server loses stress decay (it read stress from `scenario_time`), so soldiers would look stuck at their peak stress until the client updates.

**Tests:** `server/tests/soldier_sync.test.ts`, and the `soldier sync` cases in `scripts/tests/authoritative_sync_tests.gd`.

**Fixes:**
- Grenade count stuck at 5 in the UI.
- AI stance / facing / Fire At / grenade results never reaching clients (`ai_commander_framework.ts:175-257`).
- Standing up after a stun not broadcast (`match.ts:790`, `grenade_system.ts:290-306`).

**Done when:** in a 1v1, an AI going prone, a grenade throw count, and a stun recovery all show on the other client without any action-result message.

## Step 2 - Parity test harness

Catch drift as it happens instead of after testers find it.

- [x] Shared fixtures in `scripts/tests/parity/*.json` (under `scripts/tests/` so the Godot export already leaves them out). Format and query kinds are in `scripts/tests/parity/README.md`. Each fixture has:
  - map size and wall/object cells
  - soldiers (cell, facing, stance, stress, weapon)
  - one query
  - expected outcome (taken from the GDScript run, since single-player is the reference)
  - optional `knownDrift`: the server reports the case as TODO until the Step 3 fix lands
- [x] Server runner: `server/tests/parity.test.ts`, loads each fixture and asserts the expected outcome.
- [x] Client runner: `scripts/tests/parity_tests.tscn`, loads the same fixtures and asserts the same outcomes headless.
  - Run with: `Godot --headless --path . res://scripts/tests/parity_tests.tscn` (add `-- --print` to print every actual result)
- [x] First fixtures (53 cases):
  - shot LOS status and blocking cell (11)
  - cover type (5)
  - corner peek (side, lean, corner-to-corner) - covered by the LOS cases at building corners and a doorway
  - hit chance at a range (10)
  - suppression gain (8)
  - grenade stun by distance and wall (6) - kills forced off on both sides, since the two RNGs differ
  - auto-target choice (6)
  - arrival facing at a corner (7)

**Done when:** both runners pass on the same fixtures, and a deliberately changed constant on one side makes the other side's run fail.

**Result (2026-11-05):** client 53/53. Server 51 pass + 2 known drift (auto-target SMG/LMG bonus, grenade blast through a wall next to the victim). Changing the moderate-cover suppression multiplier from 0.65 to 0.7 failed exactly `suppression_moderate_cover` on each side.

**Not covered yet:** the suppression drift below sits in `resolveShot` ordering (it returns before suppression for wall-huggers), and the suppression fixtures call `applySuppressionFromShot` directly, so they can't see it. Step 3 needs a resolve-shot fixture for it.

## Step 3 - Port known server drift

Each item gets a parity fixture first (it should fail), then the fix (it should pass).

- [x] **Suppression on wall-hugging targets.** Server `resolveShot` now applies suppression right after firing, before the wall-cover return, like GDScript. Test: `server/tests/sim_parity_drift.test.ts` (stress matches the `suppression_wall_hugging_target` fixture, 67.86).
- [x] **Grenade blast blocking.** Server `blastBlocked` is now a port of `_grenade_blast_blocked`: complete walls and vision-blocking tiles only; soldiers never shield. Fixture: `grenade_wall_between_shields`.
- [x] **Auto-target scoring.** Server `scoreAutoTarget` now adds the SMG/LMG bonus (+20) and the stick-with-current-target bonus (+10). Fixtures: `auto_target_prefers_smg_gunner`, `auto_target_sticks_with_engaged_target`.
- [x] **Thrower killed during the fuse.** No drift: since v0.22.8 both sides let a thrown grenade go off after the thrower dies, and both cancel it when the thrower is stunned.
- [x] **Squad path diagonal cut.** No drift: GDScript `_assign_translated_squad_path` translates the lead path the same way (walkable-cell check only). If diagonal corner-cutting in squad moves is a gameplay problem, fix it on both sides together.
- [x] **AI clock mix-up.** `AiCommander` stores the tick's sim time (`simNowMsec`) and uses it for move/face dedup and the watchdog instead of `Date.now()`. Low impact today: server AI is never switched on for online matches (`setupAi` is not called).
- [x] **Grenade fuse timing.** No drift: single-player also resolves fuses in the 0.5s combat scan, so both sides go off at 2.0-2.3s.
- [x] **Orders during deployment.** Fire At and grenades are refused during the timed deployment countdown on both sides (server `deploymentRemainingSec > 0`, client `locks_deployment_zone()`). Hold Fire / Fire At Will toggles still work. Tests: `sim_parity_drift.test.ts`, `gameplay_foundation_tests` "Grenade refused during timed deployment".

## Step 4 - Message and reconnect correctness

- [x] **`grenade_result` vs `grenade_thrown`.** Every failed throw now replies `grenade_thrown` (`match.ts` `handleGrenade`, `index.ts` invalid-command reply); the replay recorder records `grenade_thrown`.
- [x] **Command results go to both sides.** Kept the broadcast, because the opponent's client needs the state in it (halts, stance, facing). Instead `network_client.gd` clears the status text on any result that is not for one of our own pending requests (`_strip_foreign_status`).
- [x] **Forfeit after the reconnect window records no result.** A player who drops mid-match is now held with `match.holdClientTeam` instead of removed, and both match-end paths report held teams (`resultClientTeams`). A reconnect removes the held entry. Tests in `sim_parity_drift.test.ts`.
- [x] **Reconnect snapshot ignored.** `main.gd` `_on_network_match_snapshot` re-applies the server snapshot after a confirmed reconnect and redraws.
- [x] **Any `welcome` counts as a reconnect.** The client stays in the reconnect loop until the welcome; `reconnected: true` ends it, anything else gives up at once.
- [x] **Retreat starts the reconnect loop.** `match_ready_received` is cleared on retreat (`send_leave_match`), `leave_confirmed` and `match_ended`.
- [x] **Client gives up too early.** No attempt cap; retries every 3s until 85s have passed.

- [ ] **In-game reconnect check (before the release build, not blocking the PR):** two clients; cut one player's network for about 10s mid-match and press Retreat. Optional: close-and-rejoin, and a reconnect after the 90s window (should return to the lobby with the result recorded).

## Step 5 - Real fog of war (moved to Phase 48)

- [ ] **Client:** hide unspotted enemies in 1v1 too (`main.gd` `_fog_visual_for_enemy` currently returns GHOST). At most keep a fading last-known marker.
- [ ] **Server:** only send each team the enemy positions it can see (snapshots, movement ticks).

**Done when:** at the start of a match neither player can see the other team's deployment.

---

## Order and size

| Step | Size | Why this order |
|---|---|---|
| 1 Safety-net sync | Small | Biggest player-visible payoff, fixes several bugs at once |
| 2 Parity harness | Medium | Stops new drift; every later fix gets a test |
| 3 Port drift | Medium | Works through the known list with tests |
| 4 Messages / reconnect | Medium | Mostly independent, can be split off |
| 5 Fog of war | Medium | Gameplay change; needs a design decision on last-known markers |

Not in scope:
- Corner presentation polish (peek pose between shots, arrival facing preference). That's client-only and affects both modes; it's tracked in the changelog Known Bugs.
- Security fixes. Those go on the separate security lockdown branch.
