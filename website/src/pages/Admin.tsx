import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
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

export function Admin() {
  const { settings, updateSetting } = useSiteSettings()
  const [appeals, setAppeals] = useState<BanAppeal[]>([])
  const [bugReports, setBugReports] = useState<BugReportItem[]>([])
  const [feedbackList, setFeedbackList] = useState<FeedbackItem[]>([])
  const [stats, setStats] = useState<SiteStats>({ totalPlayers: 0, totalMatches: 0, activeRegiments: 0, onlinePlayers: 0, openBugs: 0, feedbackCount: 0 })
  const [tab, setTab] = useState<'toggles' | 'stats' | 'appeals' | 'bugs' | 'feedback'>('toggles')

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

    loadStats()
    loadAppeals()
    loadBugReports()
    loadFeedback()
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
        {(['toggles', 'stats', 'appeals', 'bugs', 'feedback'] as const).map(t => {
          const labels: Record<string, string> = {
            toggles: 'Toggles',
            stats: 'Stats',
            appeals: `Appeals (${appeals.length})`,
            bugs: `Bugs (${bugReports.filter(b => b.status === 'open').length})`,
            feedback: `Feedback (${feedbackList.length})`,
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
    </div>
  )
}
