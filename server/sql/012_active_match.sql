-- Phase 16b: Active match tracking for admin panel
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- ============================================================
-- Track which match a player is currently in
-- ============================================================
alter table public.player_profiles
  add column if not exists active_match_id text;

-- ============================================================
-- RPC: set_active_match (service role only, called by game server)
-- ============================================================
create or replace function public.set_active_match(
  p_player_id uuid,
  p_match_id text
)
returns void
language plpgsql
security definer
as $$
begin
  update public.player_profiles
  set active_match_id = p_match_id
  where id = p_player_id;
end;
$$;

-- ============================================================
-- RPC: clear_active_match (service role only, called by game server)
-- ============================================================
create or replace function public.clear_active_match(
  p_player_id uuid
)
returns void
language plpgsql
security definer
as $$
begin
  update public.player_profiles
  set active_match_id = null
  where id = p_player_id;
end;
$$;

-- ============================================================
-- Update search_players to include active_match_id
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
  is_admin boolean,
  active_match_id text
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
           pp.banned_at, pp.prestige_points, pp.rank, pp.is_admin,
           pp.active_match_id
    from public.player_profiles pp
    where pp.display_name ilike '%' || p_query || '%'
    order by pp.display_name
    limit 20;
end;
$$;
