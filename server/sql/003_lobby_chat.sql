-- Lobby chat messages for Chain Revival.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).
--
-- Messages older than 24 hours can be purged with a cron job or manual cleanup:
--   DELETE FROM public.chat_messages WHERE created_at < now() - interval '24 hours';

create table if not exists public.chat_messages (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  display_name  text not null default '',
  message       text not null default '',
  created_at    timestamptz not null default now()
);

-- Enable Row Level Security
alter table public.chat_messages enable row level security;

-- Any authenticated user can read all chat messages.
create policy "Chat messages are viewable by authenticated users"
  on public.chat_messages
  for select
  to authenticated
  using (true);

-- Authenticated users can insert their own messages.
create policy "Users can send chat messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Index for fast polling of recent messages.
create index if not exists idx_chat_messages_created_at
  on public.chat_messages (created_at desc);
