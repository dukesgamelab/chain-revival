-- Phase 17: Moderator Roles
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- ============================================================
-- Add is_moderator column to player_profiles
-- ============================================================
alter table public.player_profiles
  add column if not exists is_moderator boolean not null default false;

-- ============================================================
-- RPC: set_moderator (admin only)
-- Allows admins to grant or revoke moderator status.
-- ============================================================
create or replace function public.set_moderator(
  p_target_id uuid,
  p_is_moderator boolean
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
    raise exception 'Only admins can assign moderators';
  end if;

  -- Cannot modify yourself
  if p_target_id = auth.uid() then
    raise exception 'Cannot modify your own moderator status';
  end if;

  update public.player_profiles
  set is_moderator = p_is_moderator
  where id = p_target_id;

  if not found then
    raise exception 'Player not found';
  end if;
end;
$$;

-- ============================================================
-- Update ban_player: allow admins OR moderators
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
  -- Caller must be admin or moderator
  if not exists (
    select 1 from public.player_profiles
    where id = auth.uid() and (is_admin = true or is_moderator = true)
  ) then
    raise exception 'Only admins and moderators can ban players';
  end if;

  -- Cannot ban yourself
  if p_target_id = auth.uid() then
    raise exception 'Cannot ban yourself';
  end if;

  -- Cannot ban an admin
  if exists (
    select 1 from public.player_profiles
    where id = p_target_id and is_admin = true
  ) then
    raise exception 'Cannot ban an admin';
  end if;

  -- Moderators cannot ban other moderators
  if exists (
    select 1 from public.player_profiles
    where id = auth.uid() and is_moderator = true and is_admin = false
  ) and exists (
    select 1 from public.player_profiles
    where id = p_target_id and is_moderator = true
  ) then
    raise exception 'Moderators cannot ban other moderators';
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
-- Update unban_player: allow admins OR moderators
-- ============================================================
create or replace function public.unban_player(
  p_target_id uuid
)
returns void
language plpgsql
security definer
as $$
begin
  -- Caller must be admin or moderator
  if not exists (
    select 1 from public.player_profiles
    where id = auth.uid() and (is_admin = true or is_moderator = true)
  ) then
    raise exception 'Only admins and moderators can unban players';
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
-- Update search_players: allow admins OR moderators
-- Include is_moderator in results.
-- ============================================================
drop function if exists public.search_players(text);

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
  is_admin boolean,
  is_moderator boolean,
  active_match_id text
)
language plpgsql
security definer
as $$
begin
  -- Caller must be admin or moderator
  if not exists (
    select 1 from public.player_profiles pp
    where pp.id = auth.uid() and (pp.is_admin = true or pp.is_moderator = true)
  ) then
    raise exception 'Only admins and moderators can search players';
  end if;

  return query
    select pp.id, pp.display_name, pp.is_banned, pp.ban_reason,
           pp.banned_at, pp.prestige_points, pp.rank, pp.is_admin,
           pp.is_moderator, pp.active_match_id
    from public.player_profiles pp
    where pp.display_name ilike '%' || p_query || '%'
    order by pp.display_name
    limit 20;
end;
$$;

-- ============================================================
-- Update list_banned_players: allow admins OR moderators
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
  -- Caller must be admin or moderator
  if not exists (
    select 1 from public.player_profiles pp
    where pp.id = auth.uid() and (pp.is_admin = true or pp.is_moderator = true)
  ) then
    raise exception 'Only admins and moderators can list banned players';
  end if;

  return query
    select pp.id, pp.display_name, pp.ban_reason, pp.banned_at, pp.banned_by
    from public.player_profiles pp
    where pp.is_banned = true
    order by pp.banned_at desc;
end;
$$;
