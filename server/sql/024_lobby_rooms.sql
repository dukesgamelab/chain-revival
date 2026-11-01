-- Phase 37: Lobby Room Grid
-- Adds room_number to lobbies for the persistent 8-room grid.

-- 1. Add room_number column (nullable — NULL means legacy rows)
ALTER TABLE public.lobbies
  ADD COLUMN IF NOT EXISTS room_number integer;

-- 2. Only one active lobby per room at a time.
CREATE UNIQUE INDEX IF NOT EXISTS idx_lobbies_active_room
  ON public.lobbies (room_number)
  WHERE status IN ('waiting', 'in_progress') AND room_number IS NOT NULL;

-- 3. Room numbers must be 1-8 when set.
ALTER TABLE public.lobbies
  ADD CONSTRAINT chk_room_number CHECK (room_number IS NULL OR (room_number >= 1 AND room_number <= 8));
