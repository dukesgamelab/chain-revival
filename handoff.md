# Chain Revival - Project Handoff

## What Is This?

Chain Revival is a tactical squad combat game inspired by Chain of Command, built in Godot 4.7.2 with an authoritative Node.js game server. Players command squads in turn-based tactical combat with real-time multiplayer via WebSockets.

## Architecture

```
chain-revival/
  scripts/          Godot GDScript - game client (UI, rendering, input)
  scenes/           Godot scenes (.tscn)
  server/           Node.js + TypeScript game server (WebSocket, match logic)
    src/index.ts    Main server - WebSocket handler + static file serving
    src/match.ts    Authoritative match simulation
    src/supabase_auth.ts  Auth verification
    sql/            Numbered migrations (001-033)
  website/          React + Vite + Tailwind SPA
    src/pages/      Home, Login, Leaderboard, Player, Regiments, RegimentManage, Download, Appeal, Admin
    src/hooks/      AuthProvider, useRealtimeQuery, useSiteSettings
    src/components/ Nav, GlobalChat, RankBadge, StatCard, MatchRow, Footer
  supabase/         Edge Functions (ban-notification)
  maps/             Map data files
  Dockerfile        Multi-stage: build-server -> build-website -> runtime
  fly.toml          Fly.io deployment config
```

## Related Docs

- **[game-systems.md](game-systems.md)** - Combat formulas, weapon stats, cover, suppression, rank thresholds, grenade mechanics
- **[changelog.md](changelog.md)** - Version history, completed phases, phase details, roadmap, known bugs

## Tech Stack

| Layer | Tech |
|-------|------|
| Game client | Godot 4.7.2, GDScript |
| Game server | Node.js 20, TypeScript, raw `node:http` + `ws` |
| Website | React 19, Vite 8, Tailwind CSS 4, react-router-dom 7 |
| Database | Supabase (PostgreSQL + Auth + Realtime) |
| Hosting | Fly.io (single container serves game server + website) |

## Supabase

- **Project URL:** `https://tnyaqreedvdmyworvqbw.supabase.co`
- **Site URL:** `https://chain-revival-ax0q1g.fly.dev` (set in Authentication -> URL Configuration)
- **Redirect URLs:** `https://chain-revival-ax0q1g.fly.dev/**`

### Key Tables

| Table | Purpose |
|-------|---------|
| `player_profiles` | Display name, rank, prestige points, games/wins/kills, regiment, ban status |
| `match_history` | Per-player match results (team, kills, points, PP, opponent) |
| `regiments` | Regiment name, tag, description, CO, website |
| `regiment_members` | Player-to-regiment membership with roles |
| `chat_messages` | Global and in-game chat (channel, user_id, display_name, message) |
| `chat_channels` | Custom and regiment chat channels |
| `chat_channel_members` | Channel membership |
| `site_settings` | Feature toggle key-value pairs + game_version, download_url, max_rooms |
| `ban_appeals` | Player ban appeal submissions (status: pending/approved/denied) |
| `announcements` | News posts with categories, pinning, draft/published state |
| `announcement_comments` | Per-announcement user comments |
| `newsletter_subscribers` | Email signups for newsletter |
| `match_replays` | Recorded match events for replay viewer |

### Realtime

Enabled on: `player_profiles`, `match_history`, `regiments`, `regiment_members`, `site_settings`, `chat_messages`.

## Fly.io

- **App:** `chain-revival-ax0q1g`
- **URL:** `https://chain-revival-ax0q1g.fly.dev`
- **Deploy:** `fly deploy -a chain-revival-ax0q1g --remote-only`
- **Health check:** `GET /health` returns `"ok"`
- Port 3000 serves both WebSocket (game) and HTTP (website)

## Git

- **`main`** is the stable/release branch. Only finished, tested work lands here.
- **`develop`** is the integration branch. Feature branches merge here for testing before release. When ready to release, merge `develop` into `main`.
- **Feature branches** for phase work: branch off `develop` as `chat-channels`, `lobby-rework`, etc. Merge back to `develop` when the feature is complete.
- **Hotfix branches** for urgent fixes: branch off `main` as `hotfix/short-name`. Fix, merge into both `main` and `develop`.
- **Remote:** GitHub, user `dukesgamelab`
- **No Claude attribution.** Never add `Co-Authored-By` lines or any Claude/Anthropic references to commits or PRs. All commits must appear as solely by `dukesgamelab`.

## Current Work - Phase 48 Fog of War (branch: fog-of-war)

Goal: you only see, and your game only receives, the enemies your side has spotted. Full plan, decisions and checklist: [docs/fog-of-war-plan.md](docs/fog-of-war-plan.md). Spotting rules and what each side is sent: [game-systems.md](game-systems.md) "Spotting and Fog of War".

**No SQL migrations needed.** Server and client must ship together (wire protocol change).

| Step | What | Status |
|---|---|---|
| 1 | Server per-team sending: each team gets its own soldiers plus spotted enemies, no enemy paths/ammo/grenades; reveals carry full state | Done, tested |
| 2 | Client: hide unspotted enemies in every mode, 8s last-known markers, step-by-step enemy movement, hidden-shooter tracers, enemy deployment zone tint | Done, tested headless |
| 3 | Local 1v1 check with two clients | Mostly confirmed 2026-11-05. Enemy run-in-place bug found and fixed (needs a recheck); reconnect not tested |

**Decisions (Richard, 2026-11-05):** fading marker ~8s; normal spotting from the start plus the enemy deployment zone tint during the countdown; a hidden shooter/thrower gives a tracer and marker from his cell but stays hidden; same rules in single-player.

**Also fixed:** a reconnecting player was never re-attached to the match (`index.ts` resume path), so after the reconnect snapshot they got no match messages and their orders were refused. This is live in v0.22.9, since the security hardening removed the attach-on-connect.

**Key files:**
- `server/src/fog_filter.ts` - one filter per message type (`FogView`)
- `server/src/match.ts` - `sendPerTeam()`, `sendOrderResult()`, `sendVisibilityUpdate()` (reveals), tick order (spotting before movement goes out)
- `scripts/core/main.gd` - `_fog_visual_for_enemy`, `_note_enemy_fog_transition`, `_mark_hidden_enemy_action`, `_refresh_enemy_deployment_overlay`
- `scripts/effects/last_known_markers.gd`, `scripts/effects/deployment_zone_overlay.gd`
- `scripts/soldiers/soldier.gd` - `chase_remote_step()` / `end_remote_chase()` (enemy steps without a path), `make_ghost_copy()`
- `scripts/network/authoritative_sync.gd` - hidden snapshot entries, `apply_revealed()`, hidden shooter cells, body cells

**Tests:** `server/tests/fog_of_war.test.ts`, `scripts/tests/fog_of_war_tests.tscn`.

**Local 1v1 check (before the PR is merged):** neither side sees the other's soldiers at deployment, but the enemy zone tint shows and clears when deployment ends; an enemy walking into view appears where he really is and moves smoothly (watch for choppy steps - the fallback is to send the next few cells); one walking out leaves a marker that fades in ~8s; a shot from out of sight shows a tracer from his cell and a marker while he stays hidden; reconnect mid-match shows only spotted enemies and orders work.

**Pre-existing test failures (not from this work):** server "lethality is applied to hit chance" still expects the pre-Phase 44 value 0.9; client "Pinned (not panicked) soldier can still throw" in gameplay_foundation_tests; 3 in engagement_firing_presentation_tests (aim hold, fidget, exposed prone) and 4 in ai_commander_tests (MoveCommand, SQUAD scope, ThrowGrenadeCommand, lone defender). The last two suites fail the same way on a clean `develop` (checked 2026-11-05).

**Previous work:** Phase 47 sim parity ([docs/sim-parity-plan.md](docs/sim-parity-plan.md)) was merged to `develop` on 2026-11-05 as PR #11 and has not been released. Its in-game reconnect check is still open. Phases 47 and 48 both change the wire protocol, so shipping them together as one release (0.23.0) needs only one forced client update. Security lockdown and hardening (PRs #8, #9, #10, plus the reconnect-takeover hotfix) shipped in v0.22.9-alpha and are deployed.

## Deployment

Only deploy from `main` (the stable branch):
1. `git push origin main`
2. If server changes: `fly deploy -a chain-revival-ax0q1g --remote-only`
3. If new SQL migration: run it in Supabase SQL Editor
4. Verify with `fly status` / `fly logs` if needed

### Server-Only Changes (no build needed)

For changes to `server/` or `website/` that don't affect the Godot client:
1. Commit and push
2. `fly deploy -a chain-revival-ax0q1g --remote-only`
3. If new SQL migration: run it in Supabase SQL Editor

## Game Updates / Releases

Auto-updater is built in (Phase 27). On every launch the game checks `site_settings.game_version` against `BuildConfig.VERSION`. If a newer version exists, it prompts the user, downloads the zip, and self-updates.

### When to Release

Not every commit is a release. Releases are for milestones players should get:
- **After completing a phase** - the main trigger for a new build
- **Critical bug fixes** - something broken in the live build
- **Never for** - WIP commits, handoff updates, refactors, server-only changes

### CI Release Workflow (tested & working)

1. Bump `BuildConfig.VERSION` in `scripts/core/build_config.gd`
2. Commit and push to `main`
3. Trigger: `gh workflow run build-and-sign.yml --ref main -f version=0.22.0-alpha`
4. CI builds the exe (~2 min), creates and auto-publishes a GitHub Release
5. If `SUPABASE_SERVICE_ROLE_KEY` secret is set: CI auto-updates `game_version` and `download_url` in Supabase
6. If secret is NOT set: manually update in website admin. Download URL format: `https://github.com/dukesgamelab/chain-revival/releases/download/vX.Y.Z-alpha/ChainRevival-X.Y.Z-alpha.zip`

### Local Release (fallback)

1. Bump `BuildConfig.VERSION` in `scripts/core/build_config.gd`
2. Export from Godot (Project -> Export -> Windows Desktop)
3. *(Optional, requires Certum cert)* Sign the exe
4. Zip the build, upload somewhere accessible
5. Set `game_version` and `download_url` in admin site settings

## Code Signing

**Not yet active.** Deferred until the product is more polished. Plan is **Certum Individual Cloud Code Signing** (~$115/yr via SSLmentor). See Phase 34 details in [changelog.md](changelog.md).

## Known Gotchas

- **IPv6:** Fly.io is IPv6-only internally. Supabase connection strings must use IPv4 or the connection pooler.
- **Supabase RPC overloading:** Supabase doesn't support PostgreSQL function overloading well. Use distinct function names.
- **WebSocket race conditions:** Client can send messages before server registers them. Server handles gracefully.
- **Supabase Realtime channels:** Use unique channel names (`Math.random().toString(36).slice(2)` suffix) and `supabase.removeChannel()` for cleanup to avoid "cannot add callbacks after subscribe()" errors.
- **Godot export exclude filter:** `export_presets.cfg` exclude_filter was stripping scenes from builds. Always verify new scenes aren't in the exclude list.
- **Godot export:** Requires export templates matching the Godot version (4.7.2).
- **Godot `.uid` files:** Godot 4.7.2 generates `.uid` resource tracking files. These are gitignored.
- **Reconnect window:** The server holds a dropped player's slot for 90s. The client retries every 3s for 85s. The welcome message decides the outcome: `reconnected: true` resumes the match, anything else ends the loop at once and returns to the lobby, so a reconnect that lands just as the server forfeits is handled cleanly.
