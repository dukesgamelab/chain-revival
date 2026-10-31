import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { getDisplayRank } from '../lib/ranks'
import { RankBadge } from '../components/RankBadge'
import { MatchRow } from '../components/MatchRow'

interface PlayerRow {
  id: string
  display_name: string
  games_won: number
  games_played: number
  total_kills: number
  rank: number
}

interface MatchHistoryRow {
  id: number
  match_id: string
  won: boolean
  draw: boolean
  team: string
  kills: number
  total_points: number
  pp_earned: number
  opponent_id: string | null
  played_at: string
}

interface AllMatchRow {
  match_id: string
  played_at: string
  players: Array<{ player_id: string; display_name: string; team: string; won: boolean; draw: boolean; kills: number; total_points: number }>
}

export function Leaderboard({ userId }: { userId: string | null }) {
  const [tab, setTab] = useState<'top' | 'matches' | 'all'>('top')
  const [players, setPlayers] = useState<PlayerRow[]>([])
  const [matches, setMatches] = useState<MatchHistoryRow[]>([])
  const [allMatches, setAllMatches] = useState<AllMatchRow[]>([])
  const [opponentNames, setOpponentNames] = useState<Record<string, string>>({})
  const [assignedRanks, setAssignedRanks] = useState<Record<string, string>>({})
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [searchTimeout, setSearchTimeout] = useState<ReturnType<typeof setTimeout> | null>(null)

  const fetchLeaderboard = useCallback(async (query?: string) => {
    setLoading(true)
    let req = supabase
      .from('player_profiles')
      .select('id,display_name,games_won,games_played,total_kills,rank')

    if (query) {
      req = req.ilike('display_name', `*${query}*`)
    }

    req = req.order('games_won', { ascending: false }).order('games_played', { ascending: true }).limit(50)

    const { data } = await req
    if (data) {
      setPlayers(data)
      const ids = data.map(p => p.id)
      if (ids.length > 0) {
        const { data: regMembers } = await supabase
          .from('regiment_members')
          .select('player_id,assigned_rank')
          .in('player_id', ids)
          .not('assigned_rank', 'is', null)
        if (regMembers) {
          const map: Record<string, string> = {}
          for (const m of regMembers) if (m.assigned_rank) map[m.player_id] = m.assigned_rank
          setAssignedRanks(map)
        }
      }
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchLeaderboard()

    const channel = supabase
      .channel(`leaderboard-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'player_profiles',
      } as never, () => {
        if (!search) fetchLeaderboard()
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [fetchLeaderboard, search])

  function handleSearch(value: string) {
    setSearch(value)
    if (searchTimeout) clearTimeout(searchTimeout)
    setSearchTimeout(setTimeout(() => fetchLeaderboard(value || undefined), 300))
  }

  async function fetchMatches() {
    if (!userId) return
    const { data } = await supabase
      .from('match_history')
      .select('id,match_id,won,draw,team,kills,total_points,pp_earned,opponent_id,played_at')
      .eq('player_id', userId)
      .order('played_at', { ascending: false })
      .limit(20)

    if (data) {
      setMatches(data)
      const opIds = [...new Set(data.map(m => m.opponent_id).filter(Boolean))] as string[]
      if (opIds.length > 0) {
        const { data: profiles } = await supabase
          .from('player_profiles')
          .select('id,display_name')
          .in('id', opIds)
        if (profiles) {
          const map: Record<string, string> = {}
          for (const p of profiles) map[p.id] = p.display_name
          setOpponentNames(map)
        }
      }
    }
  }

  async function fetchAllMatches() {
    setLoading(true)
    const { data } = await supabase
      .from('match_history')
      .select('match_id,player_id,won,draw,team,kills,total_points,played_at')
      .neq('match_id', 'local-mp-1')
      .order('played_at', { ascending: false })
      .limit(200)

    if (data && data.length > 0) {
      const playerIds = [...new Set(data.map(r => r.player_id))]
      const { data: profiles } = await supabase
        .from('player_profiles')
        .select('id,display_name')
        .in('id', playerIds)
      const nameMap: Record<string, string> = {}
      if (profiles) for (const p of profiles) nameMap[p.id] = p.display_name

      const grouped: Record<string, AllMatchRow> = {}
      for (const row of data) {
        if (!grouped[row.match_id]) {
          grouped[row.match_id] = { match_id: row.match_id, played_at: row.played_at, players: [] }
        }
        grouped[row.match_id].players.push({
          player_id: row.player_id,
          display_name: nameMap[row.player_id] ?? 'Unknown',
          team: row.team,
          won: row.won,
          draw: row.draw,
          kills: row.kills,
          total_points: row.total_points,
        })
      }
      setAllMatches(Object.values(grouped))
    } else {
      setAllMatches([])
    }
    setLoading(false)
  }

  useEffect(() => {
    if (tab === 'matches' && userId) fetchMatches()
    if (tab === 'all') fetchAllMatches()
  }, [tab, userId])

  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-6">Leaderboard</h1>

      <div className="flex items-center gap-4 mb-6">
        <div className="flex rounded-lg bg-slate-800 p-1">
          <button
            onClick={() => setTab('top')}
            className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
              tab === 'top' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'
            }`}
          >
            Top Players
          </button>
          <button
            onClick={() => setTab('all')}
            className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
              tab === 'all' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'
            }`}
          >
            All Matches
          </button>
          {userId && (
            <button
              onClick={() => setTab('matches')}
              className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
                tab === 'matches' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'
              }`}
            >
              My Matches
            </button>
          )}
        </div>

        {tab === 'top' && (
          <input
            type="text"
            value={search}
            onChange={e => handleSearch(e.target.value)}
            placeholder="Search players..."
            className="bg-slate-800 border border-slate-700 rounded-lg px-4 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-500 w-64"
          />
        )}
      </div>

      {tab === 'top' && (
        <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700 text-slate-400 text-left">
                <th className="px-4 py-3 w-12">#</th>
                <th className="px-4 py-3">Player</th>
                <th className="px-4 py-3">Rank</th>
                <th className="px-4 py-3 text-center">Wins</th>
                <th className="px-4 py-3 text-center">Played</th>
                <th className="px-4 py-3 text-center">Kills</th>
                <th className="px-4 py-3 text-center">Win %</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={7} className="px-4 py-8 text-center text-slate-500">Loading...</td></tr>
              ) : players.length === 0 ? (
                <tr><td colSpan={7} className="px-4 py-8 text-center text-slate-500">No players found</td></tr>
              ) : (
                players.map((p, i) => (
                  <tr key={p.id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                    <td className="px-4 py-3 text-slate-500 font-mono">{i + 1}</td>
                    <td className="px-4 py-3">
                      <Link to={`/player/${p.id}`} className="text-sky-400 hover:text-sky-300 hover:underline font-medium">
                        {p.display_name || 'Unknown'}
                      </Link>
                    </td>
                    <td className="px-4 py-3"><RankBadge rank={getDisplayRank(p.rank, assignedRanks[p.id] ?? null)} /></td>
                    <td className="px-4 py-3 text-center text-white font-medium">{p.games_won}</td>
                    <td className="px-4 py-3 text-center text-slate-300">{p.games_played}</td>
                    <td className="px-4 py-3 text-center text-slate-300">{p.total_kills}</td>
                    <td className="px-4 py-3 text-center text-slate-300">
                      {p.games_played > 0 ? `${Math.round((p.games_won / p.games_played) * 100)}%` : '—'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'all' && (
        <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700 text-slate-400 text-left">
                <th className="px-4 py-3">Date</th>
                <th className="px-4 py-3">Player 1</th>
                <th className="px-4 py-3 text-center">Score</th>
                <th className="px-4 py-3">Player 2</th>
                <th className="px-4 py-3 text-center">Result</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={6} className="px-4 py-8 text-center text-slate-500">Loading...</td></tr>
              ) : allMatches.length === 0 ? (
                <tr><td colSpan={6} className="px-4 py-8 text-center text-slate-500">No matches yet</td></tr>
              ) : (
                allMatches.map(m => {
                  const p1 = m.players[0]
                  const p2 = m.players[1]
                  const date = new Date(m.played_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                  const resultText = p1?.draw ? 'Draw' : p1?.won ? `${p1.display_name} wins` : p2 ? `${p2.display_name} wins` : '—'
                  const resultColor = p1?.draw ? 'text-yellow-400' : 'text-green-400'

                  return (
                    <tr key={m.match_id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                      <td className="px-4 py-3 text-slate-500 text-sm">{date}</td>
                      <td className="px-4 py-3">
                        {p1 ? (
                          <Link to={`/player/${p1.player_id}`} className="text-sky-400 hover:text-sky-300 hover:underline">
                            {p1.display_name}
                          </Link>
                        ) : '—'}
                        {p1 && <span className="text-slate-600 text-xs ml-1">({p1.team})</span>}
                      </td>
                      <td className="px-4 py-3 text-center text-slate-300 font-mono">
                        {p1?.total_points ?? 0} — {p2?.total_points ?? 0}
                      </td>
                      <td className="px-4 py-3">
                        {p2 ? (
                          <Link to={`/player/${p2.player_id}`} className="text-sky-400 hover:text-sky-300 hover:underline">
                            {p2.display_name}
                          </Link>
                        ) : '—'}
                        {p2 && <span className="text-slate-600 text-xs ml-1">({p2.team})</span>}
                      </td>
                      <td className={`px-4 py-3 text-center text-sm font-medium ${resultColor}`}>{resultText}</td>
                      <td className="px-4 py-3 text-right">
                        <Link
                          to={`/match/${m.match_id}`}
                          className="text-sky-400 hover:text-sky-300 underline decoration-dotted hover:decoration-solid text-sm"
                        >
                          View
                        </Link>
                      </td>
                    </tr>
                  )
                })
              )}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'matches' && (
        <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700 text-slate-400 text-left">
                <th className="px-4 py-3">Result</th>
                <th className="px-4 py-3">Team</th>
                <th className="px-4 py-3 text-center">Kills</th>
                <th className="px-4 py-3 text-center">Points</th>
                <th className="px-4 py-3 text-center">PP</th>
                <th className="px-4 py-3">Opponent</th>
                <th className="px-4 py-3">Date</th>
              </tr>
            </thead>
            <tbody>
              {matches.length === 0 ? (
                <tr><td colSpan={7} className="px-4 py-8 text-center text-slate-500">No matches yet</td></tr>
              ) : (
                matches.map(m => (
                  <MatchRow
                    key={m.id}
                    matchId={m.match_id}
                    won={m.won}
                    draw={m.draw}
                    team={m.team}
                    kills={m.kills}
                    totalPoints={m.total_points}
                    ppEarned={m.pp_earned}
                    opponentName={m.opponent_id ? opponentNames[m.opponent_id] ?? null : null}
                    opponentId={m.opponent_id}
                    playedAt={m.played_at}
                  />
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
