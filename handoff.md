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
    sql/            Numbered migrations (001-026)
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
| `site_settings` | Feature toggle key-value pairs (chat, regiments, download, leaderboard, registration, appeal) + game_version, download_url, max_rooms |
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

## Completed Phases (1-39)

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

## Phase 38 Details (Complete — Lobby Polish)

**Goal:** Complete the deferred Phase 37 features — player profile card, regimental room enforcement, server-side match settings, and expandable room count.

### What Changed

**Player Card Sidebar** (`scripts/ui/lobby_browser.gd`):
- Clicking a host name in the lobby grid fetches their profile from Supabase and shows a left-side panel
- Card displays: rank with label, regiment name + tag, stats (games played, wins, win %, total kills)
- Close button dismisses the card; clicking another host swaps the card contents
- New `fetch_player_profile()` and `player_profile_fetched` signal in `lobby_client.gd`

**Regimental Room Enforcement** (rooms 3, 4, 6, 7):
- **Client gate**: `_on_room_action()` blocks create/join if `SupabaseAuth.regiment_id` is empty — shows "You must be in a regiment" message
- **Lobby payload**: `host_regiment_id` stored in lobbies table on create
- **Server team assignment** (`server/src/index.ts`): reads `regimentId` from hello message, maps first regiment → USA (Team 1), second regiment → Germany (Team 2)
- `request_side` handler forces side based on regiment-to-team mapping in regimental matches
- New `setClientRegimentId()` in `side_ownership.ts`

**Server-Side Match Settings** (match length 10/15/20 min):
- **Client**: briefing dialog match length dropdown → `NetworkClient.match_length_sec` → sent in hello message as `matchLengthSec`
- **Server**: validates against [600, 900, 1200], calls `match.setScenarioTime()` to override the default 15 min
- `createScenarioState()` in `scenario_rules.ts` now accepts optional `timeSec` parameter
- `MatchOptions` interface extended with optional `scenarioTimeSec`

**Expandable Room Count**:
- `ROOM_CONFIG` constant replaced with dynamic `_room_config` array generated by `_generate_room_config(count)`
- `_fetch_max_rooms()` queries `site_settings` for `max_rooms` value (default 8, max 16)
- `_rebuild_room_grid()` regenerates room rows when max_rooms changes
- Rooms beyond 8 are all "Open Game" type
- DB constraint updated from `room_number <= 8` to `room_number <= 16`

**Website Admin** (`website/src/pages/Admin.tsx`):
- New "Lobby Settings" section in Toggles tab with Max Rooms number input (1-16)
- `useSiteSettings` hook extended with `max_rooms` field

**CI Pipeline** (`.github/workflows/build-and-sign.yml`):
- Commented out `push: tags:` trigger to stop GitHub Actions failure email spam
- Workflow now only runs on `workflow_dispatch` (manual)

### Database Migration (026_lobby_polish.sql — already run)

- `ALTER TABLE lobbies ADD COLUMN host_regiment_id uuid` — stores host's regiment for regimental matches
- `ALTER TABLE lobbies ADD COLUMN match_length_sec integer DEFAULT 900` — stores match duration
- `DROP/ADD chk_room_number` constraint — expanded from `<= 8` to `<= 16`
- `INSERT INTO site_settings ('max_rooms', '8')` — admin-configurable room count

**CI Pipeline — Fully Automated** (`.github/workflows/build-and-sign.yml`):
- Triggers on `workflow_dispatch` only (manual, with version input). Tag push disabled until code signing is set up.
- **Build job**: `barichello/godot-ci:4.7.2` Docker image, cross-compiles Windows exe on Linux
- **Sign job**: Certum SimplySign on Windows runner — disabled (`if: false`) until cert is purchased
- **Release job**: Zips build, auto-publishes GitHub Release (prerelease) via `softprops/action-gh-release@v2` — falls back to unsigned if signing is skipped. Auto-updates `game_version` and `download_url` in Supabase via `SUPABASE_SERVICE_ROLE_KEY` secret — no manual admin steps needed.
- **Export preset**: `"Windows Desktop"`, `custom_features=""` (removed `survival_playtest` gate — full menu with multiplayer)
- **Display**: viewport 1920x1080, window starts maximized (`window/size/mode=2`)
- **CI fixes applied**:
  - Docker image tag: `barichello/godot-ci:4.7.2` (not `4.7-stable`)
  - Export templates symlink: GitHub Actions overrides HOME to `/github/home/`, but templates live at `/root/`. Added step to symlink.
  - Job-level `if` can't access secrets — changed to `if: false` with comment
- **Auto-updater tested end-to-end**: Old build (0.20.0-alpha) detected version mismatch, downloaded 0.21.0-alpha zip, extracted, relaunched with new version. Dialog shows "Update Now" / "Skip" buttons.
- **Update dialog fix**: `max_size = Vector2(500, 250)`, `unresizable = true` — buttons were pushed off-screen before
- **Current version**: `0.21.0-alpha` (`BuildConfig.VERSION`)

**Release workflow (fully automated)**:
1. Bump `BuildConfig.VERSION` in `scripts/core/build_config.gd`
2. Commit and push
3. Trigger workflow: `gh workflow run build-and-sign.yml --ref multiplayer-complete -f version=X.Y.Z-alpha`
4. CI handles everything: builds exe, publishes GitHub Release, updates Supabase `game_version` and `download_url`
5. Players on older versions get the auto-update prompt on next launch

### Known Issues (Phase 38)

- No leave/unjoin RPC for non-host players
- Regiment-vs-regiment team assignment untested with 3v3 (only 1v1 verified)

## Phase 37 Details (Complete — Lobby Room Grid Overhaul)

**Goal:** Replace the flat create-and-join lobby flow with OG-style persistent game rooms. Players see a fixed 8-room grid and click "Join Room" to open a skirmish briefing dialog or join an existing game.

### What Changed

**Lobby UI** (`scripts/ui/lobby_browser.gd` — full rewrite):
- 8 fixed room rows always visible (no create/delete by players)
- Room types: **Open Game** (rooms 1, 2, 8), **Regimental** (rooms 3, 4, 6, 7), **Training** (room 5) — cosmetic labels only in Phase 37
- Columns: Room #, Description, Type, Players, Action button
- "Join Room" on an empty room → opens skirmish briefing dialog (map, team size, match length, AI difficulty for training)
- "Join Room" on a waiting room → joins immediately, match starts when full
- "Leave" button on your own room → cancels hosted lobby
- Recovers hosted lobby state on scene reload (detects your stale lobby from the database)
- Room type labels use default text color (no color coding)
- Removed old scrollable lobby list, "Create Game" button, and waiting panel

**Lobby Client** (`scripts/network/lobby_client.gd`):
- `create_lobby()` now accepts `room_number` parameter
- Cleanup step deletes any stale lobbies by the host before creating
- `list_lobbies()` query fetches waiting + in_progress + own lobbies, ordered by room_number
- `room_number` stored in lobbies table payload

**Developer Tools** (`scripts/ui/mode_select.gd` + `scripts/network/supabase_auth.gd`):
- Dev tools visible only to admins and moderators (not just signed-in dev builds)
- Added `profile_loaded` signal to `SupabaseAuth` — fixes async timing where `is_admin` wasn't set yet when `_ready()` ran
- `_on_profile_loaded()` callback updates dev_box visibility after profile fetch completes

**Training Room PP Suppression**:
- `NetworkClient.is_training` flag set based on room type when starting multiplayer
- Client hello message includes `isTraining: true` for training rooms
- Server (`server/src/index.ts`): `isTrainingMatch` flag zeros out PP in `handleMatchEnded`
- Client (`scripts/ui/mission_debrief_dialog.gd`): PP display shows 0 for training matches

**Admin Players Tab** (`website/src/pages/Admin.tsx`):
- New "Players" tab in website admin panel
- Search players by display name
- Toggle admin role (amber switches) and moderator role (sky blue switches)
- Cannot remove your own admin status (disabled toggle)
- Rank display from RANK_LABELS array

### Database Migrations

**024_lobby_rooms.sql** (already run):
- Adds `room_number` integer column to `lobbies` table
- Partial unique index prevents two active lobbies in the same room
- Check constraint: room_number must be 1–8 or NULL

**025_set_admin.sql** (needs to be run):
- `set_admin(p_target_id, p_is_admin)` security definer RPC
- Only admins can call it; cannot remove your own admin status

### Known Issues (Phase 37)

- Room type restrictions not enforced (regimental rooms open to all players)
- Match length selection is UI-only (server uses its configured time)
- No leave/unjoin RPC for players who joined (not hosted) — leaving just clears client state

## Phase 36 Details (Complete — Announcements & Community)

**Goal:** Add a public news/announcements page with user comments, release notes feed, and newsletter signup to the website.

### Database (Migration 023)

- **`announcements` table**: `id`, `title`, `body` (markdown), `category` (news/patch-notes/community), `version` (nullable, for patch notes), `is_pinned`, `is_published` (draft/published), `author_id`, timestamps
  - RLS: public SELECT for published posts + admin sees all; admin-only INSERT/UPDATE/DELETE
  - Realtime enabled

- **`announcement_comments` table**: `id`, `announcement_id` (FK CASCADE), `user_id`, `display_name`, `body`, `created_at`
  - RLS: public SELECT, authenticated INSERT (own user_id), admin DELETE (moderation)
  - Realtime enabled for live comment updates

- **`newsletter_subscribers` table**: `id`, `email` (UNIQUE), `is_confirmed` (future double opt-in), `player_id` (nullable), `subscribed_at`, `unsubscribed_at` (soft unsubscribe)
  - RLS: public INSERT, admin-only SELECT/UPDATE

- New `announcements_enabled` site setting (default: true)

### Website — News Page

- **Route:** `/news` — `website/src/pages/Announcements.tsx`
- **Tab filtering:** All | News | Patch Notes | Community
- **Announcement cards:** category badge (colored), date, title, optional version badge, markdown body rendered via `react-markdown`
- **Pinned posts** shown first with sky-blue accent border
- **Comments:** expandable per-announcement, realtime subscription for live updates, logged-in users can post, "Sign in to comment" for guests, display name links to player profile
- **Newsletter signup:** email input + subscribe button at bottom of page; upsert on email for idempotent re-subscribe
- **Empty state:** "No announcements yet. Check back soon!"

### Website — Admin Tab

- New "News" tab in Admin dashboard (`website/src/pages/Admin.tsx`)
- **Create/Edit form:** title, category dropdown, version (for patch-notes), markdown body textarea with Edit/Preview toggle, pinned and published checkboxes
- **Announcement list:** all posts (including drafts) with category badge, status badge, edit/delete buttons
- **Comment moderation:** expand comments per announcement, delete button on each
- **Newsletter count:** shown in both the News tab header and the Stats tab grid
- **Toggle:** `announcements_enabled` added to admin toggles

### Website — Footer Newsletter

- Compact inline email signup row in `website/src/components/Footer.tsx` above copyright
- Same upsert logic; "Subscribed!" confirmation replaces the form

### Nav

- "News" link added to nav bar, feature-toggled via `announcements_enabled`

### New Dependency

- `react-markdown` for rendering announcement body content

### Not Yet Done

- Email newsletter sending (emails collected, Resend infrastructure exists, compose/send UI deferred)
- Double opt-in confirmation emails
- Announcement notification push to game client

### Phase 36 Checklist

1. Run migration `023_announcements.sql` in Supabase SQL Editor
2. Deploy: `fly deploy -a chain-revival-ax0q1g --remote-only`
3. Test: create announcement in admin (draft → publish), verify on /news page
4. Test: category filtering, pinned posts, markdown rendering
5. Test: post comments as logged-in user, delete as admin
6. Test: newsletter signup from both /news page and footer

## Phase 35 Details (Complete — Match History & Replay)

**Goal:** Record match events for replay, add match detail pages with a visual replay viewer to the website.

### Server-Side Event Recording

- **ReplayRecorder** (`server/src/replay_recorder.ts`):
  - Hooks into `LocalMatch.broadcast()` — records every game event as it happens, zero game logic changes
  - Captures initial state (map layout, blocked tiles with terrain types, soldier positions, victory points)
  - Records: `move_result`, `face_result`, `position_result`, `fire_at_result`, `fire_control_result`, `grenade_result`, `grenade_explode`, `combat_shots`, `deployment_ended`, `match_ended`
  - Skips high-frequency noise: `movement_tick`, `visibility_update`, `scenario_time`
  - Single JSONB blob per match (~100-300KB for a typical 1v1)

- **Unique match IDs**: Each `LocalMatch` now generates a UUID (`dbMatchId`) for database operations. Game protocol `matchId` stays `"local-mp-1"` for backward compatibility — no Godot client changes needed.

- **Match metadata**: `MatchEndedInfo` now includes `mapId`, `teamSize`, `durationMs`, and `replayData`

- **DZ timing fix**: `CLIENT_READY_TIMEOUT_MS` increased from 15s to 60s — prevents deployment countdown from starting before both players have loaded in

### Database (Migration 022)

- `match_history` gets: `map_id`, `team_size`, `duration_seconds` columns
- New `match_replays` table: `match_id` (PK), `map_id`, `map_width`, `map_height`, `team_size`, `initial_state` (jsonb), `events` (jsonb), `duration_ms`, `event_count`
- RPCs `record_match_result` and `record_player_result` updated with optional metadata params (backward-compatible defaults)
- `saveReplay()` function in `supabase_client.ts` — direct REST insert into `match_replays`

### Website — Match Detail Page

- **Route:** `/match/:id` — `website/src/pages/MatchDetail.tsx`
- **Header:** map name, end cause, duration, team size badges
- **Scoreboard:** two team cards with per-player kills, points, PP, links to player profiles
- **Share button:** copies match URL to clipboard
- **Combat log:** filterable event timeline showing kills, grenade explosions, deployment/match markers

### Website — Replay Viewer

- **Component:** `website/src/components/ReplayViewer.tsx`
- **Canvas-based minimap:** top-down view of the map grid with terrain tiles color-coded by type (trees=green, walls=brown, bushes=light green, etc.)
- **Soldier tokens:** numbered colored circles (blue=USA, red=Germany) with facing indicators and X markers for dead
- **Victory points:** gold ring markers
- **Zoom/pan:** scroll-to-zoom (fit view to 2x), click-drag to pan, Fit button resets. Canvas renders at full 18px/cell detail; CSS transforms handle zoom/pan
- **Playback controls:** play/pause, step forward/back, reset, jump-to-end
- **Speed control:** 1x/2x/4x playback
- **Timeline scrubber:** range input from event 0 to N, shows current time and event count
- **Dynamic cell sizing:** maps range from 80x80 to 140x120 tiles — canvas renders at 18px/cell for detail, CSS transform scales to fit the 700px viewport

### Website — Integration

- **MatchRow** component updated: new matches (UUID match_id) show clickable result links with dotted underline to `/match/:id`; old matches (`local-mp-1`) show plain text — no broken links
- **Player page** and **Leaderboard** queries now fetch `match_id` and pass it to MatchRow
- **Leaderboard "All Matches" tab:** new tab showing every match (filters out old `local-mp-1` entries), one row per match with both players, teams, score comparison, result, and View link to match detail page
- Route added in `main.tsx`

### Not Yet Done

- Godot "View Match" button on mission debrief (link to website match page)
- OG meta tags for social link previews
- Movement animation in replay (currently shows end positions per event, not animated paths)
- DZ boundary enforcement (players can leave DZ before timer expires)

## Phase 34 Details (Code Signing & CI Pipeline)

**Goal:** Set up code signing for the Godot Windows export and a CI pipeline for automated builds.

### Carried Over from Phase 33

- **Auto-updater**: Deferred until code signing is completed.

### CI Pipeline (Done)

- **GitHub Actions workflow** (`.github/workflows/build-and-sign.yml`):
  - Triggers on manual dispatch (version input). Tag push disabled until code signing.
  - **Build job**: `barichello/godot-ci:4.7.2` Docker image, cross-compiles Windows exe on Linux
  - **Sign job**: Certum SimplySign on Windows runner — disabled (`if: false`) until cert is purchased
  - **Release job**: Auto-publishes GitHub Release, auto-updates Supabase `game_version` and `download_url` via `SUPABASE_SERVICE_ROLE_KEY` secret
- **Export preset renamed** from `"Chain Revival - 0.1.0-alpha"` to `"Windows Desktop"` so CI doesn't break on version bumps

### Code Signing (Deferred — waiting for more polished product)

**Plan:** Certum Individual Cloud Code Signing cert (~$115/yr via SSLmentor)
- Purchase from [SSLmentor](https://www.sslmentor.com/certum/certumcodecloudindividual)
- Identity verification: driver's license or passport (1-3 business days)
- No business registration required — individual developer cert
- Cloud-based via **SimplySign** — private key in Certum's HSM, no USB token or PFX file

**Azure Trusted Signing was attempted and abandoned:**
- Identity validation failed — requires a registered business for Public trust certs
- Azure subscription canceled

### When ready to enable signing

1. Purchase Certum cert from SSLmentor (~$115/yr)
2. Complete identity verification (photo ID, 1-3 days)
3. Install SimplySign Desktop locally for local signing
4. For CI: set up `signing` GitHub Environment with approval gate
5. Add GitHub secret: `SIMPLYSIGN_TOTP_SEED` (from SimplySign TOTP setup)
6. Test the full pipeline: manual dispatch → build → sign → draft release
7. Re-enable auto-updater to pull from GitHub Releases

## Phase 33 Details (Just Completed)

### Bug Fixes

- **Multiplayer grenades**: GrenadeCommand was resolving locally but `_step_simulation_tick()` returns immediately in multiplayer, so fuse timer was never checked. Fixed by routing through `NetworkClient.submit_grenade_and_wait()` and adding GrenadeCommand to server-authoritative refuse list in `command_router.gd`.
- **DZ countdown not visible**: `_on_network_scenario_time()` checked `is_deployment_phase()` which was already true from initialization. Changed to check `timed_deployment` flag instead.
- **Client-ready handshake**: Server now waits for all clients to send `client_ready` after scene boot before starting the 15s deployment timer. Safety timeout of 15s starts the match even if older clients don't send `client_ready`. Adjust `DEPLOYMENT_TIME_SEC` or `CLIENT_READY_TIMEOUT_MS` in `server/src/match.ts`.
- **GDScript warnings**: Fixed 17 debugger warnings — integer division, shadowed variables, static-called-on-instance, unused vars/params, incompatible ternary types across `settings_manager.gd`, `regiment_client.gd`, `regiment_browser.gd`, `lobby_browser.gd`.
- **Escape/pause menu**: Opens CocUiTheme "Paused" dialog with Resume and Quit to Menu.
- **Quit button**: Added to main menu, calls `get_tree().quit()`.
- **Dev tools hiding**: Developer section hidden unless `BuildConfig.is_development() and SupabaseAuth.is_signed_in`.

## Phase 32 Details (Just Completed)

- **SettingsManager autoload** (`scripts/core/settings_manager.gd`):
  - New singleton registered in `project.godot`, manages display and keybind settings
  - Persists all settings to `user://settings.cfg` via ConfigFile
  - **Display settings**: fullscreen toggle (via `DisplayServer.WINDOW_MODE_FULLSCREEN`), VSync toggle, resolution picker
  - Supported resolutions: 1280x720, 1366x768, 1600x900, 1920x1080, 2560x1440, 3840x2160
  - Window auto-centers after resolution change
  - **Keybind remapping**: stores per-action key bindings, applies them to InputMap at startup
  - `set_binding()` / `clear_binding()` / `reset_keybinds()` for runtime rebinding
  - `key_name()` helper converts keycodes to display strings via `OS.get_keycode_string()`
  - Default bindings match project.godot: WASD + arrows for movement, Q/E for rotation
- **Tabbed settings dialog** (`scripts/ui/mode_select.gd`):
  - Replaced the audio-only settings popup with a 3-tab `TabContainer` (Audio, Graphics, Controls)
  - **Audio tab**: same Master/SFX/Ambient volume sliders as before (unchanged behavior)
  - **Graphics tab**: Fullscreen checkbox, VSync checkbox, Resolution dropdown (disabled when fullscreen)
  - **Controls tab**: grid showing all 6 remappable actions with primary + secondary key buttons
  - Click any key button → shows "..." → press a key to rebind (Escape cancels)
  - "Reset Defaults" button restores all keybinds to WASD/arrows/Q/E
  - All settings sync when dialog is reopened (`_sync_settings_ui()`)
  - Keybind capture uses `_input()` with `set_input_as_handled()` to intercept during rebinding
- **6 remappable actions**: Pan Up/Down/Left/Right (camera WASD), Rotate Left/Right (Q/E)
  - Each action supports primary and secondary bindings
  - Uses `physical_keycode` for layout-independent binding (same physical key regardless of keyboard layout)

## Phase 31 Details

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
| 40 | Named objectives & field report | Named capture zones on maps (yellow labels), victory points bar, separate Field Report combat log panel (right side, timestamped events) |
| 41 | Chat channels | Regiment chat channels, whisper/DM in global chat, player-created custom channels |
| 42 | Spectator mode | Watch live matches without participating, camera controls, player perspective switching |
| 43 | Community forum | Torn-style threaded forum — categories (General, Trading, Faction, Q&A, etc.), paginated thread lists, thread/reply views, last poster tracking, admin-pinned announcements section; nav tab right after Home |

## Code Signing

**Not yet active.** Deferred until the product is more polished. Plan is **Certum Individual Cloud Code Signing** (~$115/yr via SSLmentor). See Phase 34 details for full setup steps.

- **Local signing**: Install SimplySign Desktop → `signtool sign /fd SHA256 /tr http://time.certum.pl /td SHA256 /a ChainRevival.exe`
- **CI signing**: GitHub Actions workflow already configured, just needs `SIMPLYSIGN_TOTP_SEED` secret
- SmartScreen trust accrues over download volume (OV cert, not EV)

## Game Updates

Auto-updater is built in (Phase 27). On every launch the game checks `site_settings.game_version` against `BuildConfig.VERSION`. If a newer version exists, it prompts the user, downloads the zip from `download_url`, extracts it, and self-updates via a batch script.

### When to Release

Not every commit is a release. Releases are for milestones players should get:
- **After completing a phase** — the main trigger for a new build
- **Critical bug fixes** — something broken in the live build
- **Never for** — WIP commits, handoff updates, refactors, server-only changes (deploy those with `fly deploy` instead)

### CI Release Workflow (tested & working)

1. Bump `BuildConfig.VERSION` in `scripts/core/build_config.gd` (e.g. `0.22.0-alpha`)
2. Commit and push to `multiplayer-complete`
3. Trigger: `gh workflow run build-and-sign.yml --ref multiplayer-complete -f version=0.22.0-alpha`
4. CI builds the exe (~2 min), creates and **auto-publishes** a GitHub Release
5. If `SUPABASE_SERVICE_ROLE_KEY` secret is set: CI auto-updates `game_version` and `download_url` in Supabase — no manual admin steps needed
6. If secret is NOT set: manually update `game_version` and `download_url` in website admin
   - Download URL format: `https://github.com/dukesgamelab/chain-revival/releases/download/vX.Y.Z-alpha/ChainRevival-X.Y.Z-alpha.zip`
7. All running clients will see the update on next launch

### Server-Only Changes (no build needed)

For changes to `server/` or `website/` that don't affect the Godot client:
1. Commit and push
2. `fly deploy -a chain-revival-ax0q1g --remote-only`
3. If new SQL migration: run it in Supabase SQL Editor

### Local Release (fallback — manual build, optional signing)

1. Bump `BuildConfig.VERSION` in `scripts/core/build_config.gd`
2. Export from Godot (Project → Export → Windows Desktop)
3. *(Optional, requires Certum cert)* Sign the exe: `signtool sign /fd SHA256 /tr http://time.certum.pl /td SHA256 /a ChainRevival.exe`
4. Zip the build, upload somewhere accessible
5. Set `game_version` and `download_url` in admin site settings
6. All running clients will see the update on next launch

**Without signing** (current state): players will see SmartScreen/Chrome download warnings.

## Multiplayer Lobby Bug Fixes (v0.22.4-alpha)

- **Stale lobbies persisting after match**: `list_lobbies()` query had `host_id.eq.%s` in the OR clause that bypassed status filtering for the host. Removed — now only fetches `waiting` and `in_progress` lobbies.
- **Lobby recovery loop**: Recovery logic in `_on_lobbies_listed` recovered "in_progress" lobbies AND auto-refresh auto-started them, creating an infinite loop (lobby → side select → back → lobby). Fixed: only recover "waiting" lobbies; DELETE "in_progress" ones during recovery.
- **Double `_start_multiplayer` calls**: Auto-refresh callbacks fired while `await connect_and_wait()` was pending, causing multiple WebSocket connect/disconnect cycles. Added `_starting_match` boolean guard.
- **Export join failure**: `export_presets.cfg` excluded `side_select.tscn` and `match_setup.tscn` — see Known Gotchas.
- **Removed Host Game button**: Players now only join via the room grid.

## Known Bugs

- **Reconnect on game close (BROKEN)**: Closing the game window triggers `player_disconnected` and shows "90s" message, but: (1) countdown never ticks down visually, (2) match forfeits way before 90 seconds, (3) disconnected player's PC shows "no games available" within ~5 seconds. Needs investigation in `server/src/index.ts` disconnect handler and `match.ts` reconnect logic.
- **PP not accumulated after match**: Prestige Points don't increase after winning. Killed all 4 enemy soldiers, won the game, PP stayed at 1340. Kills and victory bonus are not being added. Reported 2026-11-01.

## Known Gotchas

- **IPv6:** Fly.io is IPv6-only internally. Supabase connection strings must use IPv4 or the connection pooler.
- **Supabase RPC overloading:** Supabase doesn't support PostgreSQL function overloading well. Use distinct function names.
- **WebSocket race conditions:** Client can send messages before server registers them. Server handles gracefully.
- **Supabase Realtime channels:** Use unique channel names (`Math.random().toString(36).slice(2)` suffix) and `supabase.removeChannel()` for cleanup to avoid "cannot add callbacks after subscribe()" errors.
- **Godot export exclude filter:** `export_presets.cfg` exclude_filter was stripping `scenes/side_select.tscn` and `scenes/match_setup.tscn` from builds. This caused multiplayer joins to silently fail in exports — the join RPC succeeded (lobby showed 2/2) but `change_scene_to_file` couldn't find the scene in the PCK. Worked fine in the editor because the files exist on disk. Fixed in v0.22.4-alpha. Always verify new scenes aren't in the exclude list.
- **Godot export:** Requires export templates matching the Godot version (4.7).
- **Godot `.uid` files:** Godot 4.7 generates `.uid` resource tracking files. These are gitignored.
- **Reconnect window:** The 90s server timer and 120s client retry window are intentionally offset — the client gives up 30s after the server would forfeit anyway, avoiding a race where the client reconnects just as the server forfeits.
