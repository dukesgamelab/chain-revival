-- 010_chat_realtime.sql
-- Enable Supabase Realtime on the chat_messages table so clients can
-- subscribe to INSERT events instead of polling every 3 seconds.
--
-- Run in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
