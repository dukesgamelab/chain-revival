-- Fix infinite recursion in chat_channel_members RLS policy.
-- The old policy referenced chat_channel_members in its own USING clause,
-- causing PostgreSQL to recurse infinitely when evaluating RLS.
-- Fix: simplify to "you can see your own memberships".
-- Run this in the Supabase SQL Editor.

DROP POLICY IF EXISTS "Members can view channel membership" ON public.chat_channel_members;

CREATE POLICY "Members can view channel membership"
  ON public.chat_channel_members FOR SELECT TO authenticated
  USING (user_id = auth.uid());
