import { Link } from 'react-router-dom'

interface MatchRowProps {
  matchId?: string | null
  won: boolean
  draw: boolean
  team: string
  kills: number
  totalPoints: number
  ppEarned: number
  opponentName: string | null
  opponentId: string | null
  playedAt: string
}

export function MatchRow({ matchId, won, draw, team, kills, totalPoints, ppEarned, opponentName, opponentId, playedAt }: MatchRowProps) {
  const result = draw ? 'Draw' : won ? 'Win' : 'Loss'
  const resultColor = draw ? 'text-draw' : won ? 'text-win' : 'text-loss'
  const date = new Date(playedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  const hasReplay = matchId && matchId !== 'local-mp-1'

  return (
    <tr className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
      <td className={`px-4 py-3 font-semibold ${resultColor}`}>
        {hasReplay ? (
          <Link to={`/match/${matchId}`} className={`${resultColor} underline decoration-dotted hover:decoration-solid`}>{result}</Link>
        ) : result}
      </td>
      <td className="px-4 py-3 text-slate-300">{team}</td>
      <td className="px-4 py-3 text-center">{kills}</td>
      <td className="px-4 py-3 text-center">{totalPoints}</td>
      <td className="px-4 py-3 text-center text-sky-400">+{ppEarned}</td>
      <td className="px-4 py-3">
        {opponentId ? (
          <Link to={`/player/${opponentId}`} className="text-sky-400 hover:text-sky-300 hover:underline">
            {opponentName ?? 'Unknown'}
          </Link>
        ) : (
          <span className="text-slate-500">—</span>
        )}
      </td>
      <td className="px-4 py-3 text-slate-500 text-sm">{date}</td>
    </tr>
  )
}
