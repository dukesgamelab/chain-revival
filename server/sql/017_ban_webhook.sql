-- Phase 22b: Ban notification webhook
-- Triggers the ban-notification Edge Function when a player is banned

-- Enable pg_net if not already enabled (for HTTP requests from triggers)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Function that fires the Edge Function via HTTP
CREATE OR REPLACE FUNCTION public.notify_ban()
RETURNS trigger AS $$
DECLARE
  edge_function_url text;
  service_role_key text;
BEGIN
  -- Only fire when is_banned changes from false to true
  IF NEW.is_banned = true AND (OLD.is_banned IS DISTINCT FROM true) THEN
    edge_function_url := current_setting('app.settings.supabase_url', true)
      || '/functions/v1/ban-notification';
    service_role_key := current_setting('app.settings.service_role_key', true);

    PERFORM extensions.http_post(
      edge_function_url,
      jsonb_build_object(
        'type', 'UPDATE',
        'record', row_to_json(NEW)::jsonb
      )::text,
      'application/json',
      ARRAY[
        extensions.http_header('Authorization', 'Bearer ' || service_role_key)
      ]
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_player_banned
  AFTER UPDATE OF is_banned ON public.player_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_ban();
