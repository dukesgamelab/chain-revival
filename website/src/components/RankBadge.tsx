import { getRankLabel, getRankTier } from '../lib/ranks'

const tierColors = {
  enlisted: 'bg-slate-600 text-slate-200',
  nco: 'bg-blue-900 text-blue-300',
  officer: 'bg-amber-900 text-amber-300',
}

export function RankBadge({ rank, size = 'sm' }: { rank: number; size?: 'sm' | 'lg' }) {
  const tier = getRankTier(rank)
  const label = getRankLabel(rank)
  const sizeClass = size === 'lg' ? 'px-3 py-1 text-sm' : 'px-2 py-0.5 text-xs'

  return (
    <span className={`inline-flex items-center rounded font-semibold tracking-wide ${tierColors[tier]} ${sizeClass}`}>
      {label}
    </span>
  )
}
