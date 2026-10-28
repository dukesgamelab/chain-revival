-- Add kill count tracking to match_history and player_profiles.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- Add kills column to match_history
alter table public.match_history
  add column if not exists kills integer not null default 0;

-- Add total_kills column to player_profiles
alter table public.player_profiles
  add column if not exists total_kills integer not null default 0;

-- Replace the RPC function to include kills tracking.
create or replace function public.record_match_result(
  p_match_id       text,
  p_player1_id     uuid,
  p_player1_team   text,
  p_player1_won    boolean,
  p_player1_draw   boolean,
  p_player1_kill   integer,
  p_player1_terrain integer,
  p_player1_total  integer,
  p_player1_kills  integer,
  p_player2_id     uuid,
  p_player2_team   text,
  p_player2_won    boolean,
  p_player2_draw   boolean,
  p_player2_kill   integer,
  p_player2_terrain integer,
  p_player2_total  integer,
  p_player2_kills  integer,
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
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points, kills, end_cause, opponent_id)
  values
    (p_match_id, p_player1_id, p_player1_team, p_player1_won, p_player1_draw,
     p_player1_kill, p_player1_terrain, p_player1_total, p_player1_kills, p_end_cause, p_player2_id);

  -- Insert match history for player 2
  insert into public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points, kills, end_cause, opponent_id)
  values
    (p_match_id, p_player2_id, p_player2_team, p_player2_won, p_player2_draw,
     p_player2_kill, p_player2_terrain, p_player2_total, p_player2_kills, p_end_cause, p_player1_id);

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

  -- Increment total_kills
  update public.player_profiles
  set total_kills = total_kills + p_player1_kills
  where id = p_player1_id;

  update public.player_profiles
  set total_kills = total_kills + p_player2_kills
  where id = p_player2_id;
end;
$$;
