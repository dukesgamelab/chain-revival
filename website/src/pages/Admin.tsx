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

interface SiteStats {
  totalPlayers: number
  totalMatches: number
  activeRegiments: number
  onlinePlayers: number
}

export function Admin() {
  const { settings, updateSetting } = useSiteSettings()
  const [appeals, setAppeals] = useState<BanAppeal[]>([])
  const [stats, setStats] = useState<SiteStats>({ totalPlayers: 0, totalMatches: 0, activeRegiments: 0, onlinePlayers: 0 })
  const [tab, setTab] = useState<'toggles' | 'stats' | 'appeals'>('toggles')

  useEffect(() => {
    async function loadStats() {
      const [players, matches, regiments, online] = await Promise.all([
        supabase.from('player_profiles').select('id', { count: 'exact', head: true }),
        supabase.from('match_history').select('id', { count: 'exact', head: true }),
        supabase.from('regiments').select('id', { count: 'exact', head: true }).eq('status', 'active'),
        supabase.from('player_profiles').select('id', { count: 'exact', head: true }).not('active_match_id', 'is', null),
      ])
      setStats({
        totalPlayers: players.count ?? 0,
        totalMatches: matches.count ?? 0,
        activeRegiments: regiments.count ?? 0,
        onlinePlayers: online.count ?? 0,
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

    loadStats()
    loadAppeals()
  }, [])

  async function resolveAppeal(id: string, status: 'approved' | 'denied') {
    await supabase
      .from('ban_appeals')
      .update({ status, reviewed_at: new Date().toISOString() })
      .eq('id', id)

    setAppeals(prev => prev.filter(a => a.id !== id))
  }

  const toggles: { key: keyof typeof settings; label: string; desc: string }[] = [
    { key: 'leaderboard_enabled', label: 'Leaderboard', desc: 'Show leaderboard page and nav link' },
    { key: 'regiments_enabled', label: 'Regiments', desc: 'Show regiments page and nav link' },
    { key: 'download_enabled', label: 'Download', desc: 'Show download page and nav link' },
    { key: 'chat_enabled', label: 'Global Chat', desc: 'Show chat widget for signed-in users' },
    { key: 'registration_enabled', label: 'Registration', desc: 'Allow new account sign-ups' },
    { key: 'appeal_enabled', label: 'Ban Appeals', desc: 'Allow ban appeal form submissions' },
  ]

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-6 text-amber-400">Admin Dashboard</h1>

      <div className="flex rounded-lg bg-slate-800 p-1 mb-6 w-fit">
        {(['toggles', 'stats', 'appeals'] as const).map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm font-medium rounded-md transition-colors capitalize ${
              tab === t ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'
            }`}
          >
            {t === 'appeals' ? `Appeals (${appeals.length})` : t}
          </button>
        ))}
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
        </div>
      )}

      {tab === 'stats' && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
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
    </div>
  )
}
