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
| 24 | Alpha launch (bug reports, feedback, privacy policy, ToS, server capacity bump) |

## Phase 24 Details (Just Completed)

- Bug report system: `/bugs` page with title, description, category (gameplay/ui/multiplayer/performance/crash/other), severity, steps to reproduce
- Feedback system: `/feedback` page with star rating, category (general/gameplay/balance/ui/maps/feature-request), freeform message
- Privacy Policy page at `/privacy` — data collection, third-party services, cookies, children's privacy, contact
- Terms of Service page at `/terms` — accounts, conduct, moderation, alpha status disclaimer, IP, liability
- Admin dashboard: new Bugs and Feedback tabs for reviewing submissions, status management on bug reports (open/in-progress/closed)
- Admin toggles: `bugreports_enabled` and `feedback_enabled` site settings
- Nav updated with Bug Report and Feedback links (toggle-controlled)
- Footer updated with Privacy Policy and Terms of Service links
- SQL migration `019_alpha_launch.sql`: `bug_reports` and `feedback` tables with RLS policies
- Fly.io VM bumped from 1 to 2 shared CPUs for alpha tester capacity
- Both new tables have Supabase Realtime enabled

### Alpha Launch Checklist

1. Run migration `019_alpha_launch.sql` in Supabase SQL Editor
2. Deploy: `fly deploy -a chain-revival-ax0q1g --remote-only`
3. Verify bug report and feedback forms work
4. Share download link and site URL with alpha testers
5. Monitor bug reports and feedback in the admin dashboard

## Upcoming Phases

| Phase | Name | Scope |
|-------|------|-------|
| 25 | Regiment Management | CO/XO management dashboard on website. Player regiment interactions (apply, leave). Admin regiment oversight. |

### Phase 25: Regiment Management (Detailed Scope)

**CO/XO Management Dashboard** (website page, visible to CO/XO of their regiment):
- View pending join requests and accept/reject them (RPC `accept_regiment_join` exists)
- Kick members (RPC `kick_regiment_member` exists)
- Promote/demote members — assign regiment ranks: 1LT, CPT, MAJ, LT COL, COL (RPC `assign_regiment_rank` exists, requires player PP rank >= 2LT)
- Set/remove XO (RPC `set_regiment_xo` exists, CO-only)
- Edit regiment description and website URL (RPC `update_regiment_details` exists, CO-only)
- Send invites to players (RLS policy `CO and XO can send invites` exists on `regiment_join_requests`)
- Request regiment disbandment (RLS policy `CO can submit disband applications` exists on `regiment_applications`)

**Player Regiment Interactions** (on regiments page or player profile):
- Apply to join a regiment (RLS policy `Users can request to join a regiment` exists on `regiment_join_requests`)
- View status of pending applications
- Accept/reject invites received from regiments (RLS policy `Users can resolve invites sent to them` exists)
- Leave current regiment (RLS policy `Members can leave their regiment` exists on `regiment_members`, also need to clear `regiment_id` on `player_profiles`)
- Apply to create a new regiment (RLS policy `Users can submit create applications` exists on `regiment_applications`)

**Admin Regiment Oversight** (in admin dashboard):
- View and approve/reject regiment creation applications (RPCs `approve_regiment_application` and `reject_regiment_application` exist)
- View and approve/reject regiment disbandment requests
- View all regiment join requests across all regiments
- Override: kick members, transfer CO, force-disband

**Backend Status:** All Supabase RPC functions and RLS policies already exist in migration `009_regiments.sql`. This phase is purely website UI work — no new migrations needed unless admin override functions are added.

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
