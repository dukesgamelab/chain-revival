import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { ReplayViewer } from '../components/ReplayViewer'

interface MatchPlayer {
  player_id: string
  team: string
  won: boolean
  draw: boolean
  kills: number
  kill_points: number
  terrain_points: number
  total_points: number
  pp_earned: number
  display_name?: string
}

interface ReplayRow {
  match_id: string
  map_id: string
  map_width: number
  map_height: number
  team_size: number
  initial_state: unknown
  events: unknown[]
  duration_ms: number
  event_count: number
}

interface MatchMeta {
  match_id: string
  map_id: string | null
  team_size: number | null
  duration_seconds: number | null
  end_cause: string
  played_at: string
}

export function MatchDetail() {
  const { id } = useParams<{ id: string }>()
  const [players, setPlayers] = useState<MatchPlayer[]>([])
  const [replay, setReplay] = useState<ReplayRow | null>(null)
  const [meta, setMeta] = useState<MatchMeta | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!id) return

    async function load() {
      const { data: historyData } = await supabase
        .from('match_history')
        .select('player_id,team,won,draw,kills,kill_points,terrain_points,total_points,pp_earned,map_id,team_size,duration_seconds,end_cause,played_at')
        .eq('match_id', id)

      if (historyData && historyData.length > 0) {
        const row = historyData[0]
        setMeta({
          match_id: id!,
          map_id: row.map_id,
          team_size: row.team_size,
          duration_seconds: row.duration_seconds,
          end_cause: row.end_cause,
          played_at: row.played_at,
        })

        const playerIds = historyData.map(h => h.player_id)
        const { data: profiles } = await supabase
          .from('player_profiles')
          .select('id,display_name')
          .in('id', playerIds)

        const nameMap: Record<string, string> = {}
        if (profiles) {
          for (const p of profiles) nameMap[p.id] = p.display_name
        }

        setPlayers(historyData.map(h => ({
          ...h,
          display_name: nameMap[h.player_id] ?? 'Unknown',
        })))
      }

      const { data: replayData } = await supabase
        .from('match_replays')
        .select('*')
        .eq('match_id', id)
        .single()

      if (replayData) {
        setReplay(replayData as ReplayRow)
      }

      setLoading(false)
    }

    load()
  }, [id])

  if (loading) {
    return <div className="max-w-5xl mx-auto px-4 py-16 text-center text-slate-500">Loading match...</div>
  }

  if (players.length === 0) {
    return (
      <div className="max-w-5xl mx-auto px-4 py-16 text-center">
        <div className="text-slate-500 mb-4">Match not found</div>
        <Link to="/leaderboard" className="text-sky-400 hover:text-sky-300">Back to Leaderboard</Link>
      </div>
    )
  }

  const usaPlayers = players.filter(p => p.team === 'USA')
  const gerPlayers = players.filter(p => p.team === 'GERMANY')
  const winner = players.find(p => p.won)?.team ?? (players[0]?.draw ? 'Draw' : '—')
  const date = meta ? new Date(meta.played_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }) : ''

  function formatDuration(sec: number) {
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  function copyLink() {
    navigator.clipboard.writeText(window.location.href)
  }

  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      {/* Match header */}
      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 mb-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-4">
          <div>
            <h1 className="text-2xl font-bold mb-1">Match Detail</h1>
            <div className="flex flex-wrap gap-3 text-sm text-slate-400">
              {meta?.map_id && <span className="bg-slate-700/60 px-2 py-0.5 rounded">{meta.map_id}</span>}
              {meta?.end_cause && <span className="bg-slate-700/60 px-2 py-0.5 rounded capitalize">{meta.end_cause}</span>}
              {meta?.duration_seconds != null && <span className="bg-slate-700/60 px-2 py-0.5 rounded">{formatDuration(meta.duration_seconds)}</span>}
              {meta?.team_size && <span className="bg-slate-700/60 px-2 py-0.5 rounded">{meta.team_size}v{meta.team_size}</span>}
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-sm text-slate-500">{date}</span>
            <button
              onClick={copyLink}
              className="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-slate-300 text-sm rounded-lg transition-colors"
            >
              Share
            </button>
          </div>
        </div>

        <div className={`text-center text-lg font-bold mb-4 ${
          winner === 'Draw' ? 'text-yellow-400' : winner === 'USA' ? 'text-sky-400' : 'text-red-400'
        }`}>
          {winner === 'Draw' ? 'Draw' : `${winner} Victory`}
        </div>

        {/* Scoreboard */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <TeamCard team="USA" players={usaPlayers} won={usaPlayers.some(p => p.won)} />
          <TeamCard team="GERMANY" players={gerPlayers} won={gerPlayers.some(p => p.won)} />
        </div>
      </div>

      {/* Replay viewer */}
      {replay && (
        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 mb-6">
          <h2 className="text-xl font-bold mb-4">Match Replay</h2>
          <ReplayViewer
            initialState={replay.initial_state as ReplayViewerState}
            events={replay.events as ReplayEvent[]}
            durationMs={replay.duration_ms}
          />
        </div>
      )}

      {/* Event log */}
      {replay && (
        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
          <h2 className="text-xl font-bold mb-4">Combat Log</h2>
          <EventLog events={replay.events as ReplayEvent[]} />
        </div>
      )}
    </div>
  )
}

function TeamCard({ team, players, won }: { team: string; players: MatchPlayer[]; won: boolean }) {
  const borderColor = team === 'USA' ? 'border-sky-500/30' : 'border-red-500/30'
  const labelColor = team === 'USA' ? 'text-sky-400' : 'text-red-400'

  const totalKills = players.reduce((s, p) => s + p.kills, 0)
  const totalPoints = players.reduce((s, p) => s + p.total_points, 0)

  return (
    <div className={`border ${borderColor} rounded-lg p-4 ${won ? 'bg-slate-700/30' : 'bg-slate-800/30'}`}>
      <div className="flex justify-between items-center mb-3">
        <span className={`font-bold ${labelColor}`}>{team}</span>
        {won && <span className="text-xs bg-green-600/30 text-green-400 px-2 py-0.5 rounded">WINNER</span>}
      </div>
      <div className="space-y-2">
        {players.map(p => (
          <div key={p.player_id} className="flex justify-between items-center text-sm">
            <Link to={`/player/${p.player_id}`} className="text-slate-300 hover:text-sky-400 transition-colors">
              {p.display_name}
            </Link>
            <div className="flex gap-4 text-slate-400">
              <span>{p.kills} kills</span>
              <span>{p.total_points} pts</span>
              <span className="text-sky-400">+{p.pp_earned} PP</span>
            </div>
          </div>
        ))}
      </div>
      <div className="flex justify-between mt-3 pt-3 border-t border-slate-700/50 text-xs text-slate-500">
        <span>Total: {totalKills} kills</span>
        <span>{totalPoints} points</span>
      </div>
    </div>
  )
}

interface ReplayEvent {
  t: number
  type: string
  data: Record<string, unknown>
}

interface ReplayViewerState {
  map: {
    id: string
    width: number
    height: number
    blockedTiles: Array<{ x: number; y: number }>
    tiles: Array<{ x: number; y: number; type: string; blocksLos: boolean; cover: number }>
    victoryPoints: Array<{ x: number; y: number; holder: string }>
  }
  soldiers: Array<{
    id: number
    teamId: number
    position: { x: number; y: number }
    facing: { x: number; y: number }
  }>
}

function EventLog({ events }: { events: ReplayEvent[] }) {
  const significantEvents = events.filter(e =>
    ['combat_shots', 'grenade_explode', 'deployment_ended', 'match_ended'].includes(e.type)
  )

  if (significantEvents.length === 0) {
    return <div className="text-slate-500 text-sm">No combat events recorded</div>
  }

  return (
    <div className="max-h-80 overflow-y-auto space-y-1 text-sm">
      {significantEvents.map((event, i) => (
        <EventRow key={i} event={event} />
      ))}
    </div>
  )
}

function EventRow({ event }: { event: ReplayEvent }) {
  const time = formatMs(event.t)
  const d = event.data

  switch (event.type) {
    case 'combat_shots': {
      const shots = (d.shots as Array<Record<string, unknown>>) ?? []
      const kills = shots.filter(s => s.killed)
      const hits = shots.filter(s => s.hit && !s.killed)
      const parts: string[] = []
      if (kills.length > 0) parts.push(`${kills.length} kill${kills.length > 1 ? 's' : ''}`)
      if (hits.length > 0) parts.push(`${hits.length} hit${hits.length > 1 ? 's' : ''}`)
      if (parts.length === 0) parts.push(`${shots.length} shot${shots.length > 1 ? 's' : ''} fired`)
      return (
        <div className="flex gap-3 py-1 px-2 rounded hover:bg-slate-700/30">
          <span className="text-slate-500 w-14 shrink-0 font-mono">{time}</span>
          <span className="text-orange-400 w-5 shrink-0">{'>'}</span>
          <span className="text-slate-300">{parts.join(', ')}</span>
        </div>
      )
    }
    case 'grenade_explode': {
      const killed = (d.killed as unknown[])?.length ?? 0
      const stunned = (d.stunned as unknown[])?.length ?? 0
      const parts = ['Grenade exploded']
      if (killed > 0) parts.push(`${killed} killed`)
      if (stunned > 0) parts.push(`${stunned} stunned`)
      return (
        <div className="flex gap-3 py-1 px-2 rounded hover:bg-slate-700/30">
          <span className="text-slate-500 w-14 shrink-0 font-mono">{time}</span>
          <span className="text-yellow-400 w-5 shrink-0">*</span>
          <span className="text-slate-300">{parts.join(' — ')}</span>
        </div>
      )
    }
    case 'deployment_ended':
      return (
        <div className="flex gap-3 py-1 px-2 rounded bg-slate-700/20">
          <span className="text-slate-500 w-14 shrink-0 font-mono">{time}</span>
          <span className="text-green-400 w-5 shrink-0">!</span>
          <span className="text-green-400 font-semibold">Combat begins</span>
        </div>
      )
    case 'match_ended':
      return (
        <div className="flex gap-3 py-1 px-2 rounded bg-slate-700/20">
          <span className="text-slate-500 w-14 shrink-0 font-mono">{time}</span>
          <span className="text-red-400 w-5 shrink-0">X</span>
          <span className="text-red-400 font-semibold">Match ended</span>
        </div>
      )
    default:
      return null
  }
}

function formatMs(ms: number): string {
  const totalSec = Math.floor(ms / 1000)
  const m = Math.floor(totalSec / 60)
  const s = totalSec % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}
