import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/AuthProvider'
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

interface JoinRequest {
  id: string
  regiment_id: string
  direction: string
  status: string
  created_at: string
  regiment_name?: string
}

export function Regiments() {
  const { user, profile } = useAuth()
  const [searchParams, setSearchParams] = useSearchParams()
  const selectedId = searchParams.get('id')
  const [regiments, setRegiments] = useState<Regiment[]>([])
  const [memberCounts, setMemberCounts] = useState<Record<string, number>>({})
  const [coNames, setCoNames] = useState<Record<string, string>>({})
  const [selected, setSelected] = useState<Regiment | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [loading, setLoading] = useState(true)

  const [myRequests, setMyRequests] = useState<JoinRequest[]>([])
  const [myInvites, setMyInvites] = useState<JoinRequest[]>([])

  const [showCreateForm, setShowCreateForm] = useState(false)
  const [createName, setCreateName] = useState('')
  const [createTag, setCreateTag] = useState('')
  const [createDesc, setCreateDesc] = useState('')
  const [createError, setCreateError] = useState('')
  const [createSuccess, setCreateSuccess] = useState('')

  const [actionError, setActionError] = useState('')
  const [actionSuccess, setActionSuccess] = useState('')

  const hasRegiment = !!profile?.regiment_id
  const isCOorXO = selected && user && (selected.co_id === user.id || selected.xo_id === user.id)
  const isMember = selected && profile?.regiment_id === selected.id

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
    if (!user) return

    async function loadMyActivity() {
      const { data } = await supabase
        .from('regiment_join_requests')
        .select('id,regiment_id,direction,status,created_at')
        .eq('player_id', user!.id)
        .eq('status', 'pending')

      if (data) {
        const regIds = [...new Set(data.map(r => r.regiment_id))]
        let regNames: Record<string, string> = {}
        if (regIds.length > 0) {
          const { data: regs } = await supabase
            .from('regiments')
            .select('id,name')
            .in('id', regIds)
          if (regs) {
            for (const r of regs) regNames[r.id] = r.name
          }
        }

        const enriched = data.map(r => ({ ...r, regiment_name: regNames[r.regiment_id] ?? 'Unknown' }))
        setMyRequests(enriched.filter(r => r.direction === 'request'))
        setMyInvites(enriched.filter(r => r.direction === 'invite'))
      }
    }

    loadMyActivity()
  }, [user])

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

  function flashAction(msg: string, isError = false) {
    if (isError) { setActionError(msg); setActionSuccess('') }
    else { setActionSuccess(msg); setActionError('') }
    setTimeout(() => { setActionError(''); setActionSuccess('') }, 3000)
  }

  async function handleApplyToJoin(regimentId: string) {
    const { error } = await supabase
      .from('regiment_join_requests')
      .insert({
        regiment_id: regimentId,
        player_id: user!.id,
        direction: 'request',
      })
    if (error) { flashAction(error.message, true); return }
    setMyRequests(prev => [...prev, {
      id: crypto.randomUUID(),
      regiment_id: regimentId,
      direction: 'request',
      status: 'pending',
      created_at: new Date().toISOString(),
      regiment_name: selected?.name ?? regiments.find(r => r.id === regimentId)?.name,
    }])
    flashAction('Application submitted!')
  }

  async function handleCancelRequest(requestId: string) {
    const { error } = await supabase
      .from('regiment_join_requests')
      .update({ status: 'cancelled', resolved_at: new Date().toISOString() })
      .eq('id', requestId)
    if (error) { flashAction(error.message, true); return }
    setMyRequests(prev => prev.filter(r => r.id !== requestId))
    flashAction('Application cancelled')
  }

  async function handleAcceptInvite(requestId: string) {
    const { error } = await supabase.rpc('accept_regiment_join', {
      p_request_id: requestId,
      p_user_id: user!.id,
    })
    if (error) { flashAction(error.message, true); return }
    setMyInvites(prev => prev.filter(r => r.id !== requestId))
    flashAction('Invite accepted! Reloading...')
    setTimeout(() => window.location.reload(), 1000)
  }

  async function handleRejectInvite(requestId: string) {
    const { error } = await supabase.rpc('reject_regiment_join', {
      p_request_id: requestId,
      p_user_id: user!.id,
    })
    if (error) { flashAction(error.message, true); return }
    setMyInvites(prev => prev.filter(r => r.id !== requestId))
    flashAction('Invite declined')
  }

  async function handleLeaveRegiment() {
    if (!confirm('Are you sure you want to leave this regiment?')) return
    const { error } = await supabase.rpc('leave_regiment', {
      p_player_id: user!.id,
    })
    if (error) { flashAction(error.message, true); return }
    flashAction('You have left the regiment. Reloading...')
    setTimeout(() => window.location.reload(), 1000)
  }

  async function handleCreateApplication() {
    setCreateError('')
    if (!createName.trim() || !createTag.trim()) {
      setCreateError('Name and tag are required')
      return
    }
    if (createTag.length > 5) {
      setCreateError('Tag must be 5 characters or less')
      return
    }

    const { error } = await supabase
      .from('regiment_applications')
      .insert({
        type: 'create',
        applicant_id: user!.id,
        regiment_name: createName.trim(),
        regiment_tag: createTag.trim().toUpperCase(),
        description: createDesc.trim(),
      })
    if (error) { setCreateError(error.message); return }
    setCreateSuccess('Regiment application submitted! An admin will review it.')
    setCreateName('')
    setCreateTag('')
    setCreateDesc('')
    setShowCreateForm(false)
  }

  const hasPendingRequestFor = (regimentId: string) =>
    myRequests.some(r => r.regiment_id === regimentId)

  // Detail view
  if (selected) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8">
        <button
          onClick={() => setSearchParams({})}
          className="text-sky-400 hover:text-sky-300 text-sm mb-6 inline-flex items-center gap-1"
        >
          &larr; Back to Regiments
        </button>

        {(actionError || actionSuccess) && (
          <div className={`mb-4 px-4 py-2 rounded-lg text-sm ${actionError ? 'bg-red-500/20 text-red-400' : 'bg-emerald-500/20 text-emerald-400'}`}>
            {actionError || actionSuccess}
          </div>
        )}

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
            {selected.co_id && <span>CO: {coNames[selected.co_id] ?? members.find(m => m.player_id === selected.co_id)?.display_name ?? 'Unknown'}</span>}
          </div>

          <div className="flex gap-2 mt-4">
            {isCOorXO && (
              <Link
                to="/regiment/manage"
                className="px-4 py-2 bg-amber-600 hover:bg-amber-500 text-white text-sm font-medium rounded-lg transition-colors inline-block"
              >
                Manage Regiment
              </Link>
            )}
            {user && !hasRegiment && !hasPendingRequestFor(selected.id) && (
              <button
                onClick={() => handleApplyToJoin(selected.id)}
                className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Apply to Join
              </button>
            )}
            {user && !hasRegiment && hasPendingRequestFor(selected.id) && (
              <button
                onClick={() => {
                  const req = myRequests.find(r => r.regiment_id === selected.id)
                  if (req) handleCancelRequest(req.id)
                }}
                className="px-4 py-2 bg-slate-600 hover:bg-slate-500 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Cancel Application
              </button>
            )}
            {isMember && !isCOorXO && selected.co_id !== user?.id && (
              <button
                onClick={handleLeaveRegiment}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Leave Regiment
              </button>
            )}
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

  // List view
  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-3xl font-bold">Regiments</h1>
        {user && !hasRegiment && (
          <button
            onClick={() => setShowCreateForm(!showCreateForm)}
            className="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors"
          >
            {showCreateForm ? 'Cancel' : 'Create Regiment'}
          </button>
        )}
      </div>

      {(actionError || actionSuccess || createSuccess) && (
        <div className={`mb-4 px-4 py-2 rounded-lg text-sm ${actionError ? 'bg-red-500/20 text-red-400' : 'bg-emerald-500/20 text-emerald-400'}`}>
          {actionError || actionSuccess || createSuccess}
        </div>
      )}

      {showCreateForm && (
        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5 mb-6">
          <h2 className="text-lg font-bold text-white mb-4">Apply to Create a Regiment</h2>
          <p className="text-sm text-slate-400 mb-4">Submit an application for admin review. Once approved, you will become the Commanding Officer.</p>
          {createError && <div className="mb-3 px-3 py-2 bg-red-500/20 text-red-400 rounded text-sm">{createError}</div>}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Regiment Name</label>
              <input
                type="text"
                value={createName}
                onChange={e => setCreateName(e.target.value)}
                placeholder="1st Infantry Division"
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-300 mb-1">Tag (max 5 chars)</label>
              <input
                type="text"
                value={createTag}
                onChange={e => setCreateTag(e.target.value.slice(0, 5))}
                placeholder="1ID"
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 uppercase"
              />
            </div>
          </div>
          <div className="mb-4">
            <label className="block text-sm font-medium text-slate-300 mb-1">Description</label>
            <textarea
              value={createDesc}
              onChange={e => setCreateDesc(e.target.value)}
              rows={3}
              placeholder="Tell us about your regiment..."
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 resize-none"
            />
          </div>
          <button
            onClick={handleCreateApplication}
            className="px-6 py-2 bg-sky-600 hover:bg-sky-500 text-white text-sm font-medium rounded-lg transition-colors"
          >
            Submit Application
          </button>
        </div>
      )}

      {myInvites.length > 0 && (
        <div className="mb-6">
          <h2 className="text-sm font-semibold text-amber-400 mb-2">Pending Invites</h2>
          <div className="space-y-2">
            {myInvites.map(inv => (
              <div key={inv.id} className="bg-amber-900/20 border border-amber-700/30 rounded-lg p-3 flex items-center justify-between">
                <span className="text-sm text-white">
                  You've been invited to join <strong>{inv.regiment_name}</strong>
                </span>
                <div className="flex gap-2">
                  <button
                    onClick={() => handleAcceptInvite(inv.id)}
                    className="px-3 py-1 bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-medium rounded-lg transition-colors"
                  >
                    Accept
                  </button>
                  <button
                    onClick={() => handleRejectInvite(inv.id)}
                    className="px-3 py-1 bg-red-600 hover:bg-red-500 text-white text-xs font-medium rounded-lg transition-colors"
                  >
                    Decline
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {myRequests.length > 0 && (
        <div className="mb-6">
          <h2 className="text-sm font-semibold text-sky-400 mb-2">Your Pending Applications</h2>
          <div className="space-y-2">
            {myRequests.map(req => (
              <div key={req.id} className="bg-sky-900/20 border border-sky-700/30 rounded-lg p-3 flex items-center justify-between">
                <span className="text-sm text-white">
                  Applied to <strong>{req.regiment_name}</strong>
                  <span className="text-slate-500 ml-2">{new Date(req.created_at).toLocaleDateString()}</span>
                </span>
                <button
                  onClick={() => handleCancelRequest(req.id)}
                  className="px-3 py-1 bg-slate-600 hover:bg-slate-500 text-white text-xs font-medium rounded-lg transition-colors"
                >
                  Cancel
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

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
