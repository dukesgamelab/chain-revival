-- 032: Security lockdown
-- Run in Supabase SQL Editor (Dashboard > SQL Editor > New Query).
-- Paste the whole file and run it as one statement.
--
-- What this does:
--   - Restricts player_profiles UPDATE to display_name only
--   - Revokes EXECUTE on all public RPCs, re-grants only client-callable ones
--   - Rewrites RPCs to use auth.uid() instead of caller-supplied IDs
--   - Adds SET search_path on all SECURITY DEFINER functions
--   - Closes the open lobby UPDATE policy
--   - Adds WITH CHECK to regiment join request update policies
--   - Fixes delete_custom_channel NULL-check bypass
--   - Adds auth/ban check to join_lobby
--   - Drops stale function overloads

BEGIN;

-- ============================================================
-- 1. Drop stale function overloads
-- ============================================================
-- record_match_result: 006 (16 params), 007 (18 params), 008 (20 params)
DROP FUNCTION IF EXISTS public.record_match_result(text, uuid, text, boolean, boolean, integer, integer, integer, uuid, text, boolean, boolean, integer, integer, integer, text);
DROP FUNCTION IF EXISTS public.record_match_result(text, uuid, text, boolean, boolean, integer, integer, integer, integer, uuid, text, boolean, boolean, integer, integer, integer, integer, text);
DROP FUNCTION IF EXISTS public.record_match_result(text, uuid, text, boolean, boolean, integer, integer, integer, integer, integer, uuid, text, boolean, boolean, integer, integer, integer, integer, integer, text);
-- record_player_result: 015 (12 params)
DROP FUNCTION IF EXISTS public.record_player_result(text, uuid, text, boolean, boolean, integer, integer, integer, integer, text, uuid, integer);

-- ============================================================
-- 2. Column-level grants
-- ============================================================
-- player_profiles: authenticated can only update display_name (not is_admin, is_banned, PP, rank, etc.)
REVOKE UPDATE ON public.player_profiles FROM authenticated;
GRANT UPDATE (display_name) ON public.player_profiles TO authenticated;

-- regiment_join_requests: only status/resolved_by/resolved_at (prevents rewriting player_id)
REVOKE UPDATE ON public.regiment_join_requests FROM authenticated;
GRANT UPDATE (status, resolved_by, resolved_at) ON public.regiment_join_requests TO authenticated;

-- ============================================================
-- 3. Close the open lobby UPDATE policy
-- ============================================================
-- This policy let any authenticated user update ANY column on ANY waiting lobby,
-- including server_url (lobby hijack). Joining is handled by the join_lobby RPC.
DROP POLICY IF EXISTS "Authenticated users can join waiting lobbies" ON public.lobbies;

-- ============================================================
-- 4. Add WITH CHECK to regiment_join_request update policies
-- ============================================================
DROP POLICY IF EXISTS "CO and XO can resolve join requests" ON public.regiment_join_requests;
CREATE POLICY "CO and XO can resolve join requests"
  ON public.regiment_join_requests FOR UPDATE TO authenticated
  USING (
    direction = 'request'
    AND EXISTS (
      SELECT 1 FROM public.regiments
      WHERE id = regiment_id AND (co_id = auth.uid() OR xo_id = auth.uid())
    )
  )
  WITH CHECK (
    direction = 'request'
    AND EXISTS (
      SELECT 1 FROM public.regiments
      WHERE id = regiment_id AND (co_id = auth.uid() OR xo_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can resolve invites sent to them" ON public.regiment_join_requests;
CREATE POLICY "Users can resolve invites sent to them"
  ON public.regiment_join_requests FOR UPDATE TO authenticated
  USING (direction = 'invite' AND player_id = auth.uid())
  WITH CHECK (direction = 'invite' AND player_id = auth.uid());

DROP POLICY IF EXISTS "Users can cancel their own pending requests" ON public.regiment_join_requests;
CREATE POLICY "Users can cancel their own pending requests"
  ON public.regiment_join_requests FOR UPDATE TO authenticated
  USING (player_id = auth.uid() AND direction = 'request' AND status = 'pending')
  WITH CHECK (player_id = auth.uid() AND direction = 'request');

-- ============================================================
-- 5. Rewrite regiment RPCs: use auth.uid() instead of caller params
--    Signatures kept identical for backward compatibility.
-- ============================================================

CREATE OR REPLACE FUNCTION public.approve_regiment_application(
  p_application_id uuid,
  p_admin_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_app record;
  v_regiment_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_app
  FROM public.regiment_applications
  WHERE id = p_application_id AND status = 'pending';

  IF v_app IS NULL THEN
    RAISE EXCEPTION 'Application not found or already resolved';
  END IF;

  IF v_app.type = 'create' THEN
    INSERT INTO public.regiments (name, tag, description, co_id, status, approved_at)
    VALUES (v_app.regiment_name, v_app.regiment_tag, v_app.description, v_app.applicant_id, 'active', now())
    RETURNING id INTO v_regiment_id;

    INSERT INTO public.regiment_members (regiment_id, player_id, assigned_rank)
    VALUES (v_regiment_id, v_app.applicant_id, 'COL');

    UPDATE public.player_profiles
    SET regiment_id = v_regiment_id
    WHERE id = v_app.applicant_id;
  ELSIF v_app.type = 'disband' THEN
    UPDATE public.regiments
    SET status = 'disbanded', disbanded_at = now()
    WHERE id = v_app.regiment_id;

    UPDATE public.player_profiles
    SET regiment_id = null
    WHERE regiment_id = v_app.regiment_id;

    DELETE FROM public.regiment_members
    WHERE regiment_id = v_app.regiment_id;

    v_regiment_id := v_app.regiment_id;
  END IF;

  UPDATE public.regiment_applications
  SET status = 'approved', reviewed_by = v_caller_id, reviewed_at = now()
  WHERE id = p_application_id;

  RETURN v_regiment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_regiment_application(
  p_application_id uuid,
  p_admin_id uuid,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.regiment_applications
  SET status = 'rejected',
      reviewed_by = v_caller_id,
      reviewed_at = now(),
      review_note = p_note
  WHERE id = p_application_id AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application not found or already resolved';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_regiment_join(
  p_request_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_req record;
  v_member_count integer;
  v_max integer;
BEGIN
  SELECT * INTO v_req
  FROM public.regiment_join_requests
  WHERE id = p_request_id AND status = 'pending';

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Request not found or already resolved';
  END IF;

  IF v_req.direction = 'request' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.regiments
      WHERE id = v_req.regiment_id
        AND (co_id = v_caller_id OR xo_id = v_caller_id)
    ) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  ELSIF v_req.direction = 'invite' THEN
    IF v_req.player_id != v_caller_id THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = v_req.player_id AND regiment_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Player is already in a regiment';
  END IF;

  SELECT count(*) INTO v_member_count
  FROM public.regiment_members
  WHERE regiment_id = v_req.regiment_id;

  SELECT max_members INTO v_max
  FROM public.regiments
  WHERE id = v_req.regiment_id;

  IF v_member_count >= v_max THEN
    RAISE EXCEPTION 'Regiment is full';
  END IF;

  INSERT INTO public.regiment_members (regiment_id, player_id)
  VALUES (v_req.regiment_id, v_req.player_id);

  UPDATE public.player_profiles
  SET regiment_id = v_req.regiment_id
  WHERE id = v_req.player_id;

  UPDATE public.regiment_join_requests
  SET status = 'accepted', resolved_by = v_caller_id, resolved_at = now()
  WHERE id = p_request_id;

  UPDATE public.regiment_join_requests
  SET status = 'cancelled', resolved_at = now()
  WHERE player_id = v_req.player_id
    AND id != p_request_id
    AND status = 'pending';
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_regiment_join(
  p_request_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_req record;
BEGIN
  SELECT * INTO v_req
  FROM public.regiment_join_requests
  WHERE id = p_request_id AND status = 'pending';

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Request not found or already resolved';
  END IF;

  IF v_req.direction = 'request' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.regiments
      WHERE id = v_req.regiment_id
        AND (co_id = v_caller_id OR xo_id = v_caller_id)
    ) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  ELSIF v_req.direction = 'invite' THEN
    IF v_req.player_id != v_caller_id THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  END IF;

  UPDATE public.regiment_join_requests
  SET status = 'rejected', resolved_by = v_caller_id, resolved_at = now()
  WHERE id = p_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.kick_regiment_member(
  p_regiment_id uuid,
  p_target_id uuid,
  p_caller_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_reg record;
BEGIN
  SELECT * INTO v_reg
  FROM public.regiments
  WHERE id = p_regiment_id AND status = 'active';

  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Regiment not found';
  END IF;

  IF v_reg.co_id != v_caller_id AND v_reg.xo_id != v_caller_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_target_id = v_reg.co_id THEN
    RAISE EXCEPTION 'Cannot kick the commanding officer';
  END IF;

  IF v_caller_id = v_reg.xo_id AND p_target_id = v_reg.xo_id THEN
    RAISE EXCEPTION 'Cannot kick yourself; leave instead';
  END IF;

  DELETE FROM public.regiment_members
  WHERE regiment_id = p_regiment_id AND player_id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player is not a member of this regiment';
  END IF;

  UPDATE public.player_profiles
  SET regiment_id = null
  WHERE id = p_target_id;

  IF p_target_id = v_reg.xo_id THEN
    UPDATE public.regiments
    SET xo_id = null
    WHERE id = p_regiment_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_regiment_rank(
  p_regiment_id uuid,
  p_target_id uuid,
  p_caller_id uuid,
  p_rank text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_reg record;
  v_target_pp_rank integer;
BEGIN
  SELECT * INTO v_reg
  FROM public.regiments
  WHERE id = p_regiment_id AND status = 'active';

  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Regiment not found';
  END IF;

  IF v_reg.co_id != v_caller_id AND v_reg.xo_id != v_caller_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF p_rank IS NOT NULL AND p_rank NOT IN ('1LT', 'CPT', 'MAJ', 'LT COL', 'COL') THEN
    RAISE EXCEPTION 'Invalid assigned rank';
  END IF;

  SELECT rank INTO v_target_pp_rank
  FROM public.player_profiles
  WHERE id = p_target_id;

  IF v_target_pp_rank < 7 THEN
    RAISE EXCEPTION 'Player must be 2LT or higher to receive an assigned rank';
  END IF;

  UPDATE public.regiment_members
  SET assigned_rank = p_rank
  WHERE regiment_id = p_regiment_id AND player_id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player is not a member of this regiment';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_regiment_xo(
  p_regiment_id uuid,
  p_caller_id uuid,
  p_xo_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_reg record;
BEGIN
  SELECT * INTO v_reg
  FROM public.regiments
  WHERE id = p_regiment_id AND status = 'active';

  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Regiment not found';
  END IF;

  IF v_reg.co_id != v_caller_id THEN
    RAISE EXCEPTION 'Only the CO can assign the XO';
  END IF;

  IF p_xo_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.regiment_members
      WHERE regiment_id = p_regiment_id AND player_id = p_xo_id
    ) THEN
      RAISE EXCEPTION 'Target is not a member of this regiment';
    END IF;
  END IF;

  UPDATE public.regiments
  SET xo_id = p_xo_id
  WHERE id = p_regiment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_regiment_details(
  p_regiment_id uuid,
  p_caller_id uuid,
  p_description text DEFAULT NULL,
  p_website_url text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_reg record;
BEGIN
  SELECT * INTO v_reg
  FROM public.regiments
  WHERE id = p_regiment_id AND status = 'active';

  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Regiment not found';
  END IF;

  IF v_reg.co_id != v_caller_id THEN
    RAISE EXCEPTION 'Only the CO can update regiment details';
  END IF;

  UPDATE public.regiments
  SET
    description = coalesce(p_description, description),
    website_url = coalesce(p_website_url, website_url)
  WHERE id = p_regiment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_regiment(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_regiment_id uuid;
  v_reg record;
BEGIN
  SELECT regiment_id INTO v_regiment_id
  FROM public.player_profiles
  WHERE id = v_caller_id;

  IF v_regiment_id IS NULL THEN
    RAISE EXCEPTION 'Not in a regiment';
  END IF;

  SELECT * INTO v_reg
  FROM public.regiments
  WHERE id = v_regiment_id;

  IF v_reg.co_id = v_caller_id THEN
    RAISE EXCEPTION 'CO cannot leave the regiment. Transfer CO or request disbandment.';
  END IF;

  DELETE FROM public.regiment_members
  WHERE regiment_id = v_regiment_id AND player_id = v_caller_id;

  UPDATE public.player_profiles
  SET regiment_id = null
  WHERE id = v_caller_id;

  IF v_reg.xo_id = v_caller_id THEN
    UPDATE public.regiments
    SET xo_id = null
    WHERE id = v_regiment_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_kick_member(
  p_admin_id uuid,
  p_regiment_id uuid,
  p_target_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_reg record;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_reg
  FROM public.regiments
  WHERE id = p_regiment_id;

  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Regiment not found';
  END IF;

  DELETE FROM public.regiment_members
  WHERE regiment_id = p_regiment_id AND player_id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player is not a member of this regiment';
  END IF;

  UPDATE public.player_profiles
  SET regiment_id = null
  WHERE id = p_target_id;

  IF v_reg.co_id = p_target_id THEN
    UPDATE public.regiments
    SET co_id = null
    WHERE id = p_regiment_id;
  END IF;

  IF v_reg.xo_id = p_target_id THEN
    UPDATE public.regiments
    SET xo_id = null
    WHERE id = p_regiment_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_transfer_co(
  p_admin_id uuid,
  p_regiment_id uuid,
  p_new_co_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.regiment_members
    WHERE regiment_id = p_regiment_id AND player_id = p_new_co_id
  ) THEN
    RAISE EXCEPTION 'Target is not a member of this regiment';
  END IF;

  UPDATE public.regiments
  SET co_id = p_new_co_id
  WHERE id = p_regiment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_force_disband(
  p_admin_id uuid,
  p_regiment_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.regiments
  SET status = 'disbanded', disbanded_at = now()
  WHERE id = p_regiment_id;

  UPDATE public.player_profiles
  SET regiment_id = null
  WHERE regiment_id = p_regiment_id;

  DELETE FROM public.regiment_members
  WHERE regiment_id = p_regiment_id;

  UPDATE public.regiment_join_requests
  SET status = 'cancelled', resolved_at = now()
  WHERE regiment_id = p_regiment_id AND status = 'pending';
END;
$$;

-- ============================================================
-- 6. Add SET search_path to functions that already use auth.uid()
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_moderator(
  p_target_id uuid,
  p_is_moderator boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = auth.uid() AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only admins can assign moderators';
  END IF;

  IF p_target_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot modify your own moderator status';
  END IF;

  UPDATE public.player_profiles
  SET is_moderator = p_is_moderator
  WHERE id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player not found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.ban_player(
  p_target_id uuid,
  p_reason text DEFAULT 'No reason provided'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = auth.uid() AND (is_admin = true OR is_moderator = true)
  ) THEN
    RAISE EXCEPTION 'Only admins and moderators can ban players';
  END IF;

  IF p_target_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot ban yourself';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = p_target_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Cannot ban an admin';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = auth.uid() AND is_moderator = true AND is_admin = false
  ) AND EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = p_target_id AND is_moderator = true
  ) THEN
    RAISE EXCEPTION 'Moderators cannot ban other moderators';
  END IF;

  UPDATE public.player_profiles
  SET is_banned = true,
      ban_reason = p_reason,
      banned_at = now(),
      banned_by = auth.uid()
  WHERE id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player not found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.unban_player(
  p_target_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = auth.uid() AND (is_admin = true OR is_moderator = true)
  ) THEN
    RAISE EXCEPTION 'Only admins and moderators can unban players';
  END IF;

  UPDATE public.player_profiles
  SET is_banned = false,
      ban_reason = null,
      banned_at = null,
      banned_by = null
  WHERE id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player not found';
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.search_players(text);

CREATE OR REPLACE FUNCTION public.search_players(
  p_query text
)
RETURNS TABLE (
  id uuid,
  display_name text,
  is_banned boolean,
  ban_reason text,
  banned_at timestamptz,
  prestige_points integer,
  rank integer,
  is_admin boolean,
  is_moderator boolean,
  active_match_id text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles pp
    WHERE pp.id = auth.uid() AND (pp.is_admin = true OR pp.is_moderator = true)
  ) THEN
    RAISE EXCEPTION 'Only admins and moderators can search players';
  END IF;

  RETURN QUERY
    SELECT pp.id, pp.display_name, pp.is_banned, pp.ban_reason,
           pp.banned_at, pp.prestige_points, pp.rank, pp.is_admin,
           pp.is_moderator, pp.active_match_id
    FROM public.player_profiles pp
    WHERE pp.display_name ilike '%' || p_query || '%'
    ORDER BY pp.display_name
    LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_banned_players()
RETURNS TABLE (
  id uuid,
  display_name text,
  ban_reason text,
  banned_at timestamptz,
  banned_by uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles pp
    WHERE pp.id = auth.uid() AND (pp.is_admin = true OR pp.is_moderator = true)
  ) THEN
    RAISE EXCEPTION 'Only admins and moderators can list banned players';
  END IF;

  RETURN QUERY
    SELECT pp.id, pp.display_name, pp.ban_reason, pp.banned_at, pp.banned_by
    FROM public.player_profiles pp
    WHERE pp.is_banned = true
    ORDER BY pp.banned_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_admin(
  p_target_id uuid,
  p_is_admin boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.player_profiles
    WHERE id = auth.uid() AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only admins can assign admin roles';
  END IF;

  IF p_target_id = auth.uid() AND p_is_admin = false THEN
    RAISE EXCEPTION 'Cannot remove your own admin status';
  END IF;

  UPDATE public.player_profiles
  SET is_admin = p_is_admin
  WHERE id = p_target_id;
END;
$$;

-- ============================================================
-- 7. Server-only functions: add SET search_path
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_active_match(
  p_player_id uuid,
  p_match_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.player_profiles
  SET active_match_id = p_match_id
  WHERE id = p_player_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_active_match(
  p_player_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.player_profiles
  SET active_match_id = null
  WHERE id = p_player_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cleanup_stale_lobbies()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  deleted_count integer;
BEGIN
  DELETE FROM public.lobbies
  WHERE
    status = 'finished'
    OR (status = 'waiting'     AND created_at < now() - interval '30 minutes')
    OR (status = 'in_progress' AND created_at < now() - interval '2 hours');

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- ============================================================
-- 8. Trigger functions: add SET search_path
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_ban()
RETURNS trigger AS $$
DECLARE
  edge_function_url text;
  service_role_key text;
BEGIN
  IF NEW.is_banned = true AND (OLD.is_banned IS DISTINCT FROM true) THEN
    edge_function_url := current_setting('app.settings.supabase_url', true)
      || '/functions/v1/ban-notification';
    service_role_key := current_setting('app.settings.service_role_key', true);

    PERFORM extensions.http_post(
      edge_function_url,
      jsonb_build_object(
        'type', 'UPDATE',
        'record', row_to_json(NEW)::jsonb
      )::text,
      'application/json',
      ARRAY[
        extensions.http_header('Authorization', 'Bearer ' || service_role_key)
      ]
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.create_regiment_channel()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status <> 'active') THEN
    INSERT INTO public.chat_channels (name, type, regiment_id, created_by)
    VALUES (NEW.tag, 'regiment', NEW.id, NEW.co_id)
    ON CONFLICT (type, regiment_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================================
-- 9. Fix join_lobby: add auth/ban check, SET search_path
-- ============================================================

CREATE OR REPLACE FUNCTION public.join_lobby(p_lobby_id uuid)
RETURNS SETOF public.lobbies
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

  IF lobby_row.current_players >= lobby_row.max_players THEN
    RAISE EXCEPTION 'Lobby is full';
  END IF;

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

-- ============================================================
-- 10. Fix delete_custom_channel: IS DISTINCT FROM for NULL safety
-- ============================================================

CREATE OR REPLACE FUNCTION public.delete_custom_channel(p_channel_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_channel record;
BEGIN
  SELECT * INTO v_channel
  FROM public.chat_channels
  WHERE id = p_channel_id AND type = 'custom';

  IF v_channel IS NULL THEN
    RAISE EXCEPTION 'Channel not found or not a custom channel';
  END IF;

  IF v_channel.created_by IS DISTINCT FROM auth.uid() THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.player_profiles
      WHERE id = auth.uid() AND (is_admin = true OR is_moderator = true)
    ) THEN
      RAISE EXCEPTION 'Only the channel creator, admins, or moderators can delete a channel';
    END IF;
  END IF;

  DELETE FROM public.chat_channel_members WHERE channel_id = p_channel_id;
  DELETE FROM public.chat_messages WHERE channel_id = p_channel_id;
  DELETE FROM public.chat_channels WHERE id = p_channel_id;
END;
$$;

-- ============================================================
-- 11. Revoke EXECUTE on all public functions, then grant back
-- ============================================================

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Client-callable RPCs (authenticated users)
GRANT EXECUTE ON FUNCTION public.join_lobby(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_custom_channels() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_custom_channel(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_custom_channel(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_regiment_application(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_regiment_application(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_regiment_join(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_regiment_join(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.kick_regiment_member(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_regiment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_regiment_rank(uuid, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_regiment_xo(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_regiment_details(uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_players(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ban_player(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unban_player(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_banned_players() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_moderator(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_admin(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_force_disband(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_kick_member(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_transfer_co(uuid, uuid, uuid) TO authenticated;

-- Server-only RPCs stay revoked: record_match_result, record_player_result,
-- distribute_co_pp, set_active_match, clear_active_match, cleanup_stale_lobbies.
-- The game server calls these via service_role which bypasses these grants.

COMMIT;
