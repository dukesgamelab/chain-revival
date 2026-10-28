/**
 * Supabase service-role client for server-side writes.
 * Uses raw fetch against the Supabase REST API (no SDK dependency).
 *
 * Requires env vars:
 *   SUPABASE_URL            - e.g. https://xyz.supabase.co
 *   SUPABASE_SERVICE_ROLE_KEY - the service_role secret from Supabase dashboard
 */

const SUPABASE_URL = process.env.SUPABASE_URL ?? "";
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

function isConfigured(): boolean {
  return SUPABASE_URL !== "" && SERVICE_ROLE_KEY !== "";
}

function headers(): Record<string, string> {
  return {
    "Content-Type": "application/json",
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
  };
}

export interface MatchResultParams {
  matchId: string;
  player1Id: string;
  player1Team: string;
  player1Won: boolean;
  player1Draw: boolean;
  player1Kill: number;
  player1Terrain: number;
  player1Total: number;
  player1Kills: number;
  player2Id: string;
  player2Team: string;
  player2Won: boolean;
  player2Draw: boolean;
  player2Kill: number;
  player2Terrain: number;
  player2Total: number;
  player2Kills: number;
  endCause: string;
}

/**
 * Call the record_match_result RPC function in Supabase.
 * This atomically inserts match_history rows and increments
 * games_played/games_won on player_profiles.
 */
export async function recordMatchResult(params: MatchResultParams): Promise<void> {
  if (!isConfigured()) {
    console.warn("[Supabase] Not configured (missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY). Match result not recorded.");
    return;
  }

  const body = {
    p_match_id: params.matchId,
    p_player1_id: params.player1Id,
    p_player1_team: params.player1Team,
    p_player1_won: params.player1Won,
    p_player1_draw: params.player1Draw,
    p_player1_kill: params.player1Kill,
    p_player1_terrain: params.player1Terrain,
    p_player1_total: params.player1Total,
    p_player1_kills: params.player1Kills,
    p_player2_id: params.player2Id,
    p_player2_team: params.player2Team,
    p_player2_won: params.player2Won,
    p_player2_draw: params.player2Draw,
    p_player2_kill: params.player2Kill,
    p_player2_terrain: params.player2Terrain,
    p_player2_total: params.player2Total,
    p_player2_kills: params.player2Kills,
    p_end_cause: params.endCause,
  };

  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/record_match_result`, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      console.error("[Supabase] record_match_result failed (%d): %s", res.status, text);
    } else {
      console.log("[Supabase] Match result recorded for match %s", params.matchId);
    }
  } catch (err) {
    console.error("[Supabase] record_match_result error:", err);
  }
}
