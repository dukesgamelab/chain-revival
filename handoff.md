# Chain Revival — Project Handoff

## What Is This?

Chain Revival is a tactical squad combat game inspired by Chain of Command, built in Godot 4.7 with an authoritative Node.js game server. Players command squads in turn-based tactical combat with real-time multiplayer via WebSockets.

## Architecture

```
chain-revival/
  scripts/          Godot GDScript — game client (UI, rendering, input)
  scenes/           Godot scenes (.tscn)
  server/           Node.js + TypeScript game server (WebSocket, match logic)
    src/index.ts    Main server — WebSocket handler + static file serving
    src/match.ts    Authoritative match simulation
    src/supabase_auth.ts  Auth verification
    sql/            Numbered migrations (001-020)
  website/          React + Vite + Tailwind SPA
    src/pages/      Home, Login, Leaderboard, Player, Regiments, RegimentManage, Download, Appeal, Admin
    src/hooks/      useAuth, useRealtimeQuery, useSiteSettings
    src/components/ Nav, GlobalChat, RankBadge, StatCard, MatchRow, Footer
  supabase/         Edge Functions (ban-notification)
  maps/             Map data files
  Dockerfile        Multi-stage: build-server → build-website → runtime
  fly.toml          Fly.io deployment config
```

## Tech Stack

| Layer | Tech |
|-------|------|
| Game client | Godot 4.7, GDScript |
| Game server | Node.js 20, TypeScript, raw `node:http` + `ws` |
| Website | React 19, Vite 8, Tailwind CSS 4, React Router 7 |
| Database | Supabase (PostgreSQL + Auth + Realtime) |
| Hosting | Fly.io (single container serves game server + website) |

## Supabase

- **Project URL:** `https://tnyaqreedvdmyworvqbw.supabase.co`
- **Anon key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRueWFxcmVlZHZkbXl3b3J2cWJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5NzA5MzQsImV4cCI6MjEwODU0NjkzNH0.z9P6-W9U-NsJYr5TXxeHsc8Z5_flrDZSOqkNNParqPQ`
- **Site URL:** `https://chain-revival-ax0q1g.fly.dev` (set in Authentication → URL Configuration)
- **Redirect URLs:** `https://chain-revival-ax0q1g.fly.dev/**`

### Key Tables

| Table | Purpose |
|-------|---------|
| `player_profiles` | Display name, rank, prestige points, games/wins/kills, regiment, ban status |
| `match_history` | Per-player match results (team, kills, points, PP, opponent) |
| `regiments` | Regiment name, tag, description, CO, website |
| `regiment_members` | Player-to-regiment membership with roles |
| `chat_messages` | Global and in-game chat (channel, user_id, display_name, message) |
| `site_settings` | Feature toggle key-value pairs (chat, regiments, download, leaderboard, registration, appeal) |
| `ban_appeals` | Player ban appeal submissions (status: pending/approved/denied) |

### Realtime

Enabled on: `player_profiles`, `match_history`, `regiments`, `regiment_members`, `site_settings`, `chat_messages`.

### Rank System

13 ranks: PVT(0), PFC(1), CPL(2), SGT(3), SSG(4), SFC(5), MSG(6), 2LT(7), 1LT(8), CPT(9), MAJ(10), LT COL(11), COL(12).
PP thresholds (ranks 0-9): `[0, 500, 2500, 7500, 17500, 35500, 65500, 115500, 195500, 315500]`.
Ranks 10-12 (MAJ/LT COL/COL) are regiment-assigned only — not earned via PP. Display rank uses assigned rank when set, falls back to PP rank.

## Fly.io

- **App:** `chain-revival-ax0q1g`
- **URL:** `https://chain-revival-ax0q1g.fly.dev`
- **Deploy:** `fly deploy -a chain-revival-ax0q1g --remote-only`
- **Health check:** `GET /health` returns `"ok"`
- Port 3000 serves both WebSocket (game) and HTTP (website)

## Git

- **Branch:** `multiplayer-complete`
- **Remote:** GitHub, user `dukesgamelab`
- **Commit style:** `Phase N: Title` for phase work
- **No Claude attribution.** Never add `Co-Authored-By` lines or any Claude/Anthropic references to commits or PRs. All commits must appear as solely by `dukesgamelab`.

## Completed Phases (1-27)

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

## Phase 31 Details (Just Completed)

- **Audio bus system** (`scripts/core/audio_manager.gd`):
  - Added SFX and Ambient buses routed to Master, created programmatically at startup
  - All combat/footstep/throw players routed to SFX bus; ambient player to Ambient bus
  - Volume control via `master_volume`, `sfx_volume`, `ambient_volume` properties (0.0–1.0 linear)
  - Settings saved to `user://audio_settings.cfg` and loaded on startup
- **Footstep sounds** (`scripts/soldiers/soldier.gd`):
  - `AudioManager.play_footstep()` called in `_arrive_at_chase_cell()` each time a soldier reaches a grid cell
  - Walk vs crawl distinction: crawling uses wider pitch variation and lower volume
  - Throttled to 100ms minimum interval to prevent audio spam from many soldiers moving
  - Uses OG `Mdwn.wav`/`Mup.wav` with generated fallback (short noise+thump burst)
- **Grenade throw sound** (`scripts/core/main.gd`):
  - `AudioManager.play_grenade_throw()` called when throw orders are presented
  - Generated whoosh sound (noise + frequency sweep, 0.25s)
- **Ambient wind layer** (`scripts/core/main.gd`):
  - `AudioManager.start_ambient()` called after match boot completes
  - `AudioManager.stop_ambient()` called on mission debrief finish and return to menu
  - 8-second procedural wind loop (low-pass filtered noise with volume swell)
  - Loops continuously via `finished` signal reconnect
- **Volume controls** (`scripts/ui/mode_select.gd`):
  - "Settings" button added to main menu
  - Dialog with Master, SFX, and Ambient sliders (0–100%, step 5%)
  - Changes apply immediately and persist across sessions
- **Generated fallback audio**: all new sound categories (footsteps, throw, ambient) have procedural fallback samples, matching the existing pattern for weapons/death

## Phase 30 Details

- Phase 30 content was completed in a previous session.

## Phase 29 Details

- **Grenade throw animation on remote client** (`scripts/core/main.gd`, `scripts/network/network_client.gd`):
  - Root cause: `grenade_thrown_received` signal was never connected in `main.gd` — remote clients saw the explosion but not the throw
  - Changed signal to emit the pre-built `ActionResult` (with `throw_orders`, `face_updates`, `movement_halts`) instead of raw payload
  - Added `_on_network_grenade_thrown` handler that applies authoritative state (facing, halt, grid position) and calls `_present_action_result` to play the throw animation
- **Soldier stutter on overlapping move orders** (`scripts/soldiers/soldier.gd`):
  - Root cause: `follow_path()` and `sync_movement_chase_from_state()` snapped the visual position back to the sim's grid cell when a new path arrived mid-move, causing a visible jump
  - Added `_find_nearest_path_cell_ahead()` helper — finds the closest cell in the new path to the current visual position
  - Both `follow_path()` and `sync_movement_chase_from_state()` now use the nearest-cell lookup when redirecting mid-move instead of snapping backward
  - Visual position is preserved during redirect; only soldiers starting fresh movement snap to path[0]
- **Smoother pathfinding presentation** (`scripts/soldiers/soldier.gd`):
  - Added look-ahead blending in `_process()`: when within 30px of the current target cell and a next cell exists, movement direction blends toward the next cell
  - Creates gentle curves at direction changes instead of sharp 90°/45° snaps
  - Authoritative sim unchanged — smoothing is purely visual

## Phase 28 Details

- **Server** (`server/src/index.ts`):
  - Ghost client pattern: disconnected player's side_ownership record stays to block their slot
  - 90-second reconnect window via `pendingReconnects` map (userId → timer/side/team)
  - On reconnect: cancel timer, remove ghost, reassign side/team, send full snapshot
  - `sendJson` now checks `ws.readyState` before sending (prevents errors on ghost sockets)
  - `leave_match` message type: intentional quit → immediate forfeit, no reconnect window
  - `player_disconnected` / `player_reconnected` broadcasts to remaining players
  - Timer cleanup in `handleMatchEnded` and `ensureFreshMatch`
- **Client** (`scripts/network/network_client.gd`):
  - Auto-reconnect loop: up to 6 attempts over 120s client-side window
  - `send_leave_match()` for intentional quit via Leave button
  - New signals: `player_disconnected_received`, `player_reconnected_received`, `reconnect_started`, `reconnect_failed`
  - Status HUD shows reconnect progress
- **Game UI** (`scripts/core/main.gd`):
  - Opponent disconnect/reconnect chat messages and status bar updates
  - Reconnect failure → automatic return to lobby
  - Retreat button becomes "Leave Match" in multiplayer (sends `leave_match`, no reconnect)
- **Known issues** (`scripts/ui/mode_select.gd`): updated from "no reconnection" to "90s reconnect window"

## Phase 27 Details

- **AutoUpdater** (`scripts/network/auto_updater.gd`):
  - On game startup, queries Supabase `site_settings` for `game_version` and `download_url`
  - Compares remote version against `BuildConfig.VERSION` using semantic version parsing
  - If newer version available: shows dialog with current vs latest version
  - User clicks "Update Now" → downloads zip → extracts → launches batch updater → quits
  - Batch script waits for game process to exit, copies new files over old, relaunches
  - "Skip" button lets user play the current version
  - Progress bar shows download percentage
  - Skipped in editor (development) builds
- **Version workflow**: bump `BuildConfig.VERSION` in `scripts/core/build_config.gd`, set matching `game_version` in admin site settings, upload new zip to `/builds/`
- Hooked into `mode_select.gd` — runs automatically on every game launch

## Phase 26 Details

- **Problem:** 4 of 5 multiplayer maps (Crossroads, Twin Ridges, Three Fields, Grand Battle) had zero visual map_objects — only invisible blocked_tiles that the engine defaulted to "tree" type. Players saw flat ground with invisible walls.
- **Solution:** Generated visual terrain objects for all 4 maps using spatial cluster analysis:
  - Identified blocked tile clusters (isolated, lines, small/medium/large groups)
  - Assigned thematically appropriate sprites per map:
    - **Crossroads** (farmland): field walls (WH*), hay bales, bushes, scattered trees
    - **Twin Ridges** (ridgelines): dense tree lines on ridges, bushes in valleys
    - **Three Fields** (tree-line fields): tree line barriers, hay bales, bushes in open areas
    - **Grand Battle** (battlefield): mixed terrain — stone/wood walls, tree clusters, field walls, bushes
  - Linear clusters get consistent wall/fence types; dense clusters get tree groves
- **Object counts:** Crossroads 292, Twin Ridges 457, Three Fields 544, Grand Battle 622
- Available sprite families used: TR01/TR02 (trees), BH01/BH02 (bushes), BG01 (hay), CW01 (cow), WH00-WH11 (field walls), SWAL (stone wall), WWAL (wood wall)
- Gameplay properties preserved from asset registry: trees block LOS/movement (COMPLETE cover), bushes/field walls block movement only (MODERATE cover)

## Phase 25 Details

- **CO/XO Management Dashboard** at `/regiment/manage` (authenticated CO/XO only):
  - Members tab: roster with kick, assign regiment rank (1LT/CPT/MAJ/LT COL/COL), set/remove XO (CO-only)
  - Requests tab: view and accept/reject pending join requests
  - Invites tab: search players by name and send invites, view pending invites
  - Settings tab (CO-only): edit regiment description and website URL
  - Disband tab (CO-only): submit disbandment request for admin review
- **Player Regiment Interactions** on `/regiments` page:
  - "Create Regiment" button: application form (name, tag, description) submitted for admin review
  - "Apply to Join" button on regiment detail (with cancel application)
  - "Leave Regiment" button for members (CO cannot leave — must transfer or disband)
  - Pending invites banner at top of regiments list with accept/decline
  - Pending applications tracker with cancel option
- **Admin Regiment Oversight** — new "Regiments" tab in admin dashboard:
  - Pending regiment applications (create/disband) with approve/reject
  - Active regiments table with force-disband override
  - All pending join requests across all regiments
- SQL migration `020_regiment_management.sql`:
  - `leave_regiment` RPC (atomically removes member, clears profile regiment_id, clears XO if needed)
  - `reject_regiment_join` RPC (CO/XO rejects player request, or player rejects invite)
  - `admin_kick_member`, `admin_transfer_co`, `admin_force_disband` RPCs
  - RLS policies: admin view all join requests, player cancel own pending requests, admin view pending regiments
- New page: `website/src/pages/RegimentManage.tsx`
- Route: `/regiment/manage` (authenticated users only)

### Phase 25 Checklist

1. Run migration `020_regiment_management.sql` in Supabase SQL Editor
2. Deploy: `fly deploy -a chain-revival-ax0q1g --remote-only`
3. Test: create regiment application, approve in admin, join/leave/invite/kick flows
4. Verify admin oversight tab shows all regiment data

## Upcoming Phases

| Phase | Name | Scope |
|-------|------|-------|
| 32 | Settings & keybinds | In-game settings menu (graphics, audio, controls), remappable keybinds, resolution/fullscreen options |
| 33 | Spectator mode | Watch live matches without participating, camera controls, player perspective switching |
| 34 | Code signing & CI pipeline | SignPath integration via GitHub Actions, automated build export, signed Windows exe |
| 35 | Match history & replay | Detailed match replay viewer, turn-by-turn playback, shareable match links on website |
| 36 | Announcements & community | Website: news/announcements page, release notes feed, opt-in email newsletter signup |

## Code Signing (Not Yet Done)

The Windows build is not code-signed, so Chrome flags the download as suspicious and Windows SmartScreen warns on first run. Users can click through both warnings to install.

### Best option: SignPath (free for open-source)

[SignPath.io](https://signpath.io/) provides free code signing for open-source projects. The public GitHub repo qualifies.

1. Hook GitHub repo to SignPath
2. Set up a GitHub Actions workflow to build the Godot export (e.g. `firebelley/godot-export`)
3. Integrate the [SignPath GitHub Action](https://docs.signpath.io/trusted-build-systems/github) into the pipeline
4. On new release/tag: GitHub builds the binary → SignPath signs it → signed `.exe` attached to the release

### Alternative: Certum Open-Source ID (~€30-50)

Manual signing via SignTool/PowerShell. [Certum](https://support.certum.eu/en/how-to-activate-a-code-signing-certificate/) offers a cheap code signing cert for individual open-source developers. Requires identity verification.

### Legacy option: OV certificate ($150-220/yr)

OV is sufficient. EV ($400-600/yr) gets instant SmartScreen trust; with OV, warnings disappear after enough users download without issues.

## Game Updates

Auto-updater is built in (Phase 27). On every launch the game checks `site_settings.game_version` against `BuildConfig.VERSION`. If a newer version exists, it prompts the user, downloads the zip from `download_url`, extracts it, and self-updates via a batch script.

To release an update:
1. Bump `BuildConfig.VERSION` in `scripts/core/build_config.gd`
2. Export the Godot build, zip it, upload to `/builds/` on the server
3. Set `game_version` and `download_url` in admin site settings
4. All running clients will see the update on next launch

## Known Gotchas

- **IPv6:** Fly.io is IPv6-only internally. Supabase connection strings must use IPv4 or the connection pooler.
- **Supabase RPC overloading:** Supabase doesn't support PostgreSQL function overloading well. Use distinct function names.
- **WebSocket race conditions:** Client can send messages before server registers them. Server handles gracefully.
- **Supabase Realtime channels:** Use unique channel names (`Math.random().toString(36).slice(2)` suffix) and `supabase.removeChannel()` for cleanup to avoid "cannot add callbacks after subscribe()" errors.
- **Godot export:** Requires export templates matching the Godot version (4.7).
- **Godot `.uid` files:** Godot 4.7 generates `.uid` resource tracking files. These are gitignored.
- **Reconnect window:** The 90s server timer and 120s client retry window are intentionally offset — the client gives up 30s after the server would forfeit anyway, avoiding a race where the client reconnects just as the server forfeits.
