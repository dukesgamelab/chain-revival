-- Phase 22: Website Integration
-- Adds site_settings (feature toggles), ban_appeals, and Realtime on key tables

-- ── site_settings ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.site_settings (
    key   text PRIMARY KEY,
    value jsonb NOT NULL DEFAULT 'true'::jsonb,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    updated_by  uuid REFERENCES auth.users(id)
);

ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read site settings"
    ON public.site_settings FOR SELECT
    USING (true);

CREATE POLICY "Admins can update site settings"
    ON public.site_settings FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.player_profiles
            WHERE id = auth.uid() AND is_admin = true
        )
    );

-- Seed default settings
INSERT INTO public.site_settings (key, value) VALUES
    ('chat_enabled', 'true'::jsonb),
    ('regiments_enabled', 'true'::jsonb),
    ('download_enabled', 'true'::jsonb),
    ('leaderboard_enabled', 'true'::jsonb),
    ('registration_enabled', 'true'::jsonb),
    ('appeal_enabled', 'true'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ── ban_appeals ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ban_appeals (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id    uuid NOT NULL REFERENCES auth.users(id),
    email        text NOT NULL,
    appeal_text  text NOT NULL,
    status       text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'approved', 'denied')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    reviewed_at  timestamptz,
    reviewed_by  uuid REFERENCES auth.users(id)
);

ALTER TABLE public.ban_appeals ENABLE ROW LEVEL SECURITY;

-- Anyone can insert (banned players may not be authenticated)
CREATE POLICY "Anyone can submit a ban appeal"
    ON public.ban_appeals FOR INSERT
    WITH CHECK (true);

-- Only admins and moderators can read appeals
CREATE POLICY "Admins and moderators can read ban appeals"
    ON public.ban_appeals FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.player_profiles
            WHERE id = auth.uid() AND (is_admin = true OR is_moderator = true)
        )
    );

-- Only admins and moderators can update appeals (approve/deny)
CREATE POLICY "Admins and moderators can update ban appeals"
    ON public.ban_appeals FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.player_profiles
            WHERE id = auth.uid() AND (is_admin = true OR is_moderator = true)
        )
    );

-- ── Enable Realtime on website-relevant tables ──────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.player_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.match_history;
ALTER PUBLICATION supabase_realtime ADD TABLE public.regiments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.regiment_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.site_settings;
