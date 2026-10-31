import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
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
  player_id: string
  direction: string
  status: string
  created_at: string
  display_name?: string
  rank?: number
}

interface PlayerSearchResult {
  id: string
  display_name: string
  rank: number
  regiment_id: string | null
}

const REGIMENT_RANKS = ['1LT', 'CPT', 'MAJ', 'LT COL', 'COL']

export function RegimentManage() {
  const { user, profile } = useAuth()
  const navigate = useNavigate()
  const [regiment, setRegiment] = useState<Regiment | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [joinRequests, setJoinRequests] = useState<JoinRequest[]>([])
  const [sentInvites, setSentInvites] = useState<JoinRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [tab, setTab] = useState<'members' | 'requests' | 'invites' | 'settings' | 'disband'>('members')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const [editDesc, setEditDesc] = useState('')
  const [editWebsite, setEditWebsite] = useState('')

  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<PlayerSearchResult[]>([])
  const [searching, setSearching] = useState(false)

  const [confirmDisband, setConfirmDisband] = useState(false)

  const regimentId = profile?.regiment_id
  const isCO = regiment?.co_id === user?.id
  const isXO = regiment?.xo_id === user?.id
  const isLeader = isCO || isXO

  useEffect(() => {
    if (!regimentId || !user) return

    async function load() {
      const { data: regData } = await supabase
        .from('regiments')
        .select('id,name,tag,description,website_url,co_id,xo_id,max_members')
        .eq('id', regimentId)
        .single()

      if (!regData) {
        navigate('/regiments')
        return
      }

      setRegiment(regData)
      setEditDesc(regData.description)
      setEditWebsite(regData.website_url ?? '')

      const { data: memberData } = await supabase
        .from('regiment_members')
        .select('player_id,assigned_rank')
        .eq('regiment_id', regimentId)

      if (memberData && memberData.length > 0) {
        const playerIds = memberData.map(m => m.player_id)
        const { data: profiles } = await supabase
          .from('player_profiles')
          .select('id,display_name,rank,prestige_points')
          .in('id', playerIds)

        if (profiles) {
          setMembers(memberData.map(m => {
            const p = profiles.find(pr => pr.id === m.player_id)
            return {
              player_id: m.player_id,
              assigned_rank: m.assigned_rank,
              display_name: p?.display_name ?? 'Unknown',
              rank: p?.rank ?? 0,
              prestige_points: p?.prestige_points ?? 0,
            }
          }))
        }
      }

      const { data: requests } = await supabase
        .from('regiment_join_requests')
        .select('id,player_id,direction,status,created_at')
        .eq('regiment_id', regimentId)
        .eq('status', 'pending')

      if (requests) {
        const playerIds = [...new Set(requests.map(r => r.player_id))]
        let profileMap: Record<string, { display_name: string; rank: number }> = {}
        if (playerIds.length > 0) {
          const { data: profiles } = await supabase
            .from('player_profiles')
            .select('id,display_name,rank')
            .in('id', playerIds)
          if (profiles) {
            for (const p of profiles) profileMap[p.id] = p
          }
        }

        const enriched = requests.map(r => ({
          ...r,
          display_name: profileMap[r.player_id]?.display_name ?? 'Unknown',
          rank: profileMap[r.player_id]?.rank ?? 0,
        }))

        setJoinRequests(enriched.filter(r => r.direction === 'request'))
        setSentInvites(enriched.filter(r => r.direction === 'invite'))
      }

      setLoading(false)
    }

    load()
  }, [regimentId, user])

  function flash(msg: string, isError = false) {
    if (isError) { setError(msg); setSuccess('') }
    else { setSuccess(msg); setError('') }
    setTimeout(() => { setError(''); setSuccess('') }, 3000)
  }

  async function handleAcceptRequest(requestId: string) {
    const { error } = await supabase.rpc('accept_regiment_join', {
      p_request_id: requestId,
      p_user_id: user!.id,
    })
    if (error) { flash(error.message, true); return }
    setJoinRequests(prev => prev.filter(r => r.id !== requestId))
    flash('Request accepted')
    // Reload members
    const { data: memberData } = await supabase
      .from('regiment_members')
      .select('player_id,assigned_rank')
      .eq('regiment_id', regimentId!)
    if (memberData && memberData.length > 0) {
      const playerIds = memberData.map(m => m.player_id)
      const { data: profiles } = await supabase
        .from('player_profiles')
        .select('id,display_name,rank,prestige_points')
        .in('id', playerIds)
      if (profiles) {
        setMembers(memberData.map(m => {
          const p = profiles.find(pr => pr.id === m.player_id)
          return {
            player_id: m.player_id,
            assigned_rank: m.assigned_rank,
            display_name: p?.display_name ?? 'Unknown',
            rank: p?.rank ?? 0,
            prestige_points: p?.prestige_points ?? 0,
          }
        }))
      }
    }
  }

  async function handleRejectRequest(requestId: string) {
    const { error } = await supabase.rpc('reject_regiment_join', {
      p_request_id: requestId,
      p_user_id: user!.id,
    })
    if (error) { flash(error.message, true); return }
    setJoinRequests(prev => prev.filter(r => r.id !== requestId))
    flash('Request rejected')
  }

  async function handleKick(targetId: string, name: string) {
    if (!confirm(`Kick ${name} from the regiment?`)) return
    const { error } = await supabase.rpc('kick_regiment_member', {
      p_regiment_id: regimentId!,
      p_target_id: targetId,
      p_caller_id: user!.id,
    })
    if (error) { flash(error.message, true); return }
    setMembers(prev => prev.filter(m => m.player_id !== targetId))
    if (regiment?.xo_id === targetId) {
      setRegiment(prev => prev ? { ...prev, xo_id: null } : prev)
    }
    flash(`${name} has been kicked`)
  }

  async function handleSetXO(targetId: string | null, name: string) {
    const { error } = await supabase.rpc('set_regiment_xo', {
      p_regiment_id: regimentId!,
      p_caller_id: user!.id,
      p_xo_id: targetId,
    })
    if (error) { flash(error.message, true); return }
    setRegiment(prev => prev ? { ...prev, xo_id: targetId } : prev)
    flash(targetId ? `${name} is now XO` : 'XO removed')
  }

  async function handleAssignRank(targetId: string, rank: string | null) {
    const { error } = await supabase.rpc('assign_regiment_rank', {
      p_regiment_id: regimentId!,
      p_target_id: targetId,
      p_caller_id: user!.id,
      p_rank: rank,
    })
    if (error) { flash(error.message, true); return }
    setMembers(prev => prev.map(m =>
      m.player_id === targetId ? { ...m, assigned_rank: rank } : m
    ))
    flash(rank ? `Rank set to ${rank}` : 'Rank cleared')
  }

  async function handleSaveSettings() {
    const { error } = await supabase.rpc('update_regiment_details', {
      p_regiment_id: regimentId!,
      p_caller_id: user!.id,
      p_description: editDesc,
      p_website_url: editWebsite || null,
    })
    if (error) { flash(error.message, true); return }
    setRegiment(prev => prev ? { ...prev, description: editDesc, website_url: editWebsite || null } : prev)
    flash('Settings saved')
  }

  async function handleSearchPlayers() {
    if (searchQuery.length < 2) return
    setSearching(true)
    const { data } = await supabase
      .from('player_profiles')
      .select('id,display_name,rank,regiment_id')
      .ilike('display_name', `%${searchQuery}%`)
      .is('regiment_id', null)
      .limit(10)
    setSearchResults(data ?? [])
    setSearching(false)
  }

  async function handleSendInvite(targetId: string, name: string) {
    const { error } = await supabase
      .from('regiment_join_requests')
      .insert({
        regiment_id: regimentId!,
        player_id: targetId,
        direction: 'invite',
        invited_by: user!.id,
      })
    if (error) { flash(error.message, true); return }
    setSearchResults(prev => prev.filter(p => p.id !== targetId))
    setSentInvites(prev => [...prev, {
      id: crypto.randomUUID(),
      player_id: targetId,
      direction: 'invite',
      status: 'pending',
      created_at: new Date().toISOString(),
      display_name: name,
    }])
    flash(`Invite sent to ${name}`)
  }

  async function handleRequestDisband() {
    const { error } = await supabase
      .from('regiment_applications')
      .insert({
        type: 'disband',
        regiment_id: regimentId!,
        applicant_id: user!.id,
        description: `Disbandment requested by CO`,
      })
    if (error) { flash(error.message, true); return }
    setConfirmDisband(false)
    flash('Disbandment request submitted. An admin will review it.')
  }

  if (!user || !profile?.regiment_id) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-16 text-center text-slate-500">
        You are not in a regiment.
        <Link to="/regiments" className="block mt-4 text-sky-400 hover:underline">Browse Regiments</Link>
      </div>
    )
  }

  if (loading) {
    return <div className="max-w-4xl mx-auto px-4 py-16 text-center text-slate-500">Loading...</div>
  }

  if (!regiment || !isLeader) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-16 text-center text-slate-500">
        Only the CO or XO can manage this regiment.
        <Link to="/regiments" className="block mt-4 text-sky-400 hover:underline">Back to Regiments</Link>
      </div>
    )
  }

  const tabs = [
    { key: 'members' as const, label: `Members (${members.length})` },
    { key: 'requests' as const, label: `Requests (${joinRequests.length})` },
    { key: 'invites' as const, label: 'Invites' },
    ...(isCO ? [
      { key: 'settings' as const, label: 'Settings' },
      { key: 'disband' as const, label: 'Disband' },
    ] : []),
  ]

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <Link
        to={`/regiments?id=${regiment.id}`}
        className="text-sky-400 hover:text-sky-300 text-sm mb-4 inline-flex items-center gap-1"
      >
        &larr; Back to Regiment
      </Link>

      <div className="flex items-center gap-3 mb-6">
        <span className="text-2xl font-bold text-amber-400">[{regiment.tag}]</span>
        <h1 className="text-3xl font-bold">{regiment.name}</h1>
        <span className="text-xs font-semibold px-2 py-0.5 rounded bg-amber-900/50 text-amber-300">
          {isCO ? 'CO' : 'XO'}
        </span>
      </div>

      {(error || success) && (
        <div className={`mb-4 px-4 py-2 rounded-lg text-sm ${error ? 'bg-red-500/20 text-red-400' : 'bg-emerald-500/20 text-emerald-400'}`}>
          {error || success}
        </div>
      )}

      <div className="flex flex-wrap rounded-lg bg-slate-800 p-1 mb-6 w-fit gap-0.5">
        {tabs.map(t => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
              tab === t.key ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'members' && (
        <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700 text-slate-400 text-left">
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3">Rank</th>
                <th className="px-4 py-3">Role</th>
                <th className="px-4 py-3">Regiment Rank</th>
                <th className="px-4 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {members.map(m => {
                const isMemberCO = m.player_id === regiment.co_id
                const isMemberXO = m.player_id === regiment.xo_id
                const canKick = !isMemberCO && (isCO || (!isMemberXO && isXO))
                const canSetXO = isCO && !isMemberCO && !isMemberXO
                const canRemoveXO = isCO && isMemberXO
                const canAssignRank = isLeader && !isMemberCO && m.rank >= 7

                return (
                  <tr key={m.player_id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                    <td className="px-4 py-3">
                      <Link to={`/player/${m.player_id}`} className="text-sky-400 hover:text-sky-300 hover:underline">
                        {m.display_name}
                      </Link>
                    </td>
                    <td className="px-4 py-3"><RankBadge rank={m.rank} /></td>
                    <td className="px-4 py-3">
                      {isMemberCO && <span className="text-xs font-semibold px-2 py-0.5 rounded bg-amber-900/50 text-amber-300">CO</span>}
                      {isMemberXO && <span className="text-xs font-semibold px-2 py-0.5 rounded bg-amber-900/50 text-amber-300">XO</span>}
                    </td>
                    <td className="px-4 py-3">
                      {canAssignRank ? (
                        <select
                          value={m.assigned_rank ?? ''}
                          onChange={e => handleAssignRank(m.player_id, e.target.value || null)}
                          className="bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs text-white"
                        >
                          <option value="">None</option>
                          {REGIMENT_RANKS.map(r => (
                            <option key={r} value={r}>{r}</option>
                          ))}
                        </select>
                      ) : (
                        m.assigned_rank && <span className="text-xs text-slate-400">{m.assigned_rank}</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex gap-1 justify-end">
                        {canSetXO && (
                          <button
                            onClick={() => handleSetXO(m.player_id, m.display_name)}
                            className="px-2 py-1 bg-amber-600 hover:bg-amber-500 text-white text-xs rounded transition-colors"
                          >
                            Set XO
                          </button>
                        )}
                        {canRemoveXO && (
                          <button
                            onClick={() => handleSetXO(null, m.display_name)}
                            className="px-2 py-1 bg-slate-600 hover:bg-slate-500 text-white text-xs rounded transition-colors"
                          >
                            Remove XO
                          </button>
                        )}
                        {canKick && (
                          <button
                            onClick={() => handleKick(m.player_id, m.display_name)}
                            className="px-2 py-1 bg-red-600 hover:bg-red-500 text-white text-xs rounded transition-colors"
                          >
                            Kick
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'requests' && (
        <div className="space-y-3">
          {joinRequests.length === 0 ? (
            <div className="text-center text-slate-500 py-16">No pending join requests</div>
          ) : (
            joinRequests.map(r => (
              <div key={r.id} className="bg-slate-800/60 border border-slate-700/50 rounded-lg p-4 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Link to={`/player/${r.player_id}`} className="text-sky-400 hover:text-sky-300 hover:underline font-medium">
                    {r.display_name}
                  </Link>
                  <RankBadge rank={r.rank ?? 0} />
                  <span className="text-xs text-slate-500">{new Date(r.created_at).toLocaleDateString()}</span>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => handleAcceptRequest(r.id)}
                    className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-medium rounded-lg transition-colors"
                  >
                    Accept
                  </button>
                  <button
                    onClick={() => handleRejectRequest(r.id)}
                    className="px-3 py-1.5 bg-red-600 hover:bg-red-500 text-white text-xs font-medium rounded-lg transition-colors"
                  >
                    Reject
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {tab === 'invites' && (
        <div className="space-y-6">
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5">
            <h3 className="font-medium text-white mb-3">Send Invite</h3>
            <div className="flex gap-2 mb-3">
              <input
                type="text"
                value={searchQuery}
                onChange={e => setSearchQuery(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleSearchPlayers()}
                placeholder="Search players by name..."
                className="flex-1 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
              />
              <button
                onClick={handleSearchPlayers}
                disabled={searchQuery.length < 2 || searching}
                className="px-4 py-2 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Search
              </button>
            </div>
            {searchResults.length > 0 && (
              <div className="space-y-2">
                {searchResults.map(p => (
                  <div key={p.id} className="flex items-center justify-between bg-slate-900/50 rounded-lg px-3 py-2">
                    <div className="flex items-center gap-2">
                      <Link to={`/player/${p.id}`} className="text-sky-400 hover:text-sky-300 text-sm">{p.display_name}</Link>
                      <RankBadge rank={p.rank} />
                    </div>
                    <button
                      onClick={() => handleSendInvite(p.id, p.display_name)}
                      className="px-3 py-1 bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-medium rounded-lg transition-colors"
                    >
                      Invite
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <h3 className="font-medium text-white mb-3">Pending Invites</h3>
            {sentInvites.length === 0 ? (
              <div className="text-center text-slate-500 py-8">No pending invites</div>
            ) : (
              <div className="space-y-2">
                {sentInvites.map(inv => (
                  <div key={inv.id} className="bg-slate-800/60 border border-slate-700/50 rounded-lg p-3 flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-white text-sm">{inv.display_name}</span>
                      <span className="text-xs text-slate-500">{new Date(inv.created_at).toLocaleDateString()}</span>
                    </div>
                    <span className="text-xs text-amber-400">Pending</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {tab === 'settings' && isCO && (
        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 space-y-4">
          <div>
            <label className="block text-sm font-medium text-white mb-1">Description</label>
            <textarea
              value={editDesc}
              onChange={e => setEditDesc(e.target.value)}
              rows={4}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 resize-none"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-white mb-1">Website URL</label>
            <input
              type="url"
              value={editWebsite}
              onChange={e => setEditWebsite(e.target.value)}
              placeholder="https://..."
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
            />
          </div>
          <button
            onClick={handleSaveSettings}
            className="px-6 py-2 bg-sky-600 hover:bg-sky-500 text-white text-sm font-medium rounded-lg transition-colors"
          >
            Save Changes
          </button>
        </div>
      )}

      {tab === 'disband' && isCO && (
        <div className="bg-slate-800/60 border border-red-700/30 rounded-xl p-6">
          <h3 className="text-lg font-bold text-red-400 mb-2">Disband Regiment</h3>
          <p className="text-slate-400 text-sm mb-4">
            Requesting disbandment will send a request to the admins. If approved, the regiment will be
            permanently disbanded and all members will be removed. This cannot be undone.
          </p>
          {!confirmDisband ? (
            <button
              onClick={() => setConfirmDisband(true)}
              className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white text-sm font-medium rounded-lg transition-colors"
            >
              Request Disbandment
            </button>
          ) : (
            <div className="flex items-center gap-3">
              <span className="text-sm text-red-400">Are you sure?</span>
              <button
                onClick={handleRequestDisband}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Yes, Request Disbandment
              </button>
              <button
                onClick={() => setConfirmDisband(false)}
                className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white text-sm font-medium rounded-lg transition-colors"
              >
                Cancel
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
