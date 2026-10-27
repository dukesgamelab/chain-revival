-- Player profiles table for Chain Revival.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

create table if not exists public.player_profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  games_played integer not null default 0,
  games_won    integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Enable Row Level Security
alter table public.player_profiles enable row level security;

-- Anyone can read all profiles (leaderboard, opponent info, etc.)
create policy "Profiles are viewable by everyone"
  on public.player_profiles
  for select
  using (true);

-- Users can insert their own profile row.
create policy "Users can insert their own profile"
  on public.player_profiles
  for insert
  with check (auth.uid() = id);

-- Users can only update their own profile.
create policy "Users can update their own profile"
  on public.player_profiles
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Auto-create a profile row when a new user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.player_profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

-- Trigger: run after a new auth.users row is created.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- Auto-update the updated_at timestamp on changes.
create or replace function public.update_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at on public.player_profiles;
create trigger set_updated_at
  before update on public.player_profiles
  for each row
  execute function public.update_updated_at();
