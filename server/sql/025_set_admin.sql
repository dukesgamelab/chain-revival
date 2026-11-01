-- Phase 37: Admin role management RPC
-- Allows admins to grant or revoke admin status on other players.

create or replace function public.set_admin(
  p_target_id uuid,
  p_is_admin boolean
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
    raise exception 'Only admins can assign admin roles';
  end if;

  -- Cannot remove your own admin
  if p_target_id = auth.uid() and p_is_admin = false then
    raise exception 'Cannot remove your own admin status';
  end if;

  update public.player_profiles
  set is_admin = p_is_admin
  where id = p_target_id;
end;
$$;
