import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/AuthProvider'
import { useSiteSettings } from '../hooks/useSiteSettings'

interface BanAppeal {
  id: string
  player_id: string
  email: string
  appeal_text: string
  status: string
  created_at: string
}

interface BugReportItem {
  id: string
  player_id: string | null
  display_name: string | null
  email: string | null
  title: string
  description: string
  category: string
  severity: string
  steps_to_reproduce: string | null
  status: string
  admin_notes: string | null
  created_at: string
}

interface FeedbackItem {
  id: string
  player_id: string | null
  display_name: string | null
  rating: number
  category: string
  message: string
  created_at: string
}

interface SiteStats {
  totalPlayers: number
  totalMatches: number
  activeRegiments: number
  onlinePlayers: number
  openBugs: number
  feedbackCount: number
}

interface RegimentApplication {
  id: string
  type: string
  regiment_id: string | null
  applicant_id: string
  regiment_name: string | null
  regiment_tag: string | null
  description: string
  status: string
  created_at: string
  applicant_name?: string
  existing_regiment_name?: string
}

interface AdminRegiment {
  id: string
  name: string
  tag: string
  co_id: string | null
  status: string
  member_count?: number
  co_name?: string
}

interface AdminJoinRequest {
  id: string
  regiment_id: string
  player_id: string
  direction: string
  status: string
  created_at: string
  player_name?: string
  regiment_name?: string
}

export function Admin() {
  const { user } = useAuth()
  const { settings, updateSetting } = useSiteSettings()
  const [appeals, setAppeals] = useState<BanAppeal[]>([])
  const [bugReports, setBugReports] = useState<BugReportItem[]>([])
  const [feedbackList, setFeedbackList] = useState<FeedbackItem[]>([])
  const [stats, setStats] = useState<SiteStats>({ totalPlayers: 0, totalMatches: 0, activeRegiments: 0, onlinePlayers: 0, openBugs: 0, feedbackCount: 0 })
  const [regimentApps, setRegimentApps] = useState<RegimentApplication[]>([])
  const [adminRegiments, setAdminRegiments] = useState<AdminRegiment[]>([])
  const [adminJoinRequests, setAdminJoinRequests] = useState<AdminJoinRequest[]>([])
  const [regimentError, setRegimentError] = useState('')
  const [regimentSuccess, setRegimentSuccess] = useState('')
  const [tab, setTab] = useState<'toggles' | 'stats' | 'appeals' | 'bugs' | 'feedback' | 'regiments'>('toggles')

  useEffect(() => {
    async function loadStats() {
      const [players, matches, regiments, online, bugs, fb] = await Promise.all([
        supabase.from('player_profiles').select('id', { count: 'exact', head: true }),
        supabase.from('match_history').select('id', { count: 'exact', head: true }),
        supabase.from('regiments').select('id', { count: 'exact', head: true }).eq('status', 'active'),
        supabase.from('player_profiles').select('id', { count: 'exact', head: true }).not('active_match_id', 'is', null),
        supabase.from('bug_reports').select('id', { count: 'exact', head: true }).eq('status', 'open'),
        supabase.from('feedback').select('id', { count: 'exact', head: true }),
      ])
      setStats({
        totalPlayers: players.count ?? 0,
        totalMatches: matches.count ?? 0,
        activeRegiments: regiments.count ?? 0,
        onlinePlayers: online.count ?? 0,
        openBugs: bugs.count ?? 0,
        feedbackCount: fb.count ?? 0,
      })
    }

    async function loadAppeals() {
      const { data } = await supabase
        .from('ban_appeals')
        .select('*')
        .eq('status', 'pending')
        .order('created_at', { ascending: false })
      if (data) setAppeals(data)
    }

    async function loadBugReports() {
      const { data } = await supabase
        .from('bug_reports')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(50)
      if (data) setBugReports(data)
    }

    async function loadFeedback() {
      const { data } = await supabase
        .from('feedback')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(50)
      if (data) setFeedbackList(data)
    }

    async function loadRegimentData() {
      const { data: apps } = await supabase
        .from('regiment_applications')
        .select('*')
        .eq('status', 'pending')
        .order('created_at', { ascending: false })

      if (apps) {
        const applicantIds = [...new Set(apps.map(a => a.applicant_id))]
        const regIds = apps.map(a => a.regiment_id).filter(Boolean) as string[]
        let nameMap: Record<string, string> = {}
        let regNameMap: Record<string, string> = {}

        if (applicantIds.length > 0) {
          const { data: profiles } = await supabase
            .from('player_profiles')
            .select('id,display_name')
            .in('id', applicantIds)
          if (profiles) for (const p of profiles) nameMap[p.id] = p.display_name
        }
        if (regIds.length > 0) {
          const { data: regs } = await supabase
            .from('regiments')
            .select('id,name')
            .in('id', regIds)
          if (regs) for (const r of regs) regNameMap[r.id] = r.name
        }

        setRegimentApps(apps.map(a => ({
          ...a,
          applicant_name: nameMap[a.applicant_id] ?? 'Unknown',
          existing_regiment_name: a.regiment_id ? regNameMap[a.regiment_id] ?? 'Unknown' : undefined,
        })))
      }

      const { data: regs } = await supabase
        .from('regiments')
        .select('id,name,tag,co_id,status')
        .eq('status', 'active')
        .order('name')

      if (regs) {
        const coIds = [...new Set(regs.map(r => r.co_id).filter(Boolean))] as string[]
        let coMap: Record<string, string> = {}
        if (coIds.length > 0) {
          const { data: profiles } = await supabase
            .from('player_profiles')
            .select('id,display_name')
            .in('id', coIds)
          if (profiles) for (const p of profiles) coMap[p.id] = p.display_name
        }

        const counts: Record<string, number> = {}
        for (const r of regs) {
          const { count } = await supabase
            .from('regiment_members')
            .select('player_id', { count: 'exact', head: true })
            .eq('regiment_id', r.id)
          counts[r.id] = count ?? 0
        }

        setAdminRegiments(regs.map(r => ({
          ...r,
          member_count: counts[r.id] ?? 0,
          co_name: r.co_id ? coMap[r.co_id] ?? 'Unknown' : undefined,
        })))
      }

      const { data: joins } = await supabase
        .from('regiment_join_requests')
        .select('id,regiment_id,player_id,direction,status,created_at')
        .eq('status', 'pending')
        .order('created_at', { ascending: false })
        .limit(50)

      if (joins) {
        const playerIds = [...new Set(joins.map(j => j.player_id))]
        const regIds = [...new Set(joins.map(j => j.regiment_id))]
        let playerMap: Record<string, string> = {}
        let regMap: Record<string, string> = {}

        if (playerIds.length > 0) {
          const { data: profiles } = await supabase
            .from('player_profiles')
            .select('id,display_name')
            .in('id', playerIds)
          if (profiles) for (const p of profiles) playerMap[p.id] = p.display_name
        }
        if (regIds.length > 0) {
          const { data: regsData } = await supabase
            .from('regiments')
            .select('id,name')
            .in('id', regIds)
          if (regsData) for (const r of regsData) regMap[r.id] = r.name
        }

        setAdminJoinRequests(joins.map(j => ({
          ...j,
          player_name: playerMap[j.player_id] ?? 'Unknown',
          regiment_name: regMap[j.regiment_id] ?? 'Unknown',
        })))
      }
    }

    loadStats()
    loadAppeals()
    loadBugReports()
    loadFeedback()
    loadRegimentData()
  }, [])

  async function resolveAppeal(id: string, status: 'approved' | 'denied') {
    await supabase
      .from('ban_appeals')
      .update({ status, reviewed_at: new Date().toISOString() })
      .eq('id', id)

    setAppeals(prev => prev.filter(a => a.id !== id))
  }

  async function updateBugStatus(id: string, status: string) {
    await supabase
      .from('bug_reports')
      .update({ status, updated_at: new Date().toISOString() })
      .eq('id', id)
    setBugReports(prev => prev.map(b => b.id === id ? { ...b, status } : b))
  }

  function flashRegiment(msg: string, isError = false) {
    if (isError) { setRegimentError(msg); setRegimentSuccess('') }
    else { setRegimentSuccess(msg); setRegimentError('') }
    setTimeout(() => { setRegimentError(''); setRegimentSuccess('') }, 3000)
  }

  async function handleApproveApp(appId: string) {
    const { error } = await supabase.rpc('approve_regiment_application', {
      p_application_id: appId,
      p_admin_id: user!.id,
    })
    if (error) { flashRegiment(error.message, true); return }
    setRegimentApps(prev => prev.filter(a => a.id !== appId))
    flashRegiment('Application approved')
  }

  async function handleRejectApp(appId: string) {
    const { error } = await supabase.rpc('reject_regiment_application', {
      p_application_id: appId,
      p_admin_id: user!.id,
    })
    if (error) { flashRegiment(error.message, true); return }
    setRegimentApps(prev => prev.filter(a => a.id !== appId))
    flashRegiment('Application rejected')
  }

  async function handleAdminForceDisband(regimentId: string, name: string) {
    if (!confirm(`Force disband "${name}"? This cannot be undone.`)) return
    const { error } = await supabase.rpc('admin_force_disband', {
      p_admin_id: user!.id,
      p_regiment_id: regimentId,
    })
    if (error) { flashRegiment(error.message, true); return }
    setAdminRegiments(prev => prev.filter(r => r.id !== regimentId))
    flashRegiment(`${name} has been disbanded`)
  }

  const toggles: { key: keyof typeof settings; label: string; desc: string }[] = [
    { key: 'leaderboard_enabled', label: 'Leaderboard', desc: 'Show leaderboard page and nav link' },
    { key: 'regiments_enabled', label: 'Regiments', desc: 'Show regiments page and nav link' },
    { key: 'download_enabled', label: 'Download', desc: 'Show download page and nav link' },
    { key: 'chat_enabled', label: 'Global Chat', desc: 'Show chat widget for signed-in users' },
    { key: 'registration_enabled', label: 'Registration', desc: 'Allow new account sign-ups' },
    { key: 'appeal_enabled', label: 'Ban Appeals', desc: 'Allow ban appeal form submissions' },
    { key: 'bugreports_enabled', label: 'Bug Reports', desc: 'Show bug report form for testers' },
    { key: 'feedback_enabled', label: 'Feedback', desc: 'Show feedback form for testers' },
  ]

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-6 text-amber-400">Admin Dashboard</h1>

      <div className="flex flex-wrap rounded-lg bg-slate-800 p-1 mb-6 w-fit gap-0.5">
        {(['toggles', 'stats', 'appeals', 'bugs', 'feedback', 'regiments'] as const).map(t => {
          const labels: Record<string, string> = {
            toggles: 'Toggles',
            stats: 'Stats',
            appeals: `Appeals (${appeals.length})`,
            bugs: `Bugs (${bugReports.filter(b => b.status === 'open').length})`,
            feedback: `Feedback (${feedbackList.length})`,
            regiments: `Regiments (${regimentApps.length})`,
          }
          return (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
                tab === t ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'
              }`}
            >
              {labels[t]}
            </button>
          )
        })}
      </div>

      {tab === 'toggles' && (
        <div className="space-y-3">
          {toggles.map(t => (
            <div
              key={t.key}
              className="bg-slate-800/60 border border-slate-700/50 rounded-lg p-4 flex items-center justify-between"
            >
              <div>
                <div className="font-medium text-white">{t.label}</div>
                <div className="text-sm text-slate-400">{t.desc}</div>
              </div>
              <button
                onClick={() => updateSetting(t.key, !settings[t.key])}
                className={`relative w-12 h-6 rounded-full transition-colors ${
                  settings[t.key] ? 'bg-sky-600' : 'bg-slate-600'
                }`}
              >
                <span
                  className={`absolute top-0.5 w-5 h-5 bg-white rounded-full transition-transform ${
                    settings[t.key] ? 'translate-x-6' : 'translate-x-0.5'
                  }`}
                />
              </button>
            </div>
          ))}

          <div className="mt-6 pt-6 border-t border-slate-700/50">
            <h3 className="text-sm font-semibold text-slate-300 mb-3">Game Distribution</h3>
            <div className="space-y-3">
              <div className="bg-slate-800/60 border border-slate-700/50 rounded-lg p-4">
                <label className="block text-sm font-medium text-white mb-1">Game Version</label>
                <input
                  type="text"
                  value={settings.game_version}
                  onChange={e => updateSetting('game_version', e.target.value)}
                  placeholder="0.1.0-alpha"
                  className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 font-mono"
                />
              </div>
              <div className="bg-slate-800/60 border border-slate-700/50 rounded-lg p-4">
                <label className="block text-sm font-medium text-white mb-1">Download URL</label>
                <input
                  type="url"
                  value={settings.download_url}
                  onChange={e => updateSetting('download_url', e.target.value)}
                  placeholder="https://chain-revival-ax0q1g.fly.dev/builds/ChainRevival-0.1.0.zip"
                  className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
                />
                <p className="text-xs text-slate-500 mt-1">Leave empty to show "Coming Soon" on the download page</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {tab === 'stats' && (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-white">{stats.totalPlayers}</div>
            <div className="text-sm text-slate-400 mt-1">Total Players</div>
          </div>
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-white">{stats.totalMatches}</div>
            <div className="text-sm text-slate-400 mt-1">Total Matches</div>
          </div>
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-white">{stats.activeRegiments}</div>
            <div className="text-sm text-slate-400 mt-1">Active Regiments</div>
          </div>
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-sky-400">{stats.onlinePlayers}</div>
            <div className="text-sm text-slate-400 mt-1">In Game Now</div>
          </div>
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-amber-400">{stats.openBugs}</div>
            <div className="text-sm text-slate-400 mt-1">Open Bugs</div>
          </div>
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-emerald-400">{stats.feedbackCount}</div>
            <div className="text-sm text-slate-400 mt-1">Feedback Received</div>
          </div>
        </div>
      )}

      {tab === 'appeals' && (
        <div className="space-y-4">
          {appeals.length === 0 ? (
            <div className="text-center text-slate-500 py-16">No pending appeals</div>
          ) : (
            appeals.map(a => (
              <div key={a.id} className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5">
                <div className="flex justify-between items-start mb-3">
                  <div>
                    <span className="text-xs text-slate-500 font-mono">{a.player_id}</span>
                    <div className="text-sm text-slate-400">{a.email}</div>
                  </div>
                  <span className="text-xs text-slate-500">
                    {new Date(a.created_at).toLocaleDateString()}
                  </span>
                </div>
                <p className="text-white text-sm mb-4">{a.appeal_text}</p>
                <div className="flex gap-2">
                  <button
                    onClick={() => resolveAppeal(a.id, 'approved')}
                    className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors"
                  >
                    Approve (Unban)
                  </button>
                  <button
                    onClick={() => resolveAppeal(a.id, 'denied')}
                    className="px-4 py-1.5 bg-red-600 hover:bg-red-500 text-white text-sm font-medium rounded-lg transition-colors"
                  >
                    Deny
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {tab === 'bugs' && (
        <div className="space-y-4">
          {bugReports.length === 0 ? (
            <div className="text-center text-slate-500 py-16">No bug reports yet</div>
          ) : (
            bugReports.map(b => (
              <div key={b.id} className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5">
                <div className="flex justify-between items-start mb-2">
                  <div className="flex items-center gap-2">
                    <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                      b.severity === 'critical' ? 'bg-red-500/20 text-red-400' :
                      b.severity === 'high' ? 'bg-orange-500/20 text-orange-400' :
                      b.severity === 'medium' ? 'bg-amber-500/20 text-amber-400' :
                      'bg-slate-600/30 text-slate-400'
                    }`}>
                      {b.severity}
                    </span>
                    <span className="text-xs text-slate-500 px-2 py-0.5 bg-slate-700/50 rounded-full">{b.category}</span>
                    <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                      b.status === 'open' ? 'bg-sky-500/20 text-sky-400' :
                      b.status === 'in-progress' ? 'bg-amber-500/20 text-amber-400' :
                      b.status === 'closed' ? 'bg-slate-600/30 text-slate-500' :
                      'bg-emerald-500/20 text-emerald-400'
                    }`}>
                      {b.status}
                    </span>
                  </div>
                  <span className="text-xs text-slate-500">
                    {new Date(b.created_at).toLocaleDateString()}
                  </span>
                </div>
                <h3 className="text-white font-medium mb-1">{b.title}</h3>
                <p className="text-slate-400 text-sm mb-1">{b.description}</p>
                {b.steps_to_reproduce && (
                  <p className="text-slate-500 text-xs mt-2 whitespace-pre-line">{b.steps_to_reproduce}</p>
                )}
                <div className="flex items-center justify-between mt-3 pt-3 border-t border-slate-700/30">
                  <span className="text-xs text-slate-500">
                    {b.display_name ?? b.email ?? 'Anonymous'}
                  </span>
                  <div className="flex gap-2">
                    {b.status === 'open' && (
                      <button
                        onClick={() => updateBugStatus(b.id, 'in-progress')}
                        className="px-3 py-1 bg-amber-600 hover:bg-amber-500 text-white text-xs font-medium rounded-lg transition-colors"
                      >
                        In Progress
                      </button>
                    )}
                    {b.status !== 'closed' && (
                      <button
                        onClick={() => updateBugStatus(b.id, 'closed')}
                        className="px-3 py-1 bg-slate-600 hover:bg-slate-500 text-white text-xs font-medium rounded-lg transition-colors"
                      >
                        Close
                      </button>
                    )}
                    {b.status === 'closed' && (
                      <button
                        onClick={() => updateBugStatus(b.id, 'open')}
                        className="px-3 py-1 bg-sky-600 hover:bg-sky-500 text-white text-xs font-medium rounded-lg transition-colors"
                      >
                        Reopen
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {tab === 'feedback' && (
        <div className="space-y-4">
          {feedbackList.length === 0 ? (
            <div className="text-center text-slate-500 py-16">No feedback yet</div>
          ) : (
            feedbackList.map(f => (
              <div key={f.id} className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5">
                <div className="flex justify-between items-start mb-2">
                  <div className="flex items-center gap-2">
                    <span className="text-amber-400">
                      {'★'.repeat(f.rating)}{'☆'.repeat(5 - f.rating)}
                    </span>
                    <span className="text-xs text-slate-500 px-2 py-0.5 bg-slate-700/50 rounded-full">{f.category}</span>
                  </div>
                  <span className="text-xs text-slate-500">
                    {new Date(f.created_at).toLocaleDateString()}
                  </span>
                </div>
                <p className="text-white text-sm">{f.message}</p>
                <div className="mt-2 text-xs text-slate-500">
                  {f.display_name ?? 'Anonymous'}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {tab === 'regiments' && (
        <div className="space-y-6">
          {(regimentError || regimentSuccess) && (
            <div className={`px-4 py-2 rounded-lg text-sm ${regimentError ? 'bg-red-500/20 text-red-400' : 'bg-emerald-500/20 text-emerald-400'}`}>
              {regimentError || regimentSuccess}
            </div>
          )}

          <div>
            <h3 className="text-lg font-bold text-white mb-3">Pending Applications</h3>
            {regimentApps.length === 0 ? (
              <div className="text-center text-slate-500 py-8">No pending applications</div>
            ) : (
              <div className="space-y-3">
                {regimentApps.map(app => (
                  <div key={app.id} className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                          app.type === 'create' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'
                        }`}>
                          {app.type === 'create' ? 'Create' : 'Disband'}
                        </span>
                        <span className="text-white font-medium ml-2">
                          {app.type === 'create' ? `[${app.regiment_tag}] ${app.regiment_name}` : app.existing_regiment_name}
                        </span>
                      </div>
                      <span className="text-xs text-slate-500">{new Date(app.created_at).toLocaleDateString()}</span>
                    </div>
                    <p className="text-sm text-slate-400 mb-2">{app.description}</p>
                    <div className="flex items-center justify-between">
                      <Link to={`/player/${app.applicant_id}`} className="text-xs text-sky-400 hover:underline">
                        By: {app.applicant_name}
                      </Link>
                      <div className="flex gap-2">
                        <button
                          onClick={() => handleApproveApp(app.id)}
                          className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white text-sm font-medium rounded-lg transition-colors"
                        >
                          Approve
                        </button>
                        <button
                          onClick={() => handleRejectApp(app.id)}
                          className="px-4 py-1.5 bg-red-600 hover:bg-red-500 text-white text-sm font-medium rounded-lg transition-colors"
                        >
                          Reject
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <h3 className="text-lg font-bold text-white mb-3">Active Regiments</h3>
            {adminRegiments.length === 0 ? (
              <div className="text-center text-slate-500 py-8">No active regiments</div>
            ) : (
              <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-700 text-slate-400 text-left">
                      <th className="px-4 py-3">Regiment</th>
                      <th className="px-4 py-3">CO</th>
                      <th className="px-4 py-3 text-center">Members</th>
                      <th className="px-4 py-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {adminRegiments.map(r => (
                      <tr key={r.id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                        <td className="px-4 py-3">
                          <Link to={`/regiments?id=${r.id}`} className="text-sky-400 hover:text-sky-300 hover:underline">
                            [{r.tag}] {r.name}
                          </Link>
                        </td>
                        <td className="px-4 py-3 text-slate-300">
                          {r.co_id ? (
                            <Link to={`/player/${r.co_id}`} className="text-sky-400 hover:underline text-xs">{r.co_name}</Link>
                          ) : (
                            <span className="text-slate-500">None</span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-center text-slate-400">{r.member_count}</td>
                        <td className="px-4 py-3 text-right">
                          <button
                            onClick={() => handleAdminForceDisband(r.id, r.name)}
                            className="px-2 py-1 bg-red-600 hover:bg-red-500 text-white text-xs rounded transition-colors"
                          >
                            Force Disband
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          <div>
            <h3 className="text-lg font-bold text-white mb-3">Pending Join Requests</h3>
            {adminJoinRequests.length === 0 ? (
              <div className="text-center text-slate-500 py-8">No pending join requests</div>
            ) : (
              <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-700 text-slate-400 text-left">
                      <th className="px-4 py-3">Player</th>
                      <th className="px-4 py-3">Regiment</th>
                      <th className="px-4 py-3">Type</th>
                      <th className="px-4 py-3">Date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {adminJoinRequests.map(j => (
                      <tr key={j.id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                        <td className="px-4 py-3">
                          <Link to={`/player/${j.player_id}`} className="text-sky-400 hover:underline">{j.player_name}</Link>
                        </td>
                        <td className="px-4 py-3">
                          <Link to={`/regiments?id=${j.regiment_id}`} className="text-sky-400 hover:underline">{j.regiment_name}</Link>
                        </td>
                        <td className="px-4 py-3">
                          <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                            j.direction === 'request' ? 'bg-sky-500/20 text-sky-400' : 'bg-amber-500/20 text-amber-400'
                          }`}>
                            {j.direction === 'request' ? 'Request' : 'Invite'}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-500 text-xs">{new Date(j.created_at).toLocaleDateString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
