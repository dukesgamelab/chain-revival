import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { RankBadge } from '../components/RankBadge'
import { StatCard } from '../components/StatCard'
import { MatchRow } from '../components/MatchRow'
import { getRankLabel, getNextRankPP, getPPProgress } from '../lib/ranks'

interface PlayerProfile {
  id: string
  display_name: string
  games_played: number
  games_won: number
  total_kills: number
  rank: number
  prestige_points: number
  regiment_id: string | null
  regiments: { name: string; tag: string } | null
}

interface MatchHistoryRow {
  id: number
  won: boolean
  draw: boolean
  team: string
  kills: number
  total_points: number
  pp_earned: number
  opponent_id: string | null
  played_at: string
}

export function Player() {
  const { id } = useParams<{ id: string }>()
  const [player, setPlayer] = useState<PlayerProfile | null>(null)
  const [matches, setMatches] = useState<MatchHistoryRow[]>([])
  const [opponentNames, setOpponentNames] = useState<Record<string, string>>({})
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!id) return

    async function load() {
      const { data } = await supabase
        .from('player_profiles')
        .select('id,display_name,games_played,games_won,total_kills,rank,prestige_points,regiment_id,regiments(name,tag)')
        .eq('id', id)
        .single()

      if (data) setPlayer(data as unknown as PlayerProfile)

      const { data: matchData } = await supabase
        .from('match_history')
        .select('id,won,draw,team,kills,total_points,pp_earned,opponent_id,played_at')
        .eq('player_id', id)
        .order('played_at', { ascending: false })
        .limit(20)

      if (matchData) {
        setMatches(matchData)
        const opIds = [...new Set(matchData.map(m => m.opponent_id).filter(Boolean))] as string[]
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
      setLoading(false)
    }

    load()

    const channel = supabase
      .channel(`player-${id}-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'player_profiles',
        filter: `id=eq.${id}`,
      } as never, (payload) => {
        setPlayer(prev => prev ? { ...prev, ...payload.new as Partial<PlayerProfile> } : prev)
      })
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'match_history',
        filter: `player_id=eq.${id}`,
      } as never, () => {
        load()
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [id])

  if (loading) {
    return <div className="max-w-4xl mx-auto px-4 py-16 text-center text-slate-500">Loading...</div>
  }

  if (!player) {
    return <div className="max-w-4xl mx-auto px-4 py-16 text-center text-slate-500">Player not found</div>
  }

  const winRate = player.games_played > 0 ? Math.round((player.games_won / player.games_played) * 100) : 0
  const nextPP = getNextRankPP(player.rank)
  const progress = getPPProgress(player.prestige_points, player.rank)

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 mb-8">
        <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 mb-6">
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <h1 className="text-3xl font-bold">{player.display_name}</h1>
              <RankBadge rank={player.rank} size="lg" />
            </div>
            {player.regiments && (
              <Link
                to={`/regiments?id=${player.regiment_id}`}
                className="text-sky-400 hover:text-sky-300 text-sm mt-1 inline-block"
              >
                [{player.regiments.tag}] {player.regiments.name}
              </Link>
            )}
          </div>
          <div className="text-right">
            <div className="text-2xl font-bold text-sky-400">{player.prestige_points.toLocaleString()} PP</div>
            <div className="text-sm text-slate-400">{getRankLabel(player.rank)}</div>
          </div>
        </div>

        <div className="mb-4">
          <div className="flex justify-between text-xs text-slate-400 mb-1">
            <span>{getRankLabel(player.rank)}</span>
            <span>{nextPP ? `${getRankLabel(player.rank + 1)} at ${nextPP.toLocaleString()} PP` : 'Max Rank'}</span>
          </div>
          <div className="h-2 bg-slate-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-sky-600 to-sky-400 rounded-full transition-all duration-500"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
          <StatCard label="Games" value={player.games_played} />
          <StatCard label="Wins" value={player.games_won} />
          <StatCard label="Win Rate" value={`${winRate}%`} />
          <StatCard label="Kills" value={player.total_kills} />
          <StatCard label="PP" value={player.prestige_points.toLocaleString()} />
        </div>
      </div>

      <h2 className="text-xl font-bold mb-4">Recent Matches</h2>
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
    </div>
  )
}
