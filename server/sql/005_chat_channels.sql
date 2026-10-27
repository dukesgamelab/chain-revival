-- Add a channel column to chat_messages so global and in-game chat are separate.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS channel text NOT NULL DEFAULT 'global';

-- Index for fast polling by channel.
CREATE INDEX IF NOT EXISTS idx_chat_messages_channel_created
  ON public.chat_messages (channel, created_at DESC);
