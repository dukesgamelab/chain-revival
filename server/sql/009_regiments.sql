-- Phase 14: Regiments & Companies
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- Add is_admin flag to player_profiles (for regiment/disband approvals)
alter table public.player_profiles
  add column if not exists is_admin boolean not null default false;

-- Add regiment_id to player_profiles (null = no regiment)
alter table public.player_profiles
  add column if not exists regiment_id uuid;

-- ============================================================
-- Regiments
-- ============================================================
create table if not exists public.regiments (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique,
  tag           text not null unique,
  description   text not null default '',
  website_url   text,
  co_id         uuid references auth.users(id) on delete set null,
  xo_id         uuid references auth.users(id) on delete set null,
  status        text not null default 'pending'
                check (status in ('pending', 'active', 'disbanded')),
  max_members   integer not null default 20,
  created_at    timestamptz not null default now(),
  approved_at   timestamptz,
  disbanded_at  timestamptz
);

-- FK from player_profiles to regiments (added after regiments table exists)
alter table public.player_profiles
  add constraint fk_player_regiment
  foreign key (regiment_id) references public.regiments(id) on delete set null;

alter table public.regiments enable row level security;

-- Everyone can read active regiments
create policy "Active regiments are viewable by everyone"
  on public.regiments
  for select
  using (status = 'active');

-- Admins can read all regiments (including pending/disbanded)
create policy "Admins can view all regiments"
  on public.regiments
  for select
  to authenticated
  using (
    exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- Only service role or admins update regiments (CO/XO edits go through RPC)
create policy "Admins can update regiments"
  on public.regiments
  for update
  to authenticated
  using (
    exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- ============================================================
-- Regiment Members
-- ============================================================
create table if not exists public.regiment_members (
  regiment_id    uuid not null references public.regiments(id) on delete cascade,
  player_id      uuid not null references auth.users(id) on delete cascade,
  assigned_rank  text check (assigned_rank in ('1LT', 'CPT', 'MAJ', 'LT COL', 'COL')),
  joined_at      timestamptz not null default now(),
  primary key (regiment_id, player_id)
);

alter table public.regiment_members enable row level security;

-- Anyone can read membership (for displaying tags, rosters)
create policy "Regiment members are viewable by everyone"
  on public.regiment_members
  for select
  using (true);

-- Members can leave (delete their own row)
create policy "Members can leave their regiment"
  on public.regiment_members
  for delete
  to authenticated
  using (player_id = auth.uid());

-- ============================================================
-- Regiment Applications (create/disband requests, admin-reviewed)
-- ============================================================
create table if not exists public.regiment_applications (
  id              uuid primary key default gen_random_uuid(),
  type            text not null check (type in ('create', 'disband')),
  regiment_id     uuid references public.regiments(id) on delete cascade,
  applicant_id    uuid not null references auth.users(id) on delete cascade,
  regiment_name   text,
  regiment_tag    text,
  description     text not null default '',
  status          text not null default 'pending'
                  check (status in ('pending', 'approved', 'rejected')),
  reviewed_by     uuid references auth.users(id) on delete set null,
  reviewed_at     timestamptz,
  review_note     text,
  created_at      timestamptz not null default now()
);

alter table public.regiment_applications enable row level security;

-- Applicants can read their own applications
create policy "Users can view their own applications"
  on public.regiment_applications
  for select
  to authenticated
  using (applicant_id = auth.uid());

-- Admins can read all applications
create policy "Admins can view all applications"
  on public.regiment_applications
  for select
  to authenticated
  using (
    exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- Any authenticated user can submit a create application
create policy "Users can submit create applications"
  on public.regiment_applications
  for insert
  to authenticated
  with check (
    applicant_id = auth.uid()
    and type = 'create'
  );

-- CO can submit a disband application for their regiment
create policy "CO can submit disband applications"
  on public.regiment_applications
  for insert
  to authenticated
  with check (
    applicant_id = auth.uid()
    and type = 'disband'
    and regiment_id is not null
    and exists (
      select 1 from public.regiments
      where id = regiment_id and co_id = auth.uid()
    )
  );

-- Admins can update applications (approve/reject)
create policy "Admins can update applications"
  on public.regiment_applications
  for update
  to authenticated
  using (
    exists (
      select 1 from public.player_profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- ============================================================
-- Regiment Join Requests (player requests + CO/XO invites)
-- ============================================================
create table if not exists public.regiment_join_requests (
  id            uuid primary key default gen_random_uuid(),
  regiment_id   uuid not null references public.regiments(id) on delete cascade,
  player_id     uuid not null references auth.users(id) on delete cascade,
  direction     text not null check (direction in ('request', 'invite')),
  invited_by    uuid references auth.users(id) on delete set null,
  status        text not null default 'pending'
                check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  resolved_by   uuid references auth.users(id) on delete set null,
  resolved_at   timestamptz,
  created_at    timestamptz not null default now()
);

alter table public.regiment_join_requests enable row level security;

-- Players can see their own requests and invites
create policy "Users can view their own join requests"
  on public.regiment_join_requests
  for select
  to authenticated
  using (player_id = auth.uid());

-- CO/XO can see all join requests for their regiment
create policy "CO and XO can view regiment join requests"
  on public.regiment_join_requests
  for select
  to authenticated
  using (
    exists (
      select 1 from public.regiments
      where id = regiment_id
        and (co_id = auth.uid() or xo_id = auth.uid())
    )
  );

-- Players can submit a request to join an active regiment
create policy "Users can request to join a regiment"
  on public.regiment_join_requests
  for insert
  to authenticated
  with check (
    player_id = auth.uid()
    and direction = 'request'
    and exists (
      select 1 from public.regiments
      where id = regiment_id and status = 'active'
    )
  );

-- CO/XO can send invites
create policy "CO and XO can send invites"
  on public.regiment_join_requests
  for insert
  to authenticated
  with check (
    direction = 'invite'
    and invited_by = auth.uid()
    and exists (
      select 1 from public.regiments
      where id = regiment_id
        and status = 'active'
        and (co_id = auth.uid() or xo_id = auth.uid())
    )
  );

-- CO/XO can resolve requests (accept/reject)
create policy "CO and XO can resolve join requests"
  on public.regiment_join_requests
  for update
  to authenticated
  using (
    direction = 'request'
    and exists (
      select 1 from public.regiments
      where id = regiment_id
        and (co_id = auth.uid() or xo_id = auth.uid())
    )
  );

-- Players can resolve invites they received (accept/reject)
create policy "Users can resolve invites sent to them"
  on public.regiment_join_requests
  for update
  to authenticated
  using (
    direction = 'invite'
    and player_id = auth.uid()
  );

-- ============================================================
-- PP Distribution Log (CO earns 20% of member match PP)
-- ============================================================
create table if not exists public.pp_distribution_log (
  id            uuid primary key default gen_random_uuid(),
  match_id      text not null,
  source_id     uuid not null references auth.users(id) on delete cascade,
  recipient_id  uuid not null references auth.users(id) on delete cascade,
  regiment_id   uuid not null references public.regiments(id) on delete cascade,
  pp_amount     integer not null,
  created_at    timestamptz not null default now()
);

alter table public.pp_distribution_log enable row level security;

-- Players can see PP they received or gave
create policy "Users can view their own PP distributions"
  on public.pp_distribution_log
  for select
  to authenticated
  using (source_id = auth.uid() or recipient_id = auth.uid());

-- Only service role inserts (server writes this at match end)

-- ============================================================
-- RPC: Approve a regiment creation application
-- ============================================================
create or replace function public.approve_regiment_application(
  p_application_id  uuid,
  p_admin_id        uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app record;
  v_regiment_id uuid;
begin
  -- Verify caller is admin
  if not exists (
    select 1 from public.player_profiles
    where id = p_admin_id and is_admin = true
  ) then
    raise exception 'Not authorized';
  end if;

  -- Fetch application
  select * into v_app
  from public.regiment_applications
  where id = p_application_id and status = 'pending';

  if v_app is null then
    raise exception 'Application not found or already resolved';
  end if;

  if v_app.type = 'create' then
    -- Create the regiment
    insert into public.regiments (name, tag, description, co_id, status, approved_at)
    values (v_app.regiment_name, v_app.regiment_tag, v_app.description, v_app.applicant_id, 'active', now())
    returning id into v_regiment_id;

    -- Add the CO as the first member
    insert into public.regiment_members (regiment_id, player_id, assigned_rank)
    values (v_regiment_id, v_app.applicant_id, 'COL');

    -- Set regiment_id on the CO's profile
    update public.player_profiles
    set regiment_id = v_regiment_id
    where id = v_app.applicant_id;

  elsif v_app.type = 'disband' then
    -- Disband the regiment
    update public.regiments
    set status = 'disbanded', disbanded_at = now()
    where id = v_app.regiment_id;

    -- Clear regiment_id for all members
    update public.player_profiles
    set regiment_id = null
    where regiment_id = v_app.regiment_id;

    -- Remove all members
    delete from public.regiment_members
    where regiment_id = v_app.regiment_id;

    v_regiment_id := v_app.regiment_id;
  end if;

  -- Mark application as approved
  update public.regiment_applications
  set status = 'approved', reviewed_by = p_admin_id, reviewed_at = now()
  where id = p_application_id;

  return v_regiment_id;
end;
$$;

-- ============================================================
-- RPC: Reject a regiment application
-- ============================================================
create or replace function public.reject_regiment_application(
  p_application_id  uuid,
  p_admin_id        uuid,
  p_note            text default null
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

  update public.regiment_applications
  set status = 'rejected',
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      review_note = p_note
  where id = p_application_id and status = 'pending';

  if not found then
    raise exception 'Application not found or already resolved';
  end if;
end;
$$;

-- ============================================================
-- RPC: Accept a join request or invite (atomically adds member)
-- ============================================================
create or replace function public.accept_regiment_join(
  p_request_id  uuid,
  p_user_id     uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req record;
  v_member_count integer;
  v_max integer;
begin
  select * into v_req
  from public.regiment_join_requests
  where id = p_request_id and status = 'pending';

  if v_req is null then
    raise exception 'Request not found or already resolved';
  end if;

  -- Authorization check
  if v_req.direction = 'request' then
    -- CO/XO accepts a player's request
    if not exists (
      select 1 from public.regiments
      where id = v_req.regiment_id
        and (co_id = p_user_id or xo_id = p_user_id)
    ) then
      raise exception 'Not authorized';
    end if;
  elsif v_req.direction = 'invite' then
    -- Player accepts an invite sent to them
    if v_req.player_id != p_user_id then
      raise exception 'Not authorized';
    end if;
  end if;

  -- Check the player isn't already in a regiment
  if exists (
    select 1 from public.player_profiles
    where id = v_req.player_id and regiment_id is not null
  ) then
    raise exception 'Player is already in a regiment';
  end if;

  -- Check member cap
  select count(*) into v_member_count
  from public.regiment_members
  where regiment_id = v_req.regiment_id;

  select max_members into v_max
  from public.regiments
  where id = v_req.regiment_id;

  if v_member_count >= v_max then
    raise exception 'Regiment is full';
  end if;

  -- Add member
  insert into public.regiment_members (regiment_id, player_id)
  values (v_req.regiment_id, v_req.player_id);

  -- Set regiment_id on profile
  update public.player_profiles
  set regiment_id = v_req.regiment_id
  where id = v_req.player_id;

  -- Mark request as accepted
  update public.regiment_join_requests
  set status = 'accepted', resolved_by = p_user_id, resolved_at = now()
  where id = p_request_id;

  -- Cancel any other pending requests/invites for this player
  update public.regiment_join_requests
  set status = 'cancelled', resolved_at = now()
  where player_id = v_req.player_id
    and id != p_request_id
    and status = 'pending';
end;
$$;

-- ============================================================
-- RPC: CO/XO kicks a member
-- ============================================================
create or replace function public.kick_regiment_member(
  p_regiment_id  uuid,
  p_target_id    uuid,
  p_caller_id    uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reg record;
begin
  select * into v_reg
  from public.regiments
  where id = p_regiment_id and status = 'active';

  if v_reg is null then
    raise exception 'Regiment not found';
  end if;

  -- Only CO or XO can kick
  if v_reg.co_id != p_caller_id and v_reg.xo_id != p_caller_id then
    raise exception 'Not authorized';
  end if;

  -- Cannot kick the CO
  if p_target_id = v_reg.co_id then
    raise exception 'Cannot kick the commanding officer';
  end if;

  -- XO cannot kick the CO (already covered), but also can't be kicked by XO
  -- Actually XO can only be removed by CO. If caller is XO and target is XO, that's self.
  -- CO can kick the XO though. Let's just prevent XO from kicking XO.
  if p_caller_id = v_reg.xo_id and p_target_id = v_reg.xo_id then
    raise exception 'Cannot kick yourself; leave instead';
  end if;

  -- Remove from members
  delete from public.regiment_members
  where regiment_id = p_regiment_id and player_id = p_target_id;

  if not found then
    raise exception 'Player is not a member of this regiment';
  end if;

  -- Clear regiment_id on profile
  update public.player_profiles
  set regiment_id = null
  where id = p_target_id;

  -- If we kicked the XO, clear xo_id
  if p_target_id = v_reg.xo_id then
    update public.regiments
    set xo_id = null
    where id = p_regiment_id;
  end if;
end;
$$;

-- ============================================================
-- RPC: CO/XO assigns a rank to a member
-- ============================================================
create or replace function public.assign_regiment_rank(
  p_regiment_id   uuid,
  p_target_id     uuid,
  p_caller_id     uuid,
  p_rank          text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reg record;
  v_target_pp_rank integer;
begin
  select * into v_reg
  from public.regiments
  where id = p_regiment_id and status = 'active';

  if v_reg is null then
    raise exception 'Regiment not found';
  end if;

  -- Only CO or XO can assign ranks
  if v_reg.co_id != p_caller_id and v_reg.xo_id != p_caller_id then
    raise exception 'Not authorized';
  end if;

  -- Validate rank value
  if p_rank is not null and p_rank not in ('1LT', 'CPT', 'MAJ', 'LT COL', 'COL') then
    raise exception 'Invalid assigned rank';
  end if;

  -- Target must have PP rank >= 2LT (rank index 7)
  select rank into v_target_pp_rank
  from public.player_profiles
  where id = p_target_id;

  if v_target_pp_rank < 7 then
    raise exception 'Player must be 2LT or higher to receive an assigned rank';
  end if;

  -- Assign the rank
  update public.regiment_members
  set assigned_rank = p_rank
  where regiment_id = p_regiment_id and player_id = p_target_id;

  if not found then
    raise exception 'Player is not a member of this regiment';
  end if;
end;
$$;

-- ============================================================
-- RPC: CO sets or clears the XO
-- ============================================================
create or replace function public.set_regiment_xo(
  p_regiment_id  uuid,
  p_caller_id    uuid,
  p_xo_id        uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reg record;
begin
  select * into v_reg
  from public.regiments
  where id = p_regiment_id and status = 'active';

  if v_reg is null then
    raise exception 'Regiment not found';
  end if;

  -- Only CO can set XO
  if v_reg.co_id != p_caller_id then
    raise exception 'Only the CO can assign the XO';
  end if;

  -- If setting an XO, verify they are a member
  if p_xo_id is not null then
    if not exists (
      select 1 from public.regiment_members
      where regiment_id = p_regiment_id and player_id = p_xo_id
    ) then
      raise exception 'Target is not a member of this regiment';
    end if;
  end if;

  update public.regiments
  set xo_id = p_xo_id
  where id = p_regiment_id;
end;
$$;

-- ============================================================
-- RPC: CO updates regiment details (name, description, website)
-- ============================================================
create or replace function public.update_regiment_details(
  p_regiment_id   uuid,
  p_caller_id     uuid,
  p_description   text default null,
  p_website_url   text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reg record;
begin
  select * into v_reg
  from public.regiments
  where id = p_regiment_id and status = 'active';

  if v_reg is null then
    raise exception 'Regiment not found';
  end if;

  -- Only CO can update details
  if v_reg.co_id != p_caller_id then
    raise exception 'Only the CO can update regiment details';
  end if;

  update public.regiments
  set
    description = coalesce(p_description, description),
    website_url = coalesce(p_website_url, website_url)
  where id = p_regiment_id;
end;
$$;

-- ============================================================
-- RPC: Distribute CO PP after a match (called by server)
-- Looks up each player's regiment, gives 20% of earned PP to CO,
-- logs it, and recalculates the CO's rank.
-- ============================================================
create or replace function public.distribute_co_pp(
  p_match_id    text,
  p_player_id   uuid,
  p_pp_earned   integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_regiment_id uuid;
  v_co_id uuid;
  v_co_pp integer;
  v_new_co_pp integer;
begin
  -- Skip if player earned no PP
  if p_pp_earned <= 0 then
    return;
  end if;

  -- Look up the player's regiment
  select regiment_id into v_regiment_id
  from public.player_profiles
  where id = p_player_id;

  if v_regiment_id is null then
    return;
  end if;

  -- Look up the CO
  select co_id into v_co_id
  from public.regiments
  where id = v_regiment_id and status = 'active';

  if v_co_id is null then
    return;
  end if;

  -- Don't distribute to yourself
  if v_co_id = p_player_id then
    return;
  end if;

  -- Calculate 20% (floor)
  v_co_pp := p_pp_earned / 5;

  if v_co_pp <= 0 then
    return;
  end if;

  -- Award PP to the CO
  update public.player_profiles
  set prestige_points = prestige_points + v_co_pp
  where id = v_co_id;

  -- Recalculate CO rank
  select prestige_points into v_new_co_pp
  from public.player_profiles
  where id = v_co_id;

  update public.player_profiles
  set rank = case
    when v_new_co_pp >= 315500 then 9  -- CPT
    when v_new_co_pp >= 195500 then 8  -- 1LT
    when v_new_co_pp >= 115500 then 7  -- 2LT
    when v_new_co_pp >= 65500  then 6  -- MSG
    when v_new_co_pp >= 35500  then 5  -- SFC
    when v_new_co_pp >= 17500  then 4  -- SSG
    when v_new_co_pp >= 7500   then 3  -- SGT
    when v_new_co_pp >= 2500   then 2  -- CPL
    when v_new_co_pp >= 500    then 1  -- PFC
    else 0                             -- PVT
  end
  where id = v_co_id;

  -- Log the distribution
  insert into public.pp_distribution_log
    (match_id, source_id, recipient_id, regiment_id, pp_amount)
  values
    (p_match_id, p_player_id, v_co_id, v_regiment_id, v_co_pp);
end;
$$;

-- ============================================================
-- Indexes
-- ============================================================
create index if not exists idx_regiment_members_player
  on public.regiment_members (player_id);

create index if not exists idx_regiment_join_requests_player
  on public.regiment_join_requests (player_id, status);

create index if not exists idx_regiment_join_requests_regiment
  on public.regiment_join_requests (regiment_id, status);

create index if not exists idx_regiment_applications_status
  on public.regiment_applications (status);

create index if not exists idx_pp_distribution_recipient
  on public.pp_distribution_log (recipient_id, created_at desc);

create index if not exists idx_pp_distribution_source
  on public.pp_distribution_log (source_id, created_at desc);
