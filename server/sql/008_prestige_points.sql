-- Phase 13: Prestige Points & Ranks
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- Add prestige_points and rank columns to player_profiles
alter table public.player_profiles
  add column if not exists prestige_points integer not null default 0;

alter table public.player_profiles
  add column if not exists rank integer not null default 0;

-- Add pp_earned column to match_history
alter table public.match_history
  add column if not exists pp_earned integer not null default 0;

-- Replace the RPC function to include PP tracking.
-- PP is calculated server-side and passed in; the RPC atomically:
--   1. Inserts match_history rows (now with pp_earned)
--   2. Increments games_played, games_won, total_kills
--   3. Adds PP to prestige_points and recalculates rank
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
  p_player1_pp     integer,
  p_player2_id     uuid,
  p_player2_team   text,
  p_player2_won    boolean,
  p_player2_draw   boolean,
  p_player2_kill   integer,
  p_player2_terrain integer,
  p_player2_total  integer,
  p_player2_kills  integer,
  p_player2_pp     integer,
  p_end_cause      text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new_pp1 integer;
  v_new_pp2 integer;
begin
  -- Insert match history for player 1
  insert into public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points, kills, pp_earned, end_cause, opponent_id)
  values
    (p_match_id, p_player1_id, p_player1_team, p_player1_won, p_player1_draw,
     p_player1_kill, p_player1_terrain, p_player1_total, p_player1_kills, p_player1_pp, p_end_cause, p_player2_id);

  -- Insert match history for player 2
  insert into public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points, kills, pp_earned, end_cause, opponent_id)
  values
    (p_match_id, p_player2_id, p_player2_team, p_player2_won, p_player2_draw,
     p_player2_kill, p_player2_terrain, p_player2_total, p_player2_kills, p_player2_pp, p_end_cause, p_player1_id);

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

  -- Add PP and recalculate rank for player 1
  -- PP floor is 0 (never goes negative)
  update public.player_profiles
  set prestige_points = greatest(0, prestige_points + p_player1_pp)
  where id = p_player1_id;

  select prestige_points into v_new_pp1
  from public.player_profiles
  where id = p_player1_id;

  update public.player_profiles
  set rank = case
    when v_new_pp1 >= 315500 then 9  -- CPT
    when v_new_pp1 >= 195500 then 8  -- 1LT
    when v_new_pp1 >= 115500 then 7  -- 2LT
    when v_new_pp1 >= 65500  then 6  -- MSG
    when v_new_pp1 >= 35500  then 5  -- SFC
    when v_new_pp1 >= 17500  then 4  -- SSG
    when v_new_pp1 >= 7500   then 3  -- SGT
    when v_new_pp1 >= 2500   then 2  -- CPL
    when v_new_pp1 >= 500    then 1  -- PFC
    else 0                           -- PVT
  end
  where id = p_player1_id;

  -- Add PP and recalculate rank for player 2
  update public.player_profiles
  set prestige_points = greatest(0, prestige_points + p_player2_pp)
  where id = p_player2_id;

  select prestige_points into v_new_pp2
  from public.player_profiles
  where id = p_player2_id;

  update public.player_profiles
  set rank = case
    when v_new_pp2 >= 315500 then 9  -- CPT
    when v_new_pp2 >= 195500 then 8  -- 1LT
    when v_new_pp2 >= 115500 then 7  -- 2LT
    when v_new_pp2 >= 65500  then 6  -- MSG
    when v_new_pp2 >= 35500  then 5  -- SFC
    when v_new_pp2 >= 17500  then 4  -- SSG
    when v_new_pp2 >= 7500   then 3  -- SGT
    when v_new_pp2 >= 2500   then 2  -- CPL
    when v_new_pp2 >= 500    then 1  -- PFC
    else 0                           -- PVT
  end
  where id = p_player2_id;
end;
$$;
