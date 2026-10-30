-- Phase 19: Team Size & Map Selection
-- Adds team_size to lobbies and an atomic join RPC.

-- 1. Add team_size column to lobbies
alter table public.lobbies
  add column if not exists team_size integer not null default 1;

-- 2. Atomic lobby join RPC: increments current_players, sets in_progress when full.
--    Returns the updated lobby row so the client can check the new status.
create or replace function join_lobby(p_lobby_id uuid)
returns setof lobbies
language plpgsql security definer as $$
declare
  lobby_row lobbies;
begin
  select * into lobby_row
    from lobbies
   where id = p_lobby_id and status = 'waiting'
   for update;

  if not found then
    raise exception 'Lobby not found or not waiting';
  end if;

  if lobby_row.current_players >= lobby_row.max_players then
    raise exception 'Lobby is full';
  end if;

  update lobbies set
    current_players = current_players + 1,
    status = case
      when current_players + 1 >= max_players then 'in_progress'
      else 'waiting'
    end,
    updated_at = now()
  where id = p_lobby_id
  returning * into lobby_row;

  return next lobby_row;
end;
$$;

-- 3. Individual player result recording for team games.
--    Inserts one match_history row and updates one player_profiles row.
create or replace function record_player_result(
  p_match_id text,
  p_player_id uuid,
  p_team text,
  p_won boolean,
  p_draw boolean,
  p_kills integer,
  p_kill_points integer,
  p_terrain_points integer,
  p_total_points integer,
  p_end_cause text,
  p_opponent_id uuid,
  p_pp integer
) returns void
language plpgsql security definer as $$
declare
  new_pp bigint;
  new_rank integer;
  thresholds bigint[] := ARRAY[0,500,2500,7500,17500,35500,65500,115500,195500,315500];
begin
  insert into match_history
    (match_id, player_id, team, won, draw, kills, kill_points,
     terrain_points, total_points, end_cause, opponent_id, pp_earned)
  values
    (p_match_id, p_player_id, p_team, p_won, p_draw, p_kills, p_kill_points,
     p_terrain_points, p_total_points, p_end_cause, p_opponent_id, p_pp);

  new_pp := (select prestige_points from player_profiles where id = p_player_id) + p_pp;

  new_rank := 0;
  for i in 1..array_length(thresholds, 1) loop
    if new_pp >= thresholds[i] then
      new_rank := i - 1;
    end if;
  end loop;

  update player_profiles set
    games_played = games_played + 1,
    games_won = case when p_won then games_won + 1 else games_won end,
    total_kills = total_kills + p_kills,
    prestige_points = new_pp,
    rank = new_rank
  where id = p_player_id;
end;
$$;
