-- Lobby cleanup for Chain Revival.
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).
--
-- Creates a function that removes stale lobbies:
--   - 'finished' lobbies (already done)
--   - 'waiting' lobbies older than 30 minutes (host probably left)
--   - 'in_progress' lobbies older than 2 hours (match is long over)
--
-- To run manually:   SELECT public.cleanup_stale_lobbies();
-- To schedule with pg_cron (if enabled on your Supabase plan):
--   SELECT cron.schedule('cleanup-lobbies', '*/10 * * * *', 'SELECT public.cleanup_stale_lobbies()');

create or replace function public.cleanup_stale_lobbies()
returns integer
language plpgsql
security definer
as $$
declare
  deleted_count integer;
begin
  delete from public.lobbies
  where
    status = 'finished'
    or (status = 'waiting'    and created_at < now() - interval '30 minutes')
    or (status = 'in_progress' and created_at < now() - interval '2 hours');

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;
