# Chain Revival - Changelog

## Unreleased on develop (since v0.22.9-alpha)

Copy this into website patch notes when cutting the next release build. Remove items as they ship.

- Fixed reconnecting after a network drop mid-match - if the server still had the old connection open, the duplicate-account kick freed the player's side and left their soldiers unowned. The new connection now takes over the side directly (server-only, hotfix)
- Multiplayer soldier state now stays in sync - the server sends every soldier's stance, facing, stress, grenades, ammo, stun and Fire At target twice a second, so the other player's screen corrects itself (Phase 47)
- Fixed grenade count stuck at 5 in multiplayer (Phase 47)
- Fixed soldiers getting up after a grenade stun not showing for the other player (Phase 47)
- Multiplayer combat now follows the same rules as single-player: soldiers no longer shield each other from a grenade blast and a wall right next to the victim now blocks it, suppression lands on soldiers hugging a wall, and Fire At Will prefers SMG/LMG gunners and favors its current target (Phase 47)
- Fire At and grenades can no longer be ordered during the deployment countdown, in single-player and multiplayer (Phase 47)
- The opponent's order messages ("Target is out of grenade range") no longer show on your status bar (Phase 47)
- Fixed a forfeit after the 90-second reconnect window not recording the match result (Phase 47)
- Reconnecting mid-match is more reliable: the game keeps trying for 85 seconds instead of giving up after 6 tries, restores the full battlefield when it gets back in, and returns to the lobby straight away if the slot is gone. Retreating no longer triggers a reconnect attempt (Phase 47)

---

## Version History

**Current version:** v0.22.9-alpha

### v0.22.9-alpha

#### Security

- Rotated Supabase service role key - server now uses new-format `sb_secret_` key on both Fly and local dev
- Legacy JWT-based API keys still active (Godot client depends on legacy `anon` key for auth)
- Fixed CI shell injection in build workflow - version input now validated with regex and passed via env variable
- Disabled ban notification emails until an official domain is purchased and verified in Resend
- Fixed zip slip vulnerability in auto-updater - malicious zip entries with path traversal are now rejected
- Tightened chat message RLS - regiment and custom channel messages now restricted to members only (migration 033)
- Fixed isTraining exploit - only the first player (before sides assigned) can enable training mode
- Fixed duplicate account connections - second connection kicks the first, prevents one account holding both sides
- Removed HS256 fallback that accepted any token when JWT secret was unset

### v0.22.8-alpha

#### Features

- **Chat channels** - Multi-channel chat with tabs (Global, Regiment, Custom). Create custom channels with "+", leave with "x" on the tab
- **Custom channel management** - Channel creators, admins, and moderators can delete custom channels
- **Whisper command** - Send private messages with `/w PlayerName message`
- **Click-to-whisper** - Click any player's name in chat to start a whisper
- **Player suggestions** - Typing `/w` shows a popup with matching player names
- **Server-side DZ enforcement** (Phase 43) - Server validates deployment zone boundaries during the 15s deployment phase. Moves outside your team's DZ are blocked
- **Friendly grenade damage** (Phase 44) - Grenades now damage and stun same-team soldiers. Throw preview line turns yellow when friendlies are in blast radius. AI avoids friendly fire automatically
- **Lethality rebalance** (Phase 44) - Lethality multiplier tuned from 0.9 to 0.6 for balanced no-wound-state play
- **Sustained fire suppression** (Phase 45) - Fire At generates 1.5x suppression stress, making focused fire the way to pin enemies
- **Panicked restrictions** (Phase 45) - Panicked soldiers (stress >= 70) cannot use Fire At. Grenades still allowed. Server-side enforcement added
- **Stress UI feedback** (Phase 45) - Stress label shows band name + color (Nervous/Suppressed/Pinned/Panicked). Fire At button greys out when panicked. Soldier sprites get a subtle warm tint at high stress
- **Dev server toggle** - Create `dev_server.txt` in project root with local server URL to test develop branch in multiplayer without deploying. Lobby shows yellow LOCAL indicator
- **Cover status display** (Phase 46) - Soldiers next to obstructions now show "Cover" or "Cover (Prone)" in the command row instead of just "Standing"/"Prone". Cover label shows in green
- **Reconnect countdown** (Phase 46) - Opponent disconnect message now counts down second-by-second instead of showing a static "90s" message
- **Corner-to-corner shooting** (Phase 46) - Two soldiers hugging corners can now trade fire around a building (OG behavior). When the direct line is blocked partway, the shot is checked from each soldier's lean-out tile past his corner. The target only leans out when facing the shooter, and takes moderate cover when he does. A soldier hugging the wall straight between the two keeps complete cover
- **Rejoin after closing the game** (Phase 46) - If you close the game mid-match, your room shows a "Rejoin" button when you come back to the lobby. It reconnects you to your held slot within the 90s window, or tells you the match has ended

#### Bug Fixes

- Removed footstep sounds - constant clicking noise during soldier movement (Phase 46)
- Removed ambient wind loop - distracting background audio (Phase 46)
- Removed grenade throw whistle sound - generated placeholder sounded unnatural (Phase 46)
- Fixed status and stress column colors never showing (Phase 46)
- Fixed soldiers not taking the corner-hug pose when arriving at a corner (Phase 46)
- Fixed soldiers hugging the far side of a corner being drawn on top of the wall when the camera is rotated (Phase 46)
- Fixed corner pose leaning the wrong way when the wall is straight ahead (Phase 46)
- Fixed corner left/right being swapped (Phase 46)
- Fixed enemy soldiers standing in the open instead of in their corner pose on the opponent's screen (Phase 46)
- Fixed soldiers staying "Panicked" forever in multiplayer (Phase 46)
- Fixed soldiers on Fire At going idle after their target died or slipped out of sight (Phase 46)
- Fixed soldiers on Fire At staying locked on a target they can't hit while ignoring an exposed enemy (Phase 46)
- Fixed soldiers firing from a corner dropping prone out in the open (Phase 46)
- Soldiers arriving at a building corner now turn to look down the side of the building (Phase 46)
- Corner behavior now matches OG (lookout pose, scan peek, lean-out fire) (Phase 46)
- Fixed shots grazing diagonally past wall corners (Phase 46)
- Grenade stun now lasts at least 5 seconds anywhere in the 2-tile blast (6s on a direct hit)
- Fixed grenades vanishing when the thrower is shot during the fuse (single-player)
- Fixed server not enforcing panicked Fire At rejection (Phase 45)
- Fixed server not applying stress movement speed modifier (Phase 45)
- Fixed Fire At button not disabling when panicked (Phase 45)
- Fixed stress column too narrow for band labels (Phase 45)
- Fixed admin dashboard player role assignment
- Fixed crawl animation regression (Phase 44)
- Fixed mid-move mode switch not updating speed until next path assignment (Phase 44)
- Fixed post-stun movement mode not resetting to RUN (Phase 44)
- Fixed repeated-click move bug (Phase 44)
- Fixed move redirect snap-back (Phase 44)

#### Security & Stability

- Hardened database permissions across player profiles, lobbies, and regiment operations
- Server-only functions are no longer accessible from the client
- Improved server input validation and payload limits
- Fixed a chat channel deletion bug
- Lobby join now properly checks authentication and ban status
- Prevented duplicate account connections in the same match
- Hardened static file serving
- Added WebSocket payload size limits

### v0.22.7-alpha

- Enlarge all dialog fonts and sizes for readability

### v0.22.6-alpha

- Fix auto-updater loop

### v0.22.5-alpha

- UI scaling fix and enlarged menu

### v0.22.4-alpha - Multiplayer Lobby Bug Fixes

- **Stale lobbies persisting after match**: `list_lobbies()` query had `host_id.eq.%s` in the OR clause that bypassed status filtering for the host. Removed - now only fetches `waiting` and `in_progress` lobbies.
- **Lobby recovery loop**: Recovery logic recovered "in_progress" lobbies AND auto-refresh auto-started them, creating an infinite loop. Fixed: only recover "waiting" lobbies; DELETE "in_progress" ones during recovery.
- **Double `_start_multiplayer` calls**: Auto-refresh callbacks fired while `await connect_and_wait()` was pending, causing multiple WebSocket connect/disconnect cycles. Added `_starting_match` boolean guard.
- **Export join failure**: `export_presets.cfg` excluded `side_select.tscn` and `match_setup.tscn`.
- Removed Host Game button - players now only join via the room grid.

---

## Completed Phases

| Phase | Name |
|-------|------|
| 1-6 | Core multiplayer (WebSocket, authoritative match, grenades, AI commanders, victory conditions) |
| 7 | Godot 4.7 upgrade |
| 8 | Online multiplayer (Supabase auth, lobby, LAN support) |
| 9 | Chat system (global + in-game via Supabase) |
| 10 | Fly.io deployment |
| 11 | IPv6 fix + Railway removal |
| 12 | Match history, leaderboards, kill tracking |
| 13 | Prestige points, ranks, leaderboard search |
| 14 | Regiments & companies |
| 15 | Chat polish (Supabase Realtime replaces polling) |
| 16 | Admin & moderation tools |
| 17 | Moderator roles |
| 18 | Map overhaul |
| 19 | Team size & map selection |
| 20 | Game polish |
| 21 | Tutorial mode & rank fix |
| 22 | Website integration (React SPA, admin dashboard, forgot password, ban notification Edge Function) |
| 23 | Build & distribution (Godot Windows export, download page, build serving, admin version/URL config) |
| 24 | Alpha launch (bug reports, feedback, privacy policy, ToS, server capacity bump) |
| 25 | Regiment management (CO/XO dashboard, player interactions, admin oversight) |
| 26 | Map overhaul (visual terrain for all multiplayer maps) |
| 27 | Auto-updater (startup version check, self-updating game client) |
| 28 | Match reconnection (90s reconnect window, ghost client, Leave Match button) |
| 29 | Movement & animation polish (stutter fix, grenade throw on remote, path smoothing) |
| 30 | Chat improvements (whisper/announce in all game modes, chat history persistence, mute/block) |
| 31 | Sound effects (combat audio, footsteps, grenade throw, ambient wind, volume controls) |
| 32 | Settings & keybinds (tabbed settings menu, fullscreen/resolution/vsync, remappable keybinds) |
| 33 | Bug fixes & testing (multiplayer grenades, DZ countdown, client-ready handshake, GDScript warnings) |
| 34 | Code signing & CI pipeline (GitHub Actions automated Godot build, Certum code signing deferred) |
| 35 | Match history & replay (event recording, replay viewer with zoom/pan, match detail page, All Matches tab) |
| 36 | Announcements & community (news page with comments, release notes feed, newsletter signup, admin management) |
| 37 | Lobby room grid overhaul (8-room grid, briefing dialog, training PP suppression, admin Players tab) |
| 38 | Lobby polish (player card sidebar, regiment-vs-regiment enforcement, match length wiring, expandable rooms, admin max_rooms) |
| 39 | Distribution pipeline & leaderboard player cards (CI tested end-to-end, auto-updater verified, 1080p maximized, clickable leaderboard names, auto-publish releases) |
| 40 | Named objectives, VP capture progress & multiplayer sync |
| 41-42 | Chat channels & whispers (multi-channel, custom channels, /w whisper, click-to-whisper) |
| 43 | Server-side DZ enforcement |
| 44 | Combat realism (friendly grenades, lethality tuning, movement fixes) |
| 45 | Suppression & pinning (sustained fire bonus, panicked restrictions, stress UI) |
| 46 | Corner shooting, reconnect, cover status, security lockdown |

---

## Phase Details

### Phase 45 - Suppression & Pinning

**Goal:** Make sustained fire a real tactical tool - focused fire builds stress faster, panicked soldiers lose Fire At, and the UI shows stress state clearly.

**What Changed:**

- **Sustained fire suppression bonus** (`combat_system.gd`, `combat_system.ts`): Shots from a sustained Fire At engagement generate 1.5x suppression stress. Configurable via `sustained_fire_suppression_mult` in `gameplay_policies.json`. This is the core pinning mechanic - focus fire on a position to degrade and suppress enemies
- **Panicked Fire At block** (`action_resolver.gd`, `action_resolver.ts`): Panicked soldiers (stress >= 70) cannot use Fire At. Grenades are still allowed when panicked
- **Server-side panicked enforcement** (`action_resolver.ts`, `stress_accuracy.ts`): Server now rejects Fire At orders from panicked soldiers. Previously the panic Fire At check was client-only (security gap). Added `isStressPanicked()` and `isStressPinned()` helpers
- **Server-side stress movement speed** (`action_resolver.ts`, `stress_accuracy.ts`): Server now applies stress band movement modifiers. Previously movement speed in multiplayer ignored stress entirely
- **UI stress colors and band labels** (`soldier_command_row.gd`): Stress label now shows band name + percentage ("Pinned 52%") with color coding - white (calm), yellow (nervous), orange (suppressed), red (pinned), dark red (panicked). Activity status "Pinned" and "Panicked" also colored
- **Button disabling** (`command_bar.gd`, `soldier_command_row.gd`): Fire At button greys out when a soldier is panicked. Fixed a bug where `set_row_enabled` was overriding the disable
- **Soldier sprite stress tint** (`soldier.gd`): Subtle warm modulate tint on soldiers at pinned (>= 45) and panicked (>= 70) stress levels. Visible on both friendly and enemy soldiers
- **Dev server toggle** (`network_client.gd`, `lobby_browser.gd`): Create `dev_server.txt` in project root with a server URL (e.g. `ws://192.168.0.4:3000`) to test locally without deploying. Lobby title shows yellow LOCAL indicator. File is gitignored

No migration needed. Both client and server changes.

### Phase 44 - Combat Realism

**Goal:** Friendly grenade damage, lethality rebalance, and movement bug fixes.

**What Changed:**

- **Friendly grenade damage** (`combat_system.gd`, `grenade_system.ts`): Removed friendly immunity from blast resolution. Grenades now kill/stun same-team soldiers. Removed the server-side "cannot throw" block. Throw preview line turns yellow when friendlies are in blast radius
- **Lethality tuning** (`gameplay_policies.json`, `hit_resolution.ts`): 0.9 -> 0.6. Balanced for no wound state - soldiers die less often per hit but combat still feels decisive
- **Crawl animation fix** (`action_resolver.gd`): `_stand_up_for_locomotion` now forces prone when switching to CRAWL mode, fixing a regression where crawling soldiers appeared standing
- **Mid-move speed fix** (`action_resolver.gd`): `arm_movement_mode_for_soldier` now updates `move_speed_mult` immediately when a soldier is already moving, not just on next path assignment
- **Post-stun movement reset** (`soldier_state.gd`, `grenade_system.ts`): `recover_from_stun` resets movement mode to RUN so recovered soldiers don't stay in crawl mode
- **Repeated-click move fix** (`action_resolver.gd`, `action_resolver.ts`): Early return when soldier is already moving to the clicked destination. Prevents the path-clear/reassign cycle that locked soldiers in place
- **Redirect snap-back fix** (`action_resolver.gd`, `action_resolver.ts`): Removed `movement_halts` from `_assign_move_path` and `_assign_translated_squad_path`. The presentation layer's `follow_path` now sees `was_moving = true` and uses smooth visual blending instead of snapping back to grid position

No migration needed. Both client and server changes.

### Phase 43 - Server-Side DZ Enforcement

**Goal:** Validate deployment zone boundaries on the server so players cannot move soldiers outside their DZ during the 15-second deployment phase in multiplayer.

**What Changed:**

- **Server MapData** (`server/src/map_data.ts`): `isDeploymentCell(teamId, cell)` method with Set-based O(1) lookup
- **Server Action Resolver** (`server/src/action_resolver.ts`): `executeMove` accepts `deploymentLocked` flag. Single soldier moves outside DZ rejected. Squad moves skip members whose target lands outside DZ.
- **Server Match** (`server/src/match.ts`): `handleMove` passes `deploymentLocked = this.deploymentRemainingSec > 0`
- **Client Multiplayer Gate** (`scripts/core/main.gd`): `_apply_move_command` checks DZ before sending to server in multiplayer mode

No migration needed. Server-only change.

### Phase 40 - Named Objectives, VP Capture & Sync

**Goal:** Add named VP labels on maps, VP ownership bar in HUD, timed VP capture mechanic, and fix multiplayer VP sync.

- **VP Name Labels** (`scripts/map/victory_point_layer.gd`): Yellow text labels below diamond markers from `vp_name` field
- **VP Bar HUD** (`scripts/ui/vp_bar.gd`): Panel below ScoreHud with colored holder dots and capture progress bar
- **VP Capture Progress**: 20-second timer. Server (`server/src/victory_points.ts`) and client (`scripts/combat/victory_point_system.gd`) mirror logic
- **Multiplayer VP Sync**: Server broadcasts `vp_update` messages on state changes
- **Regiment Leave Fix**: Changed from raw REST DELETE to `leave_regiment` RPC

Migration 027 (PP fix) - already run. Server change already deployed.

### Phase 38 - Lobby Polish

**Goal:** Complete deferred Phase 37 features - player profile card, regimental room enforcement, server-side match settings, expandable room count.

- **Player Card Sidebar**: Click host name in lobby grid to see rank, regiment, stats
- **Regimental Room Enforcement** (rooms 3, 4, 6, 7): Client gate blocks non-regiment players, server maps regiments to teams
- **Server-Side Match Settings**: Match length 10/15/20 min, validated server-side
- **Expandable Room Count**: Dynamic room config from `site_settings.max_rooms` (default 8, max 16)
- **Website Admin**: Max Rooms input in Lobby Settings

Migration 026 - already run. CI workflow limited to `workflow_dispatch` only.

### Phase 37 - Lobby Room Grid Overhaul

**Goal:** Replace flat create-and-join flow with OG-style persistent game rooms.

- **Lobby UI** (`scripts/ui/lobby_browser.gd`): Full rewrite. 8 fixed room rows, room types (Open/Regimental/Training)
- **Training Room PP Suppression**: `isTraining` flag zeros out PP in match results
- **Admin Players Tab**: Search players, toggle admin/moderator roles
- **Dev Tools**: Visible only to admins/moderators

Migrations 024, 025 - already run.

### Phase 36 - Announcements & Community

**Goal:** Public news page with comments, release notes, newsletter signup.

- **Announcements**: Markdown-rendered posts with categories (news/patch-notes/community), pinning, draft/published state
- **Comments**: Realtime per-announcement, admin moderation
- **Newsletter**: Email signup with upsert, subscriber count in admin
- **Admin**: Create/edit announcements, moderate comments, toggle feature

Migration 023 - already run. Dependency: `react-markdown`.

### Phase 35 - Match History & Replay

**Goal:** Record match events for replay, add match detail pages with visual replay viewer.

- **ReplayRecorder** (`server/src/replay_recorder.ts`): Hooks into broadcast, records all game events as JSONB
- **Website Match Detail** (`/match/:id`): Header, scoreboard, combat log, share button
- **Replay Viewer** (`website/src/components/ReplayViewer.tsx`): Canvas minimap, soldier tokens, zoom/pan, playback controls, speed control, timeline scrubber
- **All Matches tab** on leaderboard

Migration 022 - already run.

### Phase 34 - Code Signing & CI Pipeline

- **CI Pipeline**: GitHub Actions with `barichello/godot-ci:4.7.2`, auto-publish releases, auto-update Supabase
- **Code Signing**: Deferred. Plan is Certum Individual Cloud Code Signing (~$115/yr via SSLmentor)

### Phase 33 - Bug Fixes & Testing

- Multiplayer grenades routed through `NetworkClient.submit_grenade_and_wait()`
- DZ countdown visibility fix
- Client-ready handshake before deployment timer
- 17 GDScript warning fixes
- Escape/pause menu, quit button

### Phase 32 - Settings & Keybinds

- **SettingsManager autoload**: Display settings (fullscreen, VSync, resolution), keybind remapping
- **Tabbed settings dialog**: Audio, Graphics, Controls tabs
- 6 remappable actions with primary + secondary bindings

### Phase 31 - Sound Effects

- Audio bus system (Master/SFX/Ambient)
- Footstep sounds (walk vs crawl), grenade throw whoosh, ambient wind loop
- Volume controls with persistence

### Phase 28 - Match Reconnection

- Ghost client pattern, 90-second reconnect window
- Auto-reconnect loop (6 attempts over 120s)
- Leave Match button for intentional quit

### Phase 27 - Auto-Updater

- Startup version check against Supabase `site_settings`
- Download zip, extract, self-update via batch script
- Skip option for current version

### Phase 25 - Regiment Management

- CO/XO dashboard at `/regiment/manage` (members, requests, invites, settings, disband)
- Player regiment interactions (create, apply, leave, accept invites)
- Admin regiment oversight tab

Migration 020 - already run.

---

## SQL Migrations

All migrations in `server/sql/`, numbered 001-033. All have been run in Supabase.

| Migration | Phase | Purpose |
|-----------|-------|---------|
| 020 | 25 | Regiment management RPCs |
| 022 | 35 | Match replays table, match metadata columns |
| 023 | 36 | Announcements, comments, newsletter tables |
| 024 | 37 | Lobby room_number column |
| 025 | 37 | set_admin RPC |
| 026 | 38 | Lobby polish (host_regiment_id, match_length_sec, room limit 16, max_rooms setting) |
| 027 | 40 | PP tracking fix |
| 028 | 41-42 | Chat channels, channel members, whisper columns |
| 029 | 41-42 | Fix channel members RLS recursion |
| 030 | 41-42 | Custom channel discovery RPCs |
| 031 | 41-42 | Delete custom channel RPC |
| 032 | 46 | Security lockdown (column grants, REVOKE/GRANT EXECUTE, auth.uid() hardening, SET search_path) |
| 033 | 46 | Chat channel RLS - restrict message SELECT/INSERT to channel members |

---

## Version Roadmap

**Current version:** v0.22.9-alpha

**Path to v1.0.0-alpha** - Core gameplay and progression must feel complete and stable. After phase 51, do a bug fix pass based on tester feedback, then cut v1.0.0-alpha.

| Phase | Name | Scope | Priority |
|-------|------|-------|----------|
| ~~44~~ | ~~Combat realism~~ | ~~Done - friendly grenades, lethality 0.6, movement fixes~~ | ~~Complete~~ |
| ~~45~~ | ~~Suppression & pinning~~ | ~~Done - sustained fire 1.5x suppression, panicked blocks, UI stress feedback~~ | ~~Complete~~ |
| ~~46~~ | ~~Reconnect fix~~ | ~~Done - countdown, lobby Rejoin after closing the game, cover status, tester audio fixes~~ | ~~Complete~~ |
| 47 | Sim parity | **Code complete** - soldier sync, parity test harness, server drift fixes, message and reconnect fixes. Quick in-game reconnect check before the release build | v1 required |
| 48 | Fog of war | Server-side position filtering, hide unspotted enemies, last-known markers (v0.23.0) | v1 required |
| 49 | Combat keybinds | OG-style keyboard shortcuts (D/W/R/C/F/G/P/H etc.), field report panel | v1 required |
| 50 | PP balance & career rewards | PP lost on killed-by-rank, Medal of Courage payouts | v1 required |
| 51 | Regiment officer promotions | CO promotes members to officer ranks, promotion slots by member count | v1 required |
| -- | Bug fix pass | Tester feedback, stability, polish | v1 required |
| -- | v1.0.0-alpha release | Build, tag, deploy | - |
| 52 | Community forum | Torn-style threaded forum - categories, thread lists, replies, admin pins | Post-v1 |
| 53 | Newsletter & notifications | Resend email sending, double opt-in, announcement push to client | Post-v1 |
| 54 | Replay polish | Movement animation, "View Match" button, OG meta tags | Post-v1 |

**Versioning:** Bump patch (0.22.8, 0.22.9) for bug fixes, minor (0.23, 0.24) for each phase. Jump to 1.0.0-alpha after the bug fix pass following phase 51.

---

## Known Bugs

- **Camera rotation drops the corner pose**: a soldier who arrives at a building corner and looks down the wall loses that pose when the camera is rotated (Q/E), and stays in a normal stand even after rotating back to the start. Seen in multiplayer on Farm Fight (Store Rooms corner). Rotation redraws via `main.gd` `_refresh_view_rotation` -> `_sync_soldier_view`, which recomputes the corner pose from tile + facing; arrival sets it another way. Not caused by the Phase 47 soldier sync.
- **Corner cover presentation polish** - still to check: how far the corner fire step plus the 0.5-tile lean pushes the sprite toward the wall, and whether the Face command feels clunky along walls (clicks snap to 8 directions).
- **Bullet hits never stun or wound**: a rifle hit kills at 60% (lethality 0.6) and otherwise does nothing lasting; stun only comes from grenades. Richard expected hits to sometimes stun. Combat balance decision.
- **Grenade stuns feel ineffective**: Richard reports never landing a stun without getting shot, even a few tiles away. Stunned soldiers cannot fire (checked on client and server). Main cause found and fixed: in single-player a thrower shot during the 1.8s fuse lost his grenade. Remaining possibilities: other enemies, throws landing outside the 2-tile blast or behind a wall. The stun hold also reuses the normal prone idle after the ~2s knockdown, so it can look like the stun ended early. Next occurrence: read the game log ("stunned by grenade blast" / "killed by grenade blast" lines). Consider a clearer stunned pose or marker.
- **No effective fog of war**: Both teams are visible from across the map, including in the deployment zone before the game starts. Two causes: (1) in 1v1 matches the client draws unspotted enemies as tinted "ghosts" instead of hiding them (`main.gd` `_fog_visual_for_enemy` returns GHOST when `_is_one_v_one_match()`), and (2) the server sends every soldier's position to every client, so even hidden enemies are known to a modified client. Fix: hide unspotted enemies (keep a last-known marker at most) and have the server only send enemy positions the receiving team can see.
- **Wall rotation on camera turn**: Some wall sprites don't rotate correctly with the camera. Reported by tester on The Fortress map - needs investigation in facet rotation system.

### Fixed Bugs (for reference)

- **Reconnect on game close** (Phase 46): Countdown was stuck at 90s, and a player who closed the game had no way back (room showed "In Game", host's lobby got deleted on relaunch). Fixed with a working countdown and a lobby Rejoin button. Note: local `npm run dev` needs `SUPABASE_URL` set or logins can't be verified, everyone joins as a guest, and the reconnect window never opens.

- **PP not accumulated after match**: Migration 022 (Phase 35) accidentally dropped prestige_points, total_kills, and rank updates from both `record_match_result` and `record_player_result` RPCs. Fixed by migration `027_fix_pp_tracking.sql`.
- **Regiment leave from Godot client broken**: `regiment_client.gd` did a raw REST DELETE on `regiment_members` instead of calling the `leave_regiment` RPC. Fixed in Phase 40.

---

## Future Features (not scheduled)

- **Spectator mode**: Watch live matches without participating, camera controls, player perspective switching.
- **More maps**: OG has 30+ scenarios, Chain Revival has 7. Deferred until existing maps are tweaked and playtested.
- **Soldier stacking prevention**: Currently soldiers can occupy the same tile (OG allowed this too). Could add collision/stacking rules later.
- **Rich text editor for announcements**: Replace plain textarea with markdown toolbar editor. Body already renders via `ReactMarkdown`.
- **Chat online list**: Show who's connected in the chat panel. Requested by tester Pai-ku-han (also asked for PMs, which already exist via `/w` and click-to-whisper).
- **Admin error logs & event viewer**: Record server error logs and game events to a Supabase table, with a browsable/filterable view in the website admin panel. Replaces needing to SSH into Fly logs for debugging.
- **Migrate off legacy Supabase API keys**: Switch Godot client from legacy `anon` JWT key to new `publishable` key format, update all GDScript Supabase REST calls, then disable JWT-based API keys in dashboard.
- **Chat BBCode whitelist**: Allow safe formatting tags (bold, italic, color) in chat while blocking dangerous ones (url, img). Currently all BBCode is escaped.
- **Official website & domain**: Get a proper domain for the project. Currently served from `chain-revival-ax0q1g.fly.dev`. `chain-revival.com` belongs to the original forked project, not us. Ban notification emails disabled until a domain is purchased and verified in Resend.
