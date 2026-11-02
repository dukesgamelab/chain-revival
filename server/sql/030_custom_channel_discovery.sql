-- Custom channel RPCs for create, list, and discovery.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- List all custom channels for the join dialog (bypasses RLS).
CREATE OR REPLACE FUNCTION public.list_custom_channels()
RETURNS TABLE (id uuid, name text, type text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.id, c.name, c.type
  FROM public.chat_channels c
  WHERE c.type = 'custom'
  ORDER BY c.name;
$$;

-- Create a custom channel and auto-join the creator.
-- Returns the new channel row so the client can switch to it.
CREATE OR REPLACE FUNCTION public.create_custom_channel(p_name text)
RETURNS TABLE (id uuid, name text, type text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_channel_id uuid;
BEGIN
  INSERT INTO public.chat_channels (name, type, created_by)
  VALUES (p_name, 'custom', auth.uid())
  RETURNING public.chat_channels.id INTO v_channel_id;

  INSERT INTO public.chat_channel_members (channel_id, user_id)
  VALUES (v_channel_id, auth.uid());

  RETURN QUERY
  SELECT c.id, c.name, c.type
  FROM public.chat_channels c
  WHERE c.id = v_channel_id;
END;
$$;
