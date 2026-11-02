-- Custom channel delete + update list RPC to include created_by.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- Drop old version first - return type changed (added created_by column).
DROP FUNCTION IF EXISTS public.list_custom_channels();

CREATE OR REPLACE FUNCTION public.list_custom_channels()
RETURNS TABLE (id uuid, name text, type text, created_by uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.id, c.name, c.type, c.created_by
  FROM public.chat_channels c
  WHERE c.type = 'custom'
  ORDER BY c.name;
$$;

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

  IF v_channel.created_by != auth.uid() THEN
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
