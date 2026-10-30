import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { RankBadge } from '../components/RankBadge'

interface Regiment {
  id: string
  name: string
  tag: string
  description: string
  website_url: string | null
  co_id: string | null
  xo_id: string | null
  max_members: number
}

interface Member {
  player_id: string
  assigned_rank: string | null
  display_name: string
  rank: number
  prestige_points: number
}

export function Regiments() {
  const [searchParams, setSearchParams] = useSearchParams()
  const selectedId = searchParams.get('id')
  const [regiments, setRegiments] = useState<Regiment[]>([])
  const [memberCounts, setMemberCounts] = useState<Record<string, number>>({})
  const [coNames, setCoNames] = useState<Record<string, string>>({})
  const [selected, setSelected] = useState<Regiment | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function loadRegiments() {
      const { data } = await supabase
        .from('regiments')
        .select('id,name,tag,description,website_url,co_id,xo_id,max_members')
        .eq('status', 'active')
        .order('name')

      if (!data) { setLoading(false); return }
      setRegiments(data)

      const coIds = [...new Set(data.map(r => r.co_id).filter(Boolean))] as string[]
      if (coIds.length > 0) {
        const { data: profiles } = await supabase
          .from('player_profiles')
          .select('id,display_name')
          .in('id', coIds)
        if (profiles) {
          const map: Record<string, string> = {}
          for (const p of profiles) map[p.id] = p.display_name
          setCoNames(map)
        }
      }

      const counts: Record<string, number> = {}
      for (const r of data) {
        const { count } = await supabase
          .from('regiment_members')
          .select('player_id', { count: 'exact', head: true })
          .eq('regiment_id', r.id)
        counts[r.id] = count ?? 0
      }
      setMemberCounts(counts)
      setLoading(false)
    }

    loadRegiments()
  }, [])

  useEffect(() => {
    if (!selectedId) { setSelected(null); return }

    async function loadDetail() {
      const reg = regiments.find(r => r.id === selectedId)
      if (!reg) {
        const { data } = await supabase
          .from('regiments')
          .select('id,name,tag,description,website_url,co_id,xo_id,max_members')
          .eq('id', selectedId)
          .single()
        if (data) setSelected(data)
      } else {
        setSelected(reg)
      }

      const { data: memberData } = await supabase
        .from('regiment_members')
        .select('player_id,assigned_rank')
        .eq('regiment_id', selectedId)

      if (memberData && memberData.length > 0) {
        const playerIds = memberData.map(m => m.player_id)
        const { data: profiles } = await supabase
          .from('player_profiles')
          .select('id,display_name,rank,prestige_points')
          .in('id', playerIds)

        if (profiles) {
          const merged: Member[] = memberData.map(m => {
            const p = profiles.find(pr => pr.id === m.player_id)
            return {
              player_id: m.player_id,
              assigned_rank: m.assigned_rank,
              display_name: p?.display_name ?? 'Unknown',
              rank: p?.rank ?? 0,
              prestige_points: p?.prestige_points ?? 0,
            }
          })
          setMembers(merged)
        }
      } else {
        setMembers([])
      }
    }

    loadDetail()
  }, [selectedId, regiments])

  if (selected) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8">
        <button
          onClick={() => setSearchParams({})}
          className="text-sky-400 hover:text-sky-300 text-sm mb-6 inline-flex items-center gap-1"
        >
          &larr; Back to Regiments
        </button>

        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 mb-8">
          <div className="flex items-center gap-3 mb-4">
            <span className="text-2xl font-bold text-amber-400">[{selected.tag}]</span>
            <h1 className="text-3xl font-bold">{selected.name}</h1>
          </div>
          {selected.description && (
            <p className="text-slate-400 mb-4">{selected.description}</p>
          )}
          {selected.website_url && (
            <a href={selected.website_url} target="_blank" rel="noopener noreferrer" className="text-sky-400 hover:underline text-sm">
              {selected.website_url}
            </a>
          )}
          <div className="flex gap-6 mt-4 text-sm text-slate-400">
            <span>Members: {members.length}/{selected.max_members}</span>
            {selected.co_id && <span>CO: {coNames[selected.co_id] ?? 'Unknown'}</span>}
          </div>
        </div>

        <h2 className="text-xl font-bold mb-4">Roster</h2>
        <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700 text-slate-400 text-left">
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3">Rank</th>
                <th className="px-4 py-3">Role</th>
                <th className="px-4 py-3 text-center">PP</th>
              </tr>
            </thead>
            <tbody>
              {members.map(m => {
                let role = ''
                if (m.player_id === selected.co_id) role = 'CO'
                else if (m.player_id === selected.xo_id) role = 'XO'
                else if (m.assigned_rank) role = m.assigned_rank

                return (
                  <tr key={m.player_id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                    <td className="px-4 py-3">
                      <Link to={`/player/${m.player_id}`} className="text-sky-400 hover:text-sky-300 hover:underline">
                        {m.display_name}
                      </Link>
                    </td>
                    <td className="px-4 py-3"><RankBadge rank={m.rank} /></td>
                    <td className="px-4 py-3">
                      {role && (
                        <span className={`text-xs font-semibold px-2 py-0.5 rounded ${
                          role === 'CO' || role === 'XO' ? 'bg-amber-900/50 text-amber-300' : 'bg-slate-700 text-slate-300'
                        }`}>
                          {role}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-center text-sky-400">{m.prestige_points.toLocaleString()}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-6">Regiments</h1>

      {loading ? (
        <div className="text-center text-slate-500 py-16">Loading...</div>
      ) : regiments.length === 0 ? (
        <div className="text-center text-slate-500 py-16">No active regiments</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {regiments.map(r => (
            <button
              key={r.id}
              onClick={() => setSearchParams({ id: r.id })}
              className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5 text-left hover:border-slate-600 transition-colors"
            >
              <div className="flex items-center gap-2 mb-2">
                <span className="text-amber-400 font-bold">[{r.tag}]</span>
                <span className="text-lg font-semibold text-white">{r.name}</span>
              </div>
              {r.description && (
                <p className="text-sm text-slate-400 line-clamp-2 mb-3">{r.description}</p>
              )}
              <div className="flex gap-4 text-xs text-slate-500">
                <span>{memberCounts[r.id] ?? '?'}/{r.max_members} members</span>
                {r.co_id && <span>CO: {coNames[r.co_id] ?? '...'}</span>}
              </div>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
