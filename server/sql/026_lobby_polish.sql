-- Phase 38: Lobby Polish
-- Adds host_regiment_id, match_length_sec to lobbies; expands room limit; adds max_rooms setting.

-- 1. Host regiment ID for regimental room enforcement
ALTER TABLE public.lobbies
  ADD COLUMN IF NOT EXISTS host_regiment_id uuid;

-- 2. Match length in seconds (default 900 = 15 minutes)
ALTER TABLE public.lobbies
  ADD COLUMN IF NOT EXISTS match_length_sec integer DEFAULT 900;

-- 3. Expand room number limit from 8 to 16
ALTER TABLE public.lobbies DROP CONSTRAINT IF EXISTS chk_room_number;
ALTER TABLE public.lobbies
  ADD CONSTRAINT chk_room_number CHECK (room_number IS NULL OR (room_number >= 1 AND room_number <= 16));

-- 4. Max rooms site setting
INSERT INTO public.site_settings (key, value)
VALUES ('max_rooms', '8')
ON CONFLICT (key) DO NOTHING;
