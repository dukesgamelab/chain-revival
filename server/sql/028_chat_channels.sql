-- Phase 41: Chat channels
-- Adds regiment and custom chat channels alongside global chat.
-- Whispers (DMs) are a separate message type visible across all channels.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- ============================================================
-- Chat channels table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_channels (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  type          text NOT NULL DEFAULT 'custom'
                CHECK (type IN ('global', 'regiment', 'custom')),
  regiment_id   uuid REFERENCES public.regiments(id) ON DELETE CASCADE,
  created_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  max_members   integer NOT NULL DEFAULT 50,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (type, regiment_id)
);

ALTER TABLE public.chat_channels ENABLE ROW LEVEL SECURITY;

-- Seed the global channel
INSERT INTO public.chat_channels (name, type)
VALUES ('Global', 'global')
ON CONFLICT (type, regiment_id) DO NOTHING;

-- ============================================================
-- Channel members (for custom channels; regiment channels use
-- player_profiles.regiment_id instead)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_channel_members (
  channel_id    uuid NOT NULL REFERENCES public.chat_channels(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (channel_id, user_id)
);

ALTER TABLE public.chat_channel_members ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Add channel_id to chat_messages (nullable for migration;
-- existing rows keep channel='global' text column)
-- ============================================================
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS channel_id uuid REFERENCES public.chat_channels(id) ON DELETE CASCADE;

-- Add whisper columns
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS is_whisper boolean NOT NULL DEFAULT false;
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS whisper_to uuid REFERENCES auth.users(id) ON DELETE CASCADE;

-- Backfill existing messages to point at the global channel
UPDATE public.chat_messages
SET channel_id = (SELECT id FROM public.chat_channels WHERE type = 'global' LIMIT 1)
WHERE channel_id IS NULL;

-- Index for fetching messages by channel
CREATE INDEX IF NOT EXISTS idx_chat_messages_channel_id_created
  ON public.chat_messages (channel_id, created_at DESC);

-- Index for whisper lookups
CREATE INDEX IF NOT EXISTS idx_chat_messages_whisper
  ON public.chat_messages (whisper_to, created_at DESC)
  WHERE is_whisper = true;

-- ============================================================
-- Auto-create regiment channel when a regiment is approved
-- ============================================================
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_regiment_channel ON public.regiments;
CREATE TRIGGER trg_regiment_channel
  AFTER INSERT OR UPDATE OF status ON public.regiments
  FOR EACH ROW
  EXECUTE FUNCTION public.create_regiment_channel();

-- Create channels for already-active regiments
INSERT INTO public.chat_channels (name, type, regiment_id, created_by)
SELECT r.tag, 'regiment', r.id, r.co_id
FROM public.regiments r
WHERE r.status = 'active'
ON CONFLICT (type, regiment_id) DO NOTHING;

-- ============================================================
-- RLS policies for chat_channels
-- ============================================================

-- Everyone can see global channels
CREATE POLICY "Global channels visible to all authenticated"
  ON public.chat_channels FOR SELECT TO authenticated
  USING (type = 'global');

-- Regiment channels visible to regiment members
CREATE POLICY "Regiment channels visible to members"
  ON public.chat_channels FOR SELECT TO authenticated
  USING (
    type = 'regiment'
    AND regiment_id IN (
      SELECT regiment_id FROM public.player_profiles WHERE id = auth.uid()
    )
  );

-- Custom channels visible to members
CREATE POLICY "Custom channels visible to members"
  ON public.chat_channels FOR SELECT TO authenticated
  USING (
    type = 'custom'
    AND id IN (
      SELECT channel_id FROM public.chat_channel_members WHERE user_id = auth.uid()
    )
  );

-- Authenticated users can create custom channels
CREATE POLICY "Users can create custom channels"
  ON public.chat_channels FOR INSERT TO authenticated
  WITH CHECK (type = 'custom' AND created_by = auth.uid());

-- ============================================================
-- RLS policies for chat_channel_members
-- ============================================================

-- Members can see who is in their channels
CREATE POLICY "Members can view channel membership"
  ON public.chat_channel_members FOR SELECT TO authenticated
  USING (
    channel_id IN (
      SELECT channel_id FROM public.chat_channel_members WHERE user_id = auth.uid()
    )
  );

-- Channel creator can add members; users can join custom channels
CREATE POLICY "Users can join or be added to channels"
  ON public.chat_channel_members FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR channel_id IN (
      SELECT id FROM public.chat_channels WHERE created_by = auth.uid()
    )
  );

-- Users can leave channels
CREATE POLICY "Users can leave channels"
  ON public.chat_channel_members FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- Update chat_messages RLS to handle whispers
-- Messages are visible if:
--   1. You can see the channel, OR
--   2. It's a whisper to you or from you
-- ============================================================
DROP POLICY IF EXISTS "Chat messages are viewable by authenticated users" ON public.chat_messages;

CREATE POLICY "Chat messages are viewable by authenticated users"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    (is_whisper = false)
    OR (is_whisper = true AND (whisper_to = auth.uid() OR user_id = auth.uid()))
  );

-- Enable realtime on new tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_channels;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_channel_members;
