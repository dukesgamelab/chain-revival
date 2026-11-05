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
- [ ] In-game check (see Done when).

**Deploy note:** server and client must ship together. A 0.22.9 client on the new server loses stress decay (it read stress from `scenario_time`), so soldiers would look stuck at their peak stress until the client updates.

**Tests:** `server/tests/soldier_sync.test.ts`, and the `soldier sync` cases in `scripts/tests/authoritative_sync_tests.gd`.

**Fixes:**
- Grenade count stuck at 5 in the UI.
- AI stance / facing / Fire At / grenade results never reaching clients (`ai_commander_framework.ts:175-257`).
- Standing up after a stun not broadcast (`match.ts:790`, `grenade_system.ts:290-306`).

**Done when:** in a 1v1, an AI going prone, a grenade throw count, and a stun recovery all show on the other client without any action-result message.

## Step 2 - Parity test harness

Catch drift as it happens instead of after testers find it.

- [ ] Shared fixtures in `tests/parity/*.json`. Each fixture has:
  - map size and wall/object cells
  - soldiers (cell, facing, stance, stress, weapon)
  - one query
  - expected outcome
- [ ] Server runner: `server/tests/parity.test.ts`, loads each fixture and asserts the expected outcome.
- [ ] Client runner: `scripts/tests/parity_tests.tscn`, loads the same fixtures and asserts the same outcomes headless.
  - Run with: `Godot --headless --path . res://scripts/tests/parity_tests.tscn`
- [ ] First fixtures (pure rule functions):
  - shot LOS status and blocking cell
  - cover type
  - corner peek (side, lean, corner-to-corner)
  - hit chance at a range
  - suppression gain
  - grenade damage / stun by distance and wall
  - auto-target choice
  - arrival facing at a corner

**Done when:** both runners pass on the same fixtures, and a deliberately changed constant on one side makes the other side's run fail.

## Step 3 - Port known server drift

Each item gets a parity fixture first (it should fail), then the fix (it should pass).

- [ ] **Suppression on wall-hugging targets.** `combat_system.ts:132-135` returns before suppression; GDScript applies it first (`combat_system.gd:375-382`).
- [ ] **Grenade blast blocking.** `grenade_system.ts:103-110` uses shot LOS, so the blast passes through walls next to the victim and is blocked by standing soldiers. GDScript uses a wall-only check (`combat_system.gd:2431-2451`).
- [ ] **Auto-target scoring.** `perception.ts` `scoreAutoTarget` lacks the SMG/LMG and stick-with-current-target bonuses (`combat_system.gd:1283-1293`).
- [ ] **Thrower killed during the fuse.** `soldier_state.ts` `markKilled` keeps the pending grenade; GDScript cancels it.
- [ ] **Squad path diagonal cut.** `action_resolver.ts:353-361` translated squad paths skip the pathfinder's no-diagonal-between-walls rule.
- [ ] **AI clock mix-up.** `ai_commander.ts:1406,1460` use `Date.now()` against sim time. Fire dedup never blocks and the watchdog never fires; the AI re-sends Fire At and resets aim. Use sim time everywhere in AI.
- [ ] **Grenade fuse timing.** `match.ts:758` checks only on 0.5s scans, so the 1.8s fuse resolves at 2.0-2.3s.
- [ ] **Orders during deployment.** Grenades and Fire At are accepted during the deployment countdown (`match.ts:600-687`). Lock them like moves.

## Step 4 - Message and reconnect correctness

- [ ] **`grenade_result` vs `grenade_thrown`.** The server sends `grenade_result` for failed throws (`index.ts:677`, `match.ts:657,673`). The client only handles `grenade_thrown`, so each failure waits 3s and times out. The replay recorder also whitelists the wrong name.
- [ ] **Command results go to both sides.** `match.ts:447,493,548,597,645,687`. The opponent's failed orders show on your status bar. Send results only to the issuing team.
- [ ] **Forfeit after the reconnect window records no result.** `index.ts:853` removes the client before the forfeit, so `clientTeams` misses the quitter. Keep the team mapping for pending reconnects.
- [ ] **Reconnect snapshot ignored.** `network_client.gd:618` emits `match_snapshot_received` and nothing listens. Re-apply the snapshot on a confirmed reconnect.
- [ ] **Any `welcome` counts as a reconnect.** Check `reconnected: true` (`network_client.gd:403-413`).
- [ ] **Retreat starts the reconnect loop.** Clear the in-match flag on `leave_confirmed` / `match_ended`.
- [ ] **Client gives up too early.** Base retries on elapsed time (about 85s), not a count of 6.

## Step 5 (optional) - Real fog of war

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
