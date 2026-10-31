-- Phase 30: Chat improvements
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- ============================================================
-- Enforce max message length at the database level (200 chars).
-- ============================================================
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_message_length CHECK (char_length(message) <= 200);

-- ============================================================
-- Enforce non-empty messages.
-- ============================================================
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_message_not_empty CHECK (char_length(trim(message)) > 0);
