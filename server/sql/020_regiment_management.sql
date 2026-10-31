-- Phase 25: Regiment Management
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).
-- Adds admin override RPCs + player leave RPC + missing RLS policies.

-- ============================================================
-- RPC: Player leaves their regiment (atomically)
-- ============================================================
create or replace function public.leave_regiment(p_player_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_regiment_id uuid;
  v_reg record;
begin
  select regiment_id into v_regiment_id
  from public.player_profiles
  where id = p_player_id;

  if v_regiment_id is null then
    raise exception 'Not in a regiment';
  end if;

  select * into v_reg
  from public.regiments
  where id = v_regiment_id;

  if v_reg.co_id = p_player_id then
    raise exception 'CO cannot leave the regiment. Transfer CO or request disbandment.';
  end if;

  delete from public.regiment_members
  where regiment_id = v_regiment_id and player_id = p_player_id;

  update public.player_profiles
  set regiment_id = null
  where id = p_player_id;

  if v_reg.xo_id = p_player_id then
    update public.regiments
    set xo_id = null
    where id = v_regiment_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: Reject a join request (CO/XO rejects a player's request)
-- ============================================================
create or replace function public.reject_regiment_join(
  p_request_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req record;
begin
  select * into v_req
  from public.regiment_join_requests
  where id = p_request_id and status = 'pending';

  if v_req is null then
    raise exception 'Request not found or already resolved';
  end if;

  if v_req.direction = 'request' then
    if not exists (
      select 1 from public.regiments
      where id = v_req.regiment_id
        and (co_id = p_user_id or xo_id = p_user_id)
    ) then
      raise exception 'Not authorized';
    end if;
  elsif v_req.direction = 'invite' then
    if v_req.player_id != p_user_id then
      raise exception 'Not authorized';
    end if;
  end if;

  update public.regiment_join_requests
  set status = 'rejected', resolved_by = p_user_id, resolved_at = now()
  where id = p_request_id;
end;
$$;

-- ============================================================
-- RPC: Admin kicks a member from any regiment
-- ============================================================
create or replace function public.admin_kick_member(
  p_admin_id uuid,
  p_regiment_id uuid,
  p_target_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reg record;
begin
  if not exists (
    select 1 from public.player_profiles
    where id = p_admin_id and is_admin = true
  ) then
    raise exception 'Not authorized';
  end if;

  select * into v_reg
  from public.regiments
  where id = p_regiment_id;

  if v_reg is null then
    raise exception 'Regiment not found';
  end if;

  delete from public.regiment_members
  where regiment_id = p_regiment_id and player_id = p_target_id;

  if not found then
    raise exception 'Player is not a member of this regiment';
  end if;

  update public.player_profiles
  set regiment_id = null
  where id = p_target_id;

  if v_reg.co_id = p_target_id then
    update public.regiments
    set co_id = null
    where id = p_regiment_id;
  end if;

  if v_reg.xo_id = p_target_id then
    update public.regiments
    set xo_id = null
    where id = p_regiment_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: Admin transfers CO to another member
-- ============================================================
create or replace function public.admin_transfer_co(
  p_admin_id uuid,
  p_regiment_id uuid,
  p_new_co_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.player_profiles
    where id = p_admin_id and is_admin = true
  ) then
    raise exception 'Not authorized';
  end if;

  if not exists (
    select 1 from public.regiment_members
    where regiment_id = p_regiment_id and player_id = p_new_co_id
  ) then
    raise exception 'Target is not a member of this regiment';
  end if;

  update public.regiments
  set co_id = p_new_co_id
  where id = p_regiment_id;
end;
$$;

-- ============================================================
-- RPC: Admin force-disbands a regiment
-- ============================================================
create or replace function public.admin_force_disband(
  p_admin_id uuid,
  p_regiment_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.player_profiles
    where id = p_admin_id and is_admin = true
  ) then
    raise exception 'Not authorized';
  end if;

  update public.regiments
  set status = 'disbanded', disbanded_at = now()
  where id = p_regiment_id;

  update public.player_profiles
  set regiment_id = null
  where regiment_id = p_regiment_id;

  delete from public.regiment_members
  where regiment_id = p_regiment_id;

  update public.regiment_join_requests
  set status = 'cancelled', resolved_at = now()
  where regiment_id = p_regiment_id and status = 'pending';
end;
$$;

-- ============================================================
-- Additional RLS policies
-- ============================================================

-- Admins can view all join requests across all regiments
create policy "Admins can view all join requests"
  on public.regiment_join_requests
  for select
  to authenticated
  using (
    exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- Players can cancel their own pending requests
create policy "Users can cancel their own pending requests"
  on public.regiment_join_requests
  for update
  to authenticated
  using (
    player_id = auth.uid()
    and direction = 'request'
    and status = 'pending'
  );

-- Admins can view all regiment applications (pending + resolved)
-- Note: policy for pending already exists; this covers resolved ones too
-- (The existing admin policy already uses is_admin check, so this is redundant but explicit)

-- Admins can view pending regiments for approval
create policy "Admins can view pending regiments"
  on public.regiments
  for select
  to authenticated
  using (
    status = 'pending'
    and exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_admin = true
    )
  );
