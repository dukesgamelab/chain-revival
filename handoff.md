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
    sql/            Numbered migrations (001-031)
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

## Current Work - Combat Realism (branch: combat-realism)

**No SQL migrations needed.**

**Features complete:**
- Friendly grenade damage/stun - grenades affect same-team soldiers (client + server)
- Throw preview line turns yellow when friendlies are in blast radius
- Lethality multiplier tuned from 0.9 to 0.6 for balanced no-wound-state play
- Crawl animation regression fix - CRAWL forces prone stance
- Mid-move mode switch now updates speed immediately
- Post-stun movement mode resets to RUN
- Repeated-click move bug fix - early return when already heading to target
- Move redirect snap-back fix - smooth visual blending instead of snapping back to grid position

**Key files changed:**
- `scripts/combat/combat_system.gd` - Friendly grenade damage in blast resolution
- `scripts/core/action_resolver.gd` - Move fixes (same-target, redirect halt removal, crawl, mid-move speed)
- `scripts/core/main.gd` - Grenade preview wiring (friendly warning)
- `scripts/effects/los_visualizer.gd` - Yellow warning line for friendly fire
- `scripts/soldiers/soldier_state.gd` - Post-stun RUN reset
- `scripts/tests/gameplay_foundation_tests.gd` - Updated lethality test assertions
- `assets/data/gameplay_policies.json` - Lethality 0.9 -> 0.6
- `server/src/action_resolver.ts` - Server-side move fixes (same-target, redirect halt removal)
- `server/src/grenade_system.ts` - Server-side friendly grenade damage, post-stun RUN reset
- `server/src/hit_resolution.ts` - Server-side lethality 0.9 -> 0.6

**Status:** All changes committed on `combat-realism` branch. When ready to merge, PR should target `develop`.

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
- **Reconnect window:** The 90s server timer and 120s client retry window are intentionally offset - the client gives up 30s after the server would forfeit anyway, avoiding a race where the client reconnects just as the server forfeits.
