-- Match history table for Chain Revival.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- Stores one row per player per match (two rows per match).
create table if not exists public.match_history (
  id             bigint generated always as identity primary key,
  match_id       text not null,
  player_id      uuid not null references auth.users(id) on delete cascade,
  team           text not null,            -- 'USA' or 'GERMANY'
  won            boolean not null,
  draw           boolean not null default false,
  kill_points    integer not null default 0,
  terrain_points integer not null default 0,
  total_points   integer not null default 0,
  end_cause      text not null,            -- 'extermination' or 'time'
  opponent_id    uuid references auth.users(id) on delete set null,
  played_at      timestamptz not null default now()
);

-- Enable Row Level Security
alter table public.match_history enable row level security;

-- Anyone can read match history (for profiles, leaderboards, etc.)
create policy "Match history is viewable by everyone"
  on public.match_history
  for select
  using (true);

-- Only the service role can insert (server-side only).
-- No insert policy for authenticated users; the server uses the
-- service role key which bypasses RLS.

-- Indexes for common queries
create index if not exists idx_match_history_player
  on public.match_history (player_id, played_at desc);

create index if not exists idx_match_history_match
  on public.match_history (match_id);

-- RPC function: record a match result atomically.
-- Inserts match_history rows for both players and increments
-- games_played/games_won on player_profiles in a single transaction.
-- Called by the server via service role (bypasses RLS).
create or replace function public.record_match_result(
  p_match_id       text,
  p_player1_id     uuid,
  p_player1_team   text,
  p_player1_won    boolean,
  p_player1_draw   boolean,
  p_player1_kill   integer,
  p_player1_terrain integer,
  p_player1_total  integer,
  p_player2_id     uuid,
  p_player2_team   text,
  p_player2_won    boolean,
  p_player2_draw   boolean,
  p_player2_kill   integer,
  p_player2_terrain integer,
  p_player2_total  integer,
  p_end_cause      text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Insert match history for player 1
  insert into public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points, end_cause, opponent_id)
  values
    (p_match_id, p_player1_id, p_player1_team, p_player1_won, p_player1_draw,
     p_player1_kill, p_player1_terrain, p_player1_total, p_end_cause, p_player2_id);

  -- Insert match history for player 2
  insert into public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points, end_cause, opponent_id)
  values
    (p_match_id, p_player2_id, p_player2_team, p_player2_won, p_player2_draw,
     p_player2_kill, p_player2_terrain, p_player2_total, p_end_cause, p_player1_id);

  -- Increment games_played for both players
  update public.player_profiles
  set games_played = games_played + 1
  where id in (p_player1_id, p_player2_id);

  -- Increment games_won for winners (skip on draw)
  if p_player1_won then
    update public.player_profiles
    set games_won = games_won + 1
    where id = p_player1_id;
  end if;

  if p_player2_won then
    update public.player_profiles
    set games_won = games_won + 1
    where id = p_player2_id;
  end if;
end;
$$;
