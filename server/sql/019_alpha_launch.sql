-- Phase 24: Alpha Launch - bug reports, feedback, site settings

-- Bug reports table
create table if not exists bug_reports (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references auth.users(id),
  display_name text,
  email text,
  title text not null,
  description text not null,
  category text not null default 'gameplay',
  severity text not null default 'medium',
  steps_to_reproduce text,
  status text not null default 'open',
  admin_notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table bug_reports enable row level security;

create policy "Anyone can submit bug reports"
  on bug_reports for insert
  with check (true);

create policy "Users can view own bug reports"
  on bug_reports for select
  using (auth.uid() = player_id);

create policy "Admins can view all bug reports"
  on bug_reports for select
  using (
    exists (
      select 1 from player_profiles
      where id = auth.uid() and (is_admin = true or is_moderator = true)
    )
  );

create policy "Admins can update bug reports"
  on bug_reports for update
  using (
    exists (
      select 1 from player_profiles
      where id = auth.uid() and is_admin = true
    )
  );

-- Feedback table
create table if not exists feedback (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references auth.users(id),
  display_name text,
  rating int check (rating between 1 and 5),
  category text not null default 'general',
  message text not null,
  created_at timestamptz default now()
);

alter table feedback enable row level security;

create policy "Anyone can submit feedback"
  on feedback for insert
  with check (true);

create policy "Admins can view feedback"
  on feedback for select
  using (
    exists (
      select 1 from player_profiles
      where id = auth.uid() and (is_admin = true or is_moderator = true)
    )
  );

-- New site settings for alpha features
insert into site_settings (key, value) values
  ('bugreports_enabled', true),
  ('feedback_enabled', true)
on conflict (key) do nothing;

-- Enable realtime on new tables
alter publication supabase_realtime add table bug_reports;
alter publication supabase_realtime add table feedback;
