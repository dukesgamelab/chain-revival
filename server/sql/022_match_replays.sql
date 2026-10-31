-- Phase 35: Match replays — event recording and metadata.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- 1. Add metadata columns to match_history so each row has context
ALTER TABLE public.match_history ADD COLUMN IF NOT EXISTS map_id text;
ALTER TABLE public.match_history ADD COLUMN IF NOT EXISTS team_size integer;
ALTER TABLE public.match_history ADD COLUMN IF NOT EXISTS duration_seconds integer;

-- 2. Create match_replays table — one row per match with full event log
CREATE TABLE IF NOT EXISTS public.match_replays (
  match_id        text PRIMARY KEY,
  map_id          text NOT NULL,
  map_width       integer NOT NULL,
  map_height      integer NOT NULL,
  team_size       integer NOT NULL DEFAULT 1,
  initial_state   jsonb NOT NULL,
  events          jsonb NOT NULL DEFAULT '[]'::jsonb,
  duration_ms     integer NOT NULL DEFAULT 0,
  event_count     integer NOT NULL DEFAULT 0,
  recorded_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.match_replays ENABLE ROW LEVEL SECURITY;

-- Anyone can read replays (for the website match detail page)
CREATE POLICY "Replays are viewable by everyone"
  ON public.match_replays
  FOR SELECT
  USING (true);

CREATE INDEX IF NOT EXISTS idx_match_replays_recorded
  ON public.match_replays (recorded_at DESC);

-- 3. Update the 1v1 record_match_result RPC to accept metadata
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
BEGIN
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

  UPDATE public.player_profiles
  SET games_played = games_played + 1
  WHERE id IN (p_player1_id, p_player2_id);

  IF p_player1_won THEN
    UPDATE public.player_profiles SET games_won = games_won + 1 WHERE id = p_player1_id;
  END IF;
  IF p_player2_won THEN
    UPDATE public.player_profiles SET games_won = games_won + 1 WHERE id = p_player2_id;
  END IF;
END;
$$;

-- 4. Update record_player_result (team games) to accept metadata
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
BEGIN
  INSERT INTO public.match_history
    (match_id, player_id, team, won, draw, kills, kill_points, terrain_points,
     total_points, end_cause, opponent_id, pp_earned, map_id, team_size, duration_seconds)
  VALUES
    (p_match_id, p_player_id, p_team, p_won, p_draw, p_kills, p_kill_points,
     p_terrain_points, p_total_points, p_end_cause, p_opponent_id, p_pp,
     p_map_id, p_team_size, p_duration_seconds);

  UPDATE public.player_profiles
  SET games_played = games_played + 1
  WHERE id = p_player_id;

  IF p_won THEN
    UPDATE public.player_profiles SET games_won = games_won + 1 WHERE id = p_player_id;
  END IF;
END;
$$;
