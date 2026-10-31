export const RANK_LABELS = ['PVT', 'PFC', 'CPL', 'SGT', 'SSG', 'SFC', 'MSG', '2LT', '1LT', 'CPT', 'MAJ', 'LT COL', 'COL'] as const

export const PP_THRESHOLDS = [0, 500, 2500, 7500, 17500, 35500, 65500, 115500, 195500, 315500]

const ASSIGNED_RANK_INDEX: Record<string, number> = {
  '1LT': 8, 'CPT': 9, 'MAJ': 10, 'LT COL': 11, 'COL': 12,
}

export function getRankLabel(rankIndex: number): string {
  return RANK_LABELS[Math.max(0, Math.min(rankIndex, RANK_LABELS.length - 1))]
}

export function getRankTier(rankIndex: number): 'enlisted' | 'nco' | 'officer' {
  if (rankIndex >= 7) return 'officer'
  if (rankIndex >= 2) return 'nco'
  return 'enlisted'
}

export function getDisplayRank(ppRank: number, assignedRank: string | null): number {
  if (!assignedRank) return ppRank
  return ASSIGNED_RANK_INDEX[assignedRank] ?? ppRank
}

export function getNextRankPP(rankIndex: number): number | null {
  if (rankIndex >= PP_THRESHOLDS.length - 1) return null
  return PP_THRESHOLDS[rankIndex + 1]
}

export function getPPProgress(pp: number, rankIndex: number): number {
  const currentThreshold = PP_THRESHOLDS[rankIndex] ?? 0
  const nextThreshold = PP_THRESHOLDS[rankIndex + 1]
  if (nextThreshold == null) return 100
  const range = nextThreshold - currentThreshold
  if (range <= 0) return 100
  return Math.min(100, ((pp - currentThreshold) / range) * 100)
}
