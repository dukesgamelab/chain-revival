-- 033: Tighten chat_messages RLS to enforce channel access
-- Run in Supabase SQL Editor (Dashboard > SQL Editor > New Query).
--
-- Previously, all non-whisper messages were visible to every authenticated
-- user regardless of channel. This migration restricts reads and writes
-- so that regiment and custom channel messages are only accessible to
-- members of those channels.

BEGIN;

-- ============================================================
-- 1. Restrict SELECT: messages visible only in accessible channels
-- ============================================================
DROP POLICY IF EXISTS "Chat messages are viewable by authenticated users" ON public.chat_messages;

CREATE POLICY "Chat messages are viewable by authorized users"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    -- Whispers: sender or recipient only
    (is_whisper = true AND (whisper_to = auth.uid() OR user_id = auth.uid()))
    OR (
      is_whisper = false AND (
        -- No channel_id (game chat or legacy messages)
        channel_id IS NULL
        -- Global channels
        OR EXISTS (
          SELECT 1 FROM public.chat_channels
          WHERE id = channel_id AND type = 'global'
        )
        -- Regiment channels: caller must be in that regiment
        OR EXISTS (
          SELECT 1 FROM public.chat_channels cc
          WHERE cc.id = channel_id AND cc.type = 'regiment'
            AND cc.regiment_id = (
              SELECT pp.regiment_id FROM public.player_profiles pp
              WHERE pp.id = auth.uid()
            )
        )
        -- Custom channels: caller must be a member
        OR EXISTS (
          SELECT 1 FROM public.chat_channel_members ccm
          WHERE ccm.channel_id = chat_messages.channel_id
            AND ccm.user_id = auth.uid()
        )
      )
    )
  );

-- ============================================================
-- 2. Restrict INSERT: can only post to channels you belong to
-- ============================================================
DROP POLICY IF EXISTS "Users can send chat messages" ON public.chat_messages;

CREATE POLICY "Users can send chat messages to authorized channels"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND (
      -- No channel_id (game chat or legacy)
      channel_id IS NULL
      -- Global channels
      OR EXISTS (
        SELECT 1 FROM public.chat_channels
        WHERE id = channel_id AND type = 'global'
      )
      -- Regiment channels: caller must be in that regiment
      OR EXISTS (
        SELECT 1 FROM public.chat_channels cc
        WHERE cc.id = channel_id AND cc.type = 'regiment'
          AND cc.regiment_id = (
            SELECT pp.regiment_id FROM public.player_profiles pp
            WHERE pp.id = auth.uid()
          )
      )
      -- Custom channels: caller must be a member
      OR EXISTS (
        SELECT 1 FROM public.chat_channel_members ccm
        WHERE ccm.channel_id = chat_messages.channel_id
          AND ccm.user_id = auth.uid()
      )
    )
  );

COMMIT;
