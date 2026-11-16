-- Lobby presence and room rosters.
-- Run this in the Supabase SQL Editor. It does not run automatically.
--
-- lobby_presence: one row per account currently in the lobby browser.
-- lobby_members: one row per account in a game room. Side is written by the
-- game server when it assigns USA or Germany. Waiting rooms leave side null.

CREATE TABLE IF NOT EXISTS public.lobby_presence (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL DEFAULT '',
  last_seen timestamptz NOT NULL DEFAULT now(),
  connected boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.lobby_members (
  lobby_id uuid NOT NULL REFERENCES public.lobbies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL DEFAULT '',
  side text CHECK (side IS NULL OR side IN ('USA', 'GERMANY')),
  connected boolean NOT NULL DEFAULT true,
  PRIMARY KEY (lobby_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_lobby_members_lobby
  ON public.lobby_members (lobby_id);

ALTER TABLE public.lobby_presence REPLICA IDENTITY FULL;
ALTER TABLE public.lobby_members REPLICA IDENTITY FULL;

ALTER TABLE public.lobby_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lobby_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lobby presence is viewable by authenticated users" ON public.lobby_presence;
CREATE POLICY "Lobby presence is viewable by authenticated users"
  ON public.lobby_presence FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Lobby members are viewable by authenticated users" ON public.lobby_members;
CREATE POLICY "Lobby members are viewable by authenticated users"
  ON public.lobby_members FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.sweep_lobby_sessions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.lobby_presence
  SET connected = false
  WHERE connected = true
    AND last_seen < now() - interval '30 seconds';

  DELETE FROM public.lobby_presence
  WHERE (connected = false AND last_seen < now() - interval '20 seconds')
     OR last_seen < now() - interval '90 seconds';

  DELETE FROM public.lobby_members AS member
  USING public.lobbies AS lobby
  WHERE member.lobby_id = lobby.id
    AND lobby.status = 'waiting'
    AND member.user_id <> lobby.host_id
    AND NOT EXISTS (
      SELECT 1 FROM public.lobby_presence AS presence
      WHERE presence.user_id = member.user_id
        AND presence.connected = true
        AND presence.last_seen > now() - interval '30 seconds'
    );

  DELETE FROM public.lobbies AS lobby
  WHERE lobby.status = 'waiting'
    AND lobby.updated_at < now() - interval '90 seconds'
    AND NOT EXISTS (
      SELECT 1 FROM public.lobby_presence AS presence
      WHERE presence.user_id = lobby.host_id
        AND presence.last_seen > now() - interval '90 seconds'
    );

  UPDATE public.lobbies AS lobby
  SET current_players = counts.member_count,
      updated_at = now()
  FROM (
    SELECT lobby_id, count(*)::integer AS member_count
    FROM public.lobby_members
    GROUP BY lobby_id
  ) AS counts
  WHERE lobby.id = counts.lobby_id
    AND lobby.status = 'waiting'
    AND lobby.current_players IS DISTINCT FROM counts.member_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_lobby_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  PERFORM public.sweep_lobby_sessions();

  SELECT COALESCE(NULLIF(display_name, ''), 'Player')
    INTO v_name
  FROM public.player_profiles
  WHERE id = auth.uid();

  IF v_name IS NULL THEN
    v_name := 'Player';
  END IF;

  INSERT INTO public.lobby_presence (user_id, display_name, last_seen, connected)
  VALUES (auth.uid(), v_name, now(), true)
  ON CONFLICT (user_id) DO UPDATE
  SET display_name = EXCLUDED.display_name,
      last_seen = now(),
      connected = true;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_lobby_presence()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  UPDATE public.lobby_presence
  SET connected = false,
      last_seen = now()
  WHERE user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.add_lobby_host_member()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name text;
BEGIN
  SELECT COALESCE(NULLIF(display_name, ''), NULLIF(NEW.host_display_name, ''), 'Player')
    INTO v_name
  FROM public.player_profiles
  WHERE id = NEW.host_id;

  IF v_name IS NULL THEN
    v_name := COALESCE(NULLIF(NEW.host_display_name, ''), 'Player');
  END IF;

  INSERT INTO public.lobby_members (lobby_id, user_id, display_name, side, connected)
  VALUES (NEW.id, NEW.host_id, v_name, NULL, true)
  ON CONFLICT (lobby_id, user_id) DO UPDATE
  SET display_name = EXCLUDED.display_name,
      connected = true;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS add_lobby_host_member ON public.lobbies;
CREATE TRIGGER add_lobby_host_member
  AFTER INSERT ON public.lobbies
  FOR EACH ROW
  EXECUTE FUNCTION public.add_lobby_host_member();

CREATE OR REPLACE FUNCTION public.clear_lobby_members_when_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.status = 'finished' AND OLD.status IS DISTINCT FROM 'finished' THEN
    DELETE FROM public.lobby_members WHERE lobby_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS clear_lobby_members_when_finished ON public.lobbies;
CREATE TRIGGER clear_lobby_members_when_finished
  AFTER UPDATE OF status ON public.lobbies
  FOR EACH ROW
  EXECUTE FUNCTION public.clear_lobby_members_when_finished();

CREATE OR REPLACE FUNCTION public.join_lobby(p_lobby_id uuid)
RETURNS SETOF public.lobbies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  lobby_row public.lobbies;
  v_name text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = auth.uid() AND is_banned = true
  ) THEN
    RAISE EXCEPTION 'Banned players cannot join lobbies';
  END IF;

  SELECT * INTO lobby_row
  FROM public.lobbies
  WHERE id = p_lobby_id AND status = 'waiting'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lobby not found or not waiting';
  END IF;

  SELECT COALESCE(NULLIF(display_name, ''), 'Player')
    INTO v_name
  FROM public.player_profiles
  WHERE id = auth.uid();

  IF v_name IS NULL THEN
    v_name := 'Player';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lobby_members
    WHERE lobby_id = p_lobby_id AND user_id = auth.uid()
  ) THEN
    UPDATE public.lobby_members
    SET display_name = v_name,
        connected = true
    WHERE lobby_id = p_lobby_id AND user_id = auth.uid();
    RETURN NEXT lobby_row;
    RETURN;
  END IF;

  IF lobby_row.current_players >= lobby_row.max_players THEN
    RAISE EXCEPTION 'Lobby is full';
  END IF;

  INSERT INTO public.lobby_members (lobby_id, user_id, display_name, side, connected)
  VALUES (p_lobby_id, auth.uid(), v_name, NULL, true);

  UPDATE public.lobbies SET
    current_players = current_players + 1,
    status = CASE
      WHEN current_players + 1 >= max_players THEN 'in_progress'
      ELSE 'waiting'
    END,
    updated_at = now()
  WHERE id = p_lobby_id
  RETURNING * INTO lobby_row;

  RETURN NEXT lobby_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_lobby(p_lobby_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  lobby_row public.lobbies;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO lobby_row
  FROM public.lobbies
  WHERE id = p_lobby_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF lobby_row.host_id = auth.uid() THEN
    IF lobby_row.status = 'waiting' THEN
      DELETE FROM public.lobbies WHERE id = p_lobby_id;
    END IF;
    RETURN;
  END IF;

  IF lobby_row.status <> 'waiting' THEN
    RETURN;
  END IF;

  DELETE FROM public.lobby_members
  WHERE lobby_id = p_lobby_id AND user_id = auth.uid();

  IF FOUND THEN
    UPDATE public.lobbies
    SET current_players = GREATEST(1, current_players - 1),
        updated_at = now()
    WHERE id = p_lobby_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sweep_lobby_sessions() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_lobby_presence() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.leave_lobby_presence() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.join_lobby(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.leave_lobby(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.touch_lobby_presence() TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_lobby_presence() TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_lobby(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_lobby(uuid) TO authenticated;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.lobby_presence;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.lobby_members;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
