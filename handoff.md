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
    sql/            Numbered migrations (001-017)
  website/          React + Vite + Tailwind SPA
    src/pages/      Home, Login, Leaderboard, Player, Regiments, Download, Appeal, Admin
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

10 ranks: PVT(0), PFC(1), CPL(2), SGT(3), SSG(4), SFC(5), MSG(6), 2LT(7), 1LT(8), CPT(9).
PP thresholds: `[0, 500, 2500, 7500, 17500, 35500, 65500, 115500, 195500, 315500]`.

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

## Completed Phases (1-23)

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

## Phase 23 Details (Just Completed)

- Godot Windows x86_64 export preset configured, outputs to `builds/ChainRevival-0.1.0-alpha.zip`
- Download page with version badge, system requirements, 4-step install guide, SmartScreen warning
- Download button activates when admin sets `download_url` in the admin dashboard
- Admin dashboard: Game Distribution section with `game_version` and `download_url` fields
- Server serves game builds from `/builds` directory with `Content-Disposition: attachment` headers
- Dockerfile copies `builds/` into the container (wildcard pattern so build doesn't fail if empty)
- SQL migration `018_download_settings.sql` seeds `game_version` and `download_url` in `site_settings`
- Ban notification Edge Function deployed to Supabase with Resend integration
- Server admin/moderator verification now done server-side via Supabase (was client-trusted)
- Auth consolidated into single AuthProvider context (was duplicated across components)
- 404 catch-all route added

### Build & Deploy Workflow

1. Export from Godot: Project > Export > "Chain Revival 0.1.0-alpha" > Export Project
2. Build lands in `builds/ChainRevival-0.1.0-alpha.zip` (gitignored, picked up by Dockerfile)
3. Deploy: `fly deploy -a chain-revival-ax0q1g --remote-only`
4. Set version and download URL in admin dashboard

## Upcoming Phases

| Phase | Name | Scope |
|-------|------|-------|
| 24 | Alpha Launch | Bug reporting channel. Minimal privacy policy/ToS. Server capacity check. Invite testers, collect feedback. |

## Code Signing (Not Yet Done)

The Windows build is not code-signed, so Chrome flags the download as suspicious and Windows SmartScreen warns on first run. Users can click through both warnings to install.

To eliminate the warnings:
1. Buy an OV code signing certificate (~$150-220/year) from a reseller like CodeSigningStore or CheapSSLSecurity (can be issued to individuals with a photo ID)
2. Install the Windows SDK (for `signtool.exe`)
3. In Godot: Editor > Editor Settings > Export > Windows — set Sign Tool path to `signtool.exe`
4. In the export preset: Options > Code Signing — enable and set the certificate
5. Godot signs automatically on export

OV is sufficient. EV ($400-600/yr) gets instant SmartScreen trust; with OV, warnings disappear after enough users download without issues.

## Game Update Options

Currently players re-download the full build manually. Future options:

1. **Custom launcher/updater** — a small exe that checks your server for new versions and downloads them automatically
2. **Steam / itch.io** — handles updates automatically, but adds platform dependency

## Known Gotchas

- **IPv6:** Fly.io is IPv6-only internally. Supabase connection strings must use IPv4 or the connection pooler.
- **Supabase RPC overloading:** Supabase doesn't support PostgreSQL function overloading well. Use distinct function names.
- **WebSocket race conditions:** Client can send messages before server registers them. Server handles gracefully.
- **Supabase Realtime channels:** Use unique channel names (`Math.random().toString(36).slice(2)` suffix) and `supabase.removeChannel()` for cleanup to avoid "cannot add callbacks after subscribe()" errors.
- **Godot export:** Requires export templates matching the Godot version (4.7).
