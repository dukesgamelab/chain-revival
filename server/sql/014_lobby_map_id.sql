alter table public.lobbies
  add column if not exists map_id text not null default 'ff_farm';
