-- Fix PP tracking: migration 022 accidentally dropped prestige_points,
-- total_kills, and rank updates from both record_match_result and
-- record_player_result. This restores them.

-- 1. Fix record_match_result (1v1 matches)
CREATE OR REPLACE FUNCTION public.record_match_result(
  p_match_id       text,
  p_player1_id     uuid,
  p_player1_team   text,
  p_player1_won    boolean,
  p_player1_draw   boolean,
  p_player1_kill   integer,
  p_player1_terrain integer,
  p_player1_total  integer,
  p_player1_kills  integer DEFAULT 0,
  p_player1_pp     integer DEFAULT 0,
  p_player2_id     uuid DEFAULT NULL,
  p_player2_team   text DEFAULT 'GERMANY',
  p_player2_won    boolean DEFAULT false,
  p_player2_draw   boolean DEFAULT false,
  p_player2_kill   integer DEFAULT 0,
  p_player2_terrain integer DEFAULT 0,
  p_player2_total  integer DEFAULT 0,
  p_player2_kills  integer DEFAULT 0,
  p_player2_pp     integer DEFAULT 0,
  p_end_cause      text DEFAULT 'time',
  p_map_id         text DEFAULT NULL,
  p_team_size      integer DEFAULT NULL,
  p_duration_seconds integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_pp1 bigint;
  v_new_pp2 bigint;
  v_new_rank1 integer;
  v_new_rank2 integer;
  thresholds bigint[] := ARRAY[0,500,2500,7500,17500,35500,65500,115500,195500,315500];
BEGIN
  -- Insert match history for both players
  INSERT INTO public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points,
     kills, pp_earned, end_cause, opponent_id, map_id, team_size, duration_seconds)
  VALUES
    (p_match_id, p_player1_id, p_player1_team, p_player1_won, p_player1_draw,
     p_player1_kill, p_player1_terrain, p_player1_total,
     p_player1_kills, p_player1_pp, p_end_cause, p_player2_id,
     p_map_id, p_team_size, p_duration_seconds);

  INSERT INTO public.match_history
    (match_id, player_id, team, won, draw, kill_points, terrain_points, total_points,
     kills, pp_earned, end_cause, opponent_id, map_id, team_size, duration_seconds)
  VALUES
    (p_match_id, p_player2_id, p_player2_team, p_player2_won, p_player2_draw,
     p_player2_kill, p_player2_terrain, p_player2_total,
     p_player2_kills, p_player2_pp, p_end_cause, p_player1_id,
     p_map_id, p_team_size, p_duration_seconds);

  -- Player 1: update stats, PP, and rank
  v_new_pp1 := greatest(0, (SELECT prestige_points FROM public.player_profiles WHERE id = p_player1_id) + p_player1_pp);

  v_new_rank1 := 0;
  FOR i IN 1..array_length(thresholds, 1) LOOP
    IF v_new_pp1 >= thresholds[i] THEN
      v_new_rank1 := i - 1;
    END IF;
  END LOOP;

  UPDATE public.player_profiles SET
    games_played = games_played + 1,
    games_won = CASE WHEN p_player1_won THEN games_won + 1 ELSE games_won END,
    total_kills = total_kills + p_player1_kills,
    prestige_points = v_new_pp1,
    rank = v_new_rank1
  WHERE id = p_player1_id;

  -- Player 2: update stats, PP, and rank
  v_new_pp2 := greatest(0, (SELECT prestige_points FROM public.player_profiles WHERE id = p_player2_id) + p_player2_pp);

  v_new_rank2 := 0;
  FOR i IN 1..array_length(thresholds, 1) LOOP
    IF v_new_pp2 >= thresholds[i] THEN
      v_new_rank2 := i - 1;
    END IF;
  END LOOP;

  UPDATE public.player_profiles SET
    games_played = games_played + 1,
    games_won = CASE WHEN p_player2_won THEN games_won + 1 ELSE games_won END,
    total_kills = total_kills + p_player2_kills,
    prestige_points = v_new_pp2,
    rank = v_new_rank2
  WHERE id = p_player2_id;
END;
$$;

-- 2. Fix record_player_result (team matches)
CREATE OR REPLACE FUNCTION public.record_player_result(
  p_match_id       text,
  p_player_id      uuid,
  p_team           text,
  p_won            boolean,
  p_draw           boolean,
  p_kills          integer,
  p_kill_points    integer,
  p_terrain_points integer,
  p_total_points   integer,
  p_end_cause      text,
  p_opponent_id    uuid DEFAULT NULL,
  p_pp             integer DEFAULT 0,
  p_map_id         text DEFAULT NULL,
  p_team_size      integer DEFAULT NULL,
  p_duration_seconds integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_pp bigint;
  v_new_rank integer;
  thresholds bigint[] := ARRAY[0,500,2500,7500,17500,35500,65500,115500,195500,315500];
BEGIN
  INSERT INTO public.match_history
    (match_id, player_id, team, won, draw, kills, kill_points, terrain_points,
     total_points, end_cause, opponent_id, pp_earned, map_id, team_size, duration_seconds)
  VALUES
    (p_match_id, p_player_id, p_team, p_won, p_draw, p_kills, p_kill_points,
     p_terrain_points, p_total_points, p_end_cause, p_opponent_id, p_pp,
     p_map_id, p_team_size, p_duration_seconds);

  v_new_pp := greatest(0, (SELECT prestige_points FROM public.player_profiles WHERE id = p_player_id) + p_pp);

  v_new_rank := 0;
  FOR i IN 1..array_length(thresholds, 1) LOOP
    IF v_new_pp >= thresholds[i] THEN
      v_new_rank := i - 1;
    END IF;
  END LOOP;

  UPDATE public.player_profiles SET
    games_played = games_played + 1,
    games_won = CASE WHEN p_won THEN games_won + 1 ELSE games_won END,
    total_kills = total_kills + p_kills,
    prestige_points = v_new_pp,
    rank = v_new_rank
  WHERE id = p_player_id;
END;
$$;
