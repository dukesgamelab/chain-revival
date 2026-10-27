-- Lobbies table for Chain Revival online matchmaking.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

create table if not exists public.lobbies (
  id                 uuid primary key default gen_random_uuid(),
  host_id            uuid not null references auth.users(id) on delete cascade,
  host_display_name  text not null default '',
  match_name         text not null default 'New Game',
  status             text not null default 'waiting'
                     check (status in ('waiting', 'in_progress', 'finished')),
  max_players        integer not null default 2,
  current_players    integer not null default 1,
  server_url         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Enable Row Level Security
alter table public.lobbies enable row level security;

-- Any authenticated user can see all lobbies.
create policy "Lobbies are viewable by authenticated users"
  on public.lobbies
  for select
  to authenticated
  using (true);

-- Any authenticated user can create a lobby.
create policy "Authenticated users can create lobbies"
  on public.lobbies
  for insert
  to authenticated
  with check (auth.uid() = host_id);

-- Only the host can update their own lobby.
create policy "Hosts can update their own lobby"
  on public.lobbies
  for update
  to authenticated
  using (auth.uid() = host_id)
  with check (auth.uid() = host_id);

-- Only the host can delete their own lobby.
create policy "Hosts can delete their own lobby"
  on public.lobbies
  for delete
  to authenticated
  using (auth.uid() = host_id);

-- Auto-update the updated_at timestamp on changes.
drop trigger if exists set_lobbies_updated_at on public.lobbies;
create trigger set_lobbies_updated_at
  before update on public.lobbies
  for each row
  execute function public.update_updated_at();
