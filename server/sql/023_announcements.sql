-- Phase 36: Announcements & Community
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query).

-- ============================================================
-- 1. Announcements table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.announcements (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text NOT NULL,
  body          text NOT NULL,
  category      text NOT NULL DEFAULT 'news'
                    CHECK (category IN ('news', 'patch-notes', 'community')),
  version       text,
  is_pinned     boolean NOT NULL DEFAULT false,
  is_published  boolean NOT NULL DEFAULT false,
  author_id     uuid NOT NULL REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Published announcements are viewable by everyone"
  ON public.announcements FOR SELECT
  USING (
    is_published = true
    OR exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE POLICY "Admins can insert announcements"
  ON public.announcements FOR INSERT
  TO authenticated
  WITH CHECK (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE POLICY "Admins can update announcements"
  ON public.announcements FOR UPDATE
  TO authenticated
  USING (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  )
  WITH CHECK (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE POLICY "Admins can delete announcements"
  ON public.announcements FOR DELETE
  TO authenticated
  USING (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE INDEX IF NOT EXISTS idx_announcements_published_date
  ON public.announcements (is_published, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_announcements_category
  ON public.announcements (category);

-- ============================================================
-- 2. Announcement comments table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.announcement_comments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id  uuid NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES auth.users(id),
  display_name     text NOT NULL,
  body             text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.announcement_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Comments are viewable by everyone"
  ON public.announcement_comments FOR SELECT
  USING (true);

CREATE POLICY "Authenticated users can post comments"
  ON public.announcement_comments FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can delete comments"
  ON public.announcement_comments FOR DELETE
  TO authenticated
  USING (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE INDEX IF NOT EXISTS idx_announcement_comments_announcement
  ON public.announcement_comments (announcement_id, created_at ASC);

-- ============================================================
-- 3. Newsletter subscribers table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email           text NOT NULL UNIQUE,
  is_confirmed    boolean NOT NULL DEFAULT false,
  player_id       uuid REFERENCES auth.users(id),
  subscribed_at   timestamptz NOT NULL DEFAULT now(),
  unsubscribed_at timestamptz
);

ALTER TABLE public.newsletter_subscribers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can subscribe to the newsletter"
  ON public.newsletter_subscribers FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Admins can view newsletter subscribers"
  ON public.newsletter_subscribers FOR SELECT
  TO authenticated
  USING (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE POLICY "Admins can update newsletter subscribers"
  ON public.newsletter_subscribers FOR UPDATE
  TO authenticated
  USING (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  )
  WITH CHECK (
    exists (select 1 from public.player_profiles where id = auth.uid() and is_admin = true)
  );

CREATE INDEX IF NOT EXISTS idx_newsletter_active
  ON public.newsletter_subscribers (email) WHERE unsubscribed_at IS NULL;

-- ============================================================
-- 4. Site setting seed
-- ============================================================

INSERT INTO public.site_settings (key, value)
VALUES ('announcements_enabled', 'true'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- 5. Enable Realtime
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.announcement_comments;
