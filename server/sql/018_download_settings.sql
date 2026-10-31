-- Phase 23: Build & Distribution settings
-- Adds game_version and download_url to site_settings for the download page

INSERT INTO public.site_settings (key, value) VALUES
    ('game_version', '"0.1.0-alpha"'::jsonb),
    ('download_url', '""'::jsonb)
ON CONFLICT (key) DO NOTHING;
