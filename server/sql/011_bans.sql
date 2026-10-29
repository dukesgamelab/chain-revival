-- Phase 16: Admin & Moderation Tools
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- ============================================================
-- Ban columns on player_profiles
-- ============================================================
alter table public.player_profiles
  add column if not exists is_banned boolean not null default false;

alter table public.player_profiles
  add column if not exists ban_reason text;

alter table public.player_profiles
  add column if not exists banned_at timestamptz;

alter table public.player_profiles
  add column if not exists banned_by uuid references auth.users(id) on delete set null;

-- ============================================================
-- RPC: ban_player (admin only)
-- ============================================================
create or replace function public.ban_player(
  p_target_id uuid,
  p_reason text default 'No reason provided'
)
returns void
language plpgsql
security definer
as $$
begin
  -- Caller must be admin
  if not exists (
    select 1 from public.player_profiles
    where id = auth.uid() and is_admin = true
  ) then
    raise exception 'Only admins can ban players';
  end if;

  -- Cannot ban yourself
  if p_target_id = auth.uid() then
    raise exception 'Cannot ban yourself';
  end if;

  -- Cannot ban another admin
  if exists (
    select 1 from public.player_profiles
    where id = p_target_id and is_admin = true
  ) then
    raise exception 'Cannot ban an admin';
  end if;

  update public.player_profiles
  set is_banned = true,
      ban_reason = p_reason,
      banned_at = now(),
      banned_by = auth.uid()
  where id = p_target_id;

  if not found then
    raise exception 'Player not found';
  end if;
end;
$$;

-- ============================================================
-- RPC: unban_player (admin only)
-- ============================================================
create or replace function public.unban_player(
  p_target_id uuid
)
returns void
language plpgsql
security definer
as $$
begin
  -- Caller must be admin
  if not exists (
    select 1 from public.player_profiles
    where id = auth.uid() and is_admin = true
  ) then
    raise exception 'Only admins can unban players';
  end if;

  update public.player_profiles
  set is_banned = false,
      ban_reason = null,
      banned_at = null,
      banned_by = null
  where id = p_target_id;

  if not found then
    raise exception 'Player not found';
  end if;
end;
$$;

-- ============================================================
-- RPC: search_players (admin only, for ban management UI)
-- Returns up to 20 players matching a case-insensitive name query.
-- ============================================================
create or replace function public.search_players(
  p_query text
)
returns table (
  id uuid,
  display_name text,
  is_banned boolean,
  ban_reason text,
  banned_at timestamptz,
  prestige_points integer,
  rank integer,
  is_admin boolean
)
language plpgsql
security definer
as $$
begin
  -- Caller must be admin
  if not exists (
    select 1 from public.player_profiles pp
    where pp.id = auth.uid() and pp.is_admin = true
  ) then
    raise exception 'Only admins can search players';
  end if;

  return query
    select pp.id, pp.display_name, pp.is_banned, pp.ban_reason,
           pp.banned_at, pp.prestige_points, pp.rank, pp.is_admin
    from public.player_profiles pp
    where pp.display_name ilike '%' || p_query || '%'
    order by pp.display_name
    limit 20;
end;
$$;

-- ============================================================
-- RPC: list_banned_players (admin only)
-- Returns all currently banned players.
-- ============================================================
create or replace function public.list_banned_players()
returns table (
  id uuid,
  display_name text,
  ban_reason text,
  banned_at timestamptz,
  banned_by uuid
)
language plpgsql
security definer
as $$
begin
  -- Caller must be admin
  if not exists (
    select 1 from public.player_profiles pp
    where pp.id = auth.uid() and pp.is_admin = true
  ) then
    raise exception 'Only admins can list banned players';
  end if;

  return query
    select pp.id, pp.display_name, pp.ban_reason, pp.banned_at, pp.banned_by
    from public.player_profiles pp
    where pp.is_banned = true
    order by pp.banned_at desc;
end;
$$;

-- ============================================================
-- RLS: Block banned users from inserting into lobbies
-- Drop and recreate the insert policy to add the ban check.
-- ============================================================
drop policy if exists "Authenticated users can create lobbies" on public.lobbies;

create policy "Authenticated users can create lobbies"
  on public.lobbies
  for insert
  to authenticated
  with check (
    auth.uid() = host_id
    and not exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_banned = true
    )
  );

-- ============================================================
-- RLS: Block banned users from sending chat messages
-- Drop and recreate the insert policy to add the ban check.
-- ============================================================
drop policy if exists "Users can send chat messages" on public.chat_messages;

create policy "Users can send chat messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and not exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_banned = true
    )
  );

-- ============================================================
-- RLS: Block banned users from joining lobbies (update policy)
-- If the "Authenticated users can join waiting lobbies" policy
-- exists (added manually), drop and recreate with ban check.
-- ============================================================
drop policy if exists "Authenticated users can join waiting lobbies" on public.lobbies;

create policy "Authenticated users can join waiting lobbies"
  on public.lobbies
  for update
  to authenticated
  using (status = 'waiting')
  with check (
    not exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_banned = true
    )
  );
