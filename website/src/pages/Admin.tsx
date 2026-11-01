import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import ReactMarkdown from 'react-markdown'
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

interface AdminPlayer {
  id: string
  display_name: string
  is_admin: boolean
  is_moderator: boolean
  is_banned: boolean
  rank: number
  prestige_points: number
  email?: string
}

interface AdminAnnouncement {
  id: string
  title: string
  body: string
  category: string
  version: string | null
  is_pinned: boolean
  is_published: boolean
  author_id: string
  created_at: string
  updated_at: string
}

interface AnnouncementComment {
  id: string
  announcement_id: string
  user_id: string
  display_name: string
  body: string
  created_at: string
}

const EMPTY_FORM = { title: '', body: '', category: 'news', version: '', is_pinned: false, is_published: false }

const MD_PREVIEW_COMPONENTS = {
  h1: ({ children }: { children?: React.ReactNode }) => <h1 className="text-2xl font-bold text-white mt-4 mb-2">{children}</h1>,
  h2: ({ children }: { children?: React.ReactNode }) => <h2 className="text-lg font-bold text-white mt-4 mb-2">{children}</h2>,
  h3: ({ children }: { children?: React.ReactNode }) => <h3 className="text-base font-semibold text-white mt-3 mb-1">{children}</h3>,
  p: ({ children }: { children?: React.ReactNode }) => <p className="text-slate-300 mb-2">{children}</p>,
  ul: ({ children }: { children?: React.ReactNode }) => <ul className="list-disc list-inside text-slate-300 mb-2 space-y-1">{children}</ul>,
  ol: ({ children }: { children?: React.ReactNode }) => <ol className="list-decimal list-inside text-slate-300 mb-2 space-y-1">{children}</ol>,
  li: ({ children }: { children?: React.ReactNode }) => <li className="text-slate-300">{children}</li>,
  strong: ({ children }: { children?: React.ReactNode }) => <strong className="text-white font-semibold">{children}</strong>,
  code: ({ children }: { children?: React.ReactNode }) => <code className="bg-slate-900 px-1.5 py-0.5 rounded text-sky-300 text-sm font-mono">{children}</code>,
  a: ({ href, children }: { href?: string; children?: React.ReactNode }) => <a href={href} className="text-sky-400 hover:underline" target="_blank" rel="noopener noreferrer">{children}</a>,
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
  const [adminAnnouncements, setAdminAnnouncements] = useState<AdminAnnouncement[]>([])
  const [announcementForm, setAnnouncementForm] = useState(EMPTY_FORM)
  const [editingAnnouncementId, setEditingAnnouncementId] = useState<string | null>(null)
  const [showAnnouncementForm, setShowAnnouncementForm] = useState(false)
  const [previewMode, setPreviewMode] = useState(false)
  const [announcementComments, setAnnouncementComments] = useState<Record<string, AnnouncementComment[]>>({})
  const [expandedAnnouncementComments, setExpandedAnnouncementComments] = useState<Set<string>>(new Set())
  const [newsletterCount, setNewsletterCount] = useState(0)
  const [adminPlayers, setAdminPlayers] = useState<AdminPlayer[]>([])
  const [playerSearch, setPlayerSearch] = useState('')
  const [playerSearchLoading, setPlayerSearchLoading] = useState(false)
  const [tab, setTab] = useState<'toggles' | 'stats' | 'appeals' | 'bugs' | 'feedback' | 'regiments' | 'announcements' | 'players'>('toggles')

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

    async function loadAnnouncements() {
      const { data } = await supabase
        .from('announcements')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100)
      if (data) setAdminAnnouncements(data)
    }

    async function loadNewsletterCount() {
      const { count } = await supabase
        .from('newsletter_subscribers')
        .select('id', { count: 'exact', head: true })
        .is('unsubscribed_at', null)
      setNewsletterCount(count ?? 0)
    }

    async function loadPlayers() {
      const { data } = await supabase
        .from('player_profiles')
        .select('id,display_name,is_admin,is_moderator,is_banned,rank,prestige_points')
        .order('display_name')
        .limit(100)
      if (data) setAdminPlayers(data)
    }

    loadStats()
    loadAppeals()
    loadBugReports()
    loadFeedback()
    loadRegimentData()
    loadAnnouncements()
    loadNewsletterCount()
    loadPlayers()
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

  async function saveAnnouncement() {
    if (!announcementForm.title.trim() || !announcementForm.body.trim()) return
    const payload = {
      title: announcementForm.title.trim(),
      body: announcementForm.body.trim(),
      category: announcementForm.category,
      version: announcementForm.version.trim() || null,
      is_pinned: announcementForm.is_pinned,
      is_published: announcementForm.is_published,
      author_id: user!.id,
      updated_at: new Date().toISOString(),
    }
    if (editingAnnouncementId) {
      const { error } = await supabase.from('announcements').update(payload).eq('id', editingAnnouncementId)
      if (!error) {
        setAdminAnnouncements(prev => prev.map(a => a.id === editingAnnouncementId ? { ...a, ...payload } : a))
      }
    } else {
      const { data, error } = await supabase.from('announcements').insert(payload).select().single()
      if (!error && data) {
        setAdminAnnouncements(prev => [data, ...prev])
      }
    }
    setShowAnnouncementForm(false)
    setEditingAnnouncementId(null)
    setAnnouncementForm(EMPTY_FORM)
    setPreviewMode(false)
  }

  function startEditAnnouncement(a: AdminAnnouncement) {
    setAnnouncementForm({
      title: a.title,
      body: a.body,
      category: a.category,
      version: a.version ?? '',
      is_pinned: a.is_pinned,
      is_published: a.is_published,
    })
    setEditingAnnouncementId(a.id)
    setShowAnnouncementForm(true)
    setPreviewMode(false)
  }

  async function deleteAnnouncement(id: string) {
    if (!confirm('Delete this announcement? This cannot be undone.')) return
    await supabase.from('announcements').delete().eq('id', id)
    setAdminAnnouncements(prev => prev.filter(a => a.id !== id))
  }

  async function loadAnnouncementComments(announcementId: string) {
    if (announcementComments[announcementId]) return
    const { data } = await supabase
      .from('announcement_comments')
      .select('*')
      .eq('announcement_id', announcementId)
      .order('created_at', { ascending: true })
    if (data) setAnnouncementComments(prev => ({ ...prev, [announcementId]: data }))
  }

  function toggleAnnouncementComments(announcementId: string) {
    setExpandedAnnouncementComments(prev => {
      const next = new Set(prev)
      if (next.has(announcementId)) {
        next.delete(announcementId)
      } else {
        next.add(announcementId)
        loadAnnouncementComments(announcementId)
      }
      return next
    })
  }

  async function deleteComment(commentId: string, announcementId: string) {
    if (!confirm('Delete this comment?')) return
    await supabase.from('announcement_comments').delete().eq('id', commentId)
    setAnnouncementComments(prev => ({
      ...prev,
      [announcementId]: (prev[announcementId] ?? []).filter(c => c.id !== commentId),
    }))
  }

  async function searchPlayers(query: string) {
    setPlayerSearch(query)
    if (query.trim().length < 2) {
      const { data } = await supabase
        .from('player_profiles')
        .select('id,display_name,is_admin,is_moderator,is_banned,rank,prestige_points')
        .order('display_name')
        .limit(100)
      if (data) setAdminPlayers(data)
      return
    }
    setPlayerSearchLoading(true)
    const { data } = await supabase
      .from('player_profiles')
      .select('id,display_name,is_admin,is_moderator,is_banned,rank,prestige_points')
      .ilike('display_name', `%${query.trim()}%`)
      .order('display_name')
      .limit(100)
    if (data) setAdminPlayers(data)
    setPlayerSearchLoading(false)
  }

  async function togglePlayerAdmin(playerId: string, isAdmin: boolean) {
    const { error } = await supabase.rpc('set_admin', {
      p_target_id: playerId,
      p_is_admin: isAdmin,
    })
    if (error) { alert(error.message); return }
    setAdminPlayers(prev => prev.map(p => p.id === playerId ? { ...p, is_admin: isAdmin } : p))
  }

  async function togglePlayerModerator(playerId: string, isMod: boolean) {
    const { error } = await supabase.rpc('set_moderator', {
      p_target_id: playerId,
      p_is_moderator: isMod,
    })
    if (error) { alert(error.message); return }
    setAdminPlayers(prev => prev.map(p => p.id === playerId ? { ...p, is_moderator: isMod } : p))
  }

  const RANK_LABELS = ['PVT', 'PFC', 'CPL', 'SGT', 'SSG', 'SFC', 'MSG', '2LT', '1LT', 'CPT']

  const toggles: { key: keyof typeof settings; label: string; desc: string }[] = [
    { key: 'leaderboard_enabled', label: 'Leaderboard', desc: 'Show leaderboard page and nav link' },
    { key: 'regiments_enabled', label: 'Regiments', desc: 'Show regiments page and nav link' },
    { key: 'download_enabled', label: 'Download', desc: 'Show download page and nav link' },
    { key: 'chat_enabled', label: 'Global Chat', desc: 'Show chat widget for signed-in users' },
    { key: 'registration_enabled', label: 'Registration', desc: 'Allow new account sign-ups' },
    { key: 'appeal_enabled', label: 'Ban Appeals', desc: 'Allow ban appeal form submissions' },
    { key: 'bugreports_enabled', label: 'Bug Reports', desc: 'Show bug report form for testers' },
    { key: 'feedback_enabled', label: 'Feedback', desc: 'Show feedback form for testers' },
    { key: 'announcements_enabled', label: 'Announcements', desc: 'Show news/announcements page and nav link' },
  ]

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-6 text-amber-400">Admin Dashboard</h1>

      <div className="flex flex-wrap rounded-lg bg-slate-800 p-1 mb-6 w-fit gap-0.5">
        {(['toggles', 'stats', 'players', 'appeals', 'bugs', 'feedback', 'regiments', 'announcements'] as const).map(t => {
          const labels: Record<string, string> = {
            toggles: 'Toggles',
            stats: 'Stats',
            players: 'Players',
            appeals: `Appeals (${appeals.length})`,
            bugs: `Bugs (${bugReports.filter(b => b.status === 'open').length})`,
            feedback: `Feedback (${feedbackList.length})`,
            regiments: `Regiments (${regimentApps.length})`,
            announcements: `News (${adminAnnouncements.length})`,
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
          <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
            <div className="text-3xl font-bold text-violet-400">{newsletterCount}</div>
            <div className="text-sm text-slate-400 mt-1">Newsletter Subscribers</div>
          </div>
        </div>
      )}

      {tab === 'players' && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <input
              type="text"
              value={playerSearch}
              onChange={e => searchPlayers(e.target.value)}
              placeholder="Search by display name..."
              className="flex-1 bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
            />
            {playerSearchLoading && <span className="text-slate-500 text-sm">Searching...</span>}
          </div>

          {adminPlayers.length === 0 ? (
            <div className="text-center text-slate-500 py-16">No players found</div>
          ) : (
            <div className="bg-slate-800/40 border border-slate-700/50 rounded-xl overflow-hidden">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-700 text-slate-400 text-left">
                    <th className="px-4 py-3">Player</th>
                    <th className="px-4 py-3 text-center">Rank</th>
                    <th className="px-4 py-3 text-center">PP</th>
                    <th className="px-4 py-3 text-center">Admin</th>
                    <th className="px-4 py-3 text-center">Moderator</th>
                    <th className="px-4 py-3 text-center">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {adminPlayers.map(p => (
                    <tr key={p.id} className="border-b border-slate-800 hover:bg-slate-800/40 transition-colors">
                      <td className="px-4 py-3">
                        <Link to={`/player/${p.id}`} className="text-sky-400 hover:text-sky-300 hover:underline">
                          {p.display_name}
                        </Link>
                      </td>
                      <td className="px-4 py-3 text-center text-slate-300 text-xs font-mono">
                        {RANK_LABELS[Math.min(p.rank, RANK_LABELS.length - 1)]}
                      </td>
                      <td className="px-4 py-3 text-center text-slate-400">{p.prestige_points}</td>
                      <td className="px-4 py-3 text-center">
                        <button
                          onClick={() => togglePlayerAdmin(p.id, !p.is_admin)}
                          disabled={p.id === user?.id && p.is_admin}
                          title={p.id === user?.id && p.is_admin ? 'Cannot remove your own admin' : ''}
                          className={`relative w-10 h-5 rounded-full transition-colors ${
                            p.is_admin ? 'bg-amber-600' : 'bg-slate-600'
                          } ${p.id === user?.id && p.is_admin ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
                        >
                          <span className={`absolute top-0.5 w-4 h-4 bg-white rounded-full transition-transform ${
                            p.is_admin ? 'translate-x-5' : 'translate-x-0.5'
                          }`} />
                        </button>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <button
                          onClick={() => togglePlayerModerator(p.id, !p.is_moderator)}
                          className={`relative w-10 h-5 rounded-full transition-colors cursor-pointer ${
                            p.is_moderator ? 'bg-sky-600' : 'bg-slate-600'
                          }`}
                        >
                          <span className={`absolute top-0.5 w-4 h-4 bg-white rounded-full transition-transform ${
                            p.is_moderator ? 'translate-x-5' : 'translate-x-0.5'
                          }`} />
                        </button>
                      </td>
                      <td className="px-4 py-3 text-center">
                        {p.is_banned ? (
                          <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-red-500/20 text-red-400">Banned</span>
                        ) : (
                          <span className="text-xs font-medium px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400">Active</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
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

      {tab === 'announcements' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-3">
              <span className="text-sm text-slate-400">
                {newsletterCount} newsletter subscriber{newsletterCount !== 1 ? 's' : ''}
              </span>
            </div>
            <button
              onClick={() => {
                setAnnouncementForm(EMPTY_FORM)
                setEditingAnnouncementId(null)
                setShowAnnouncementForm(true)
                setPreviewMode(false)
              }}
              className="px-4 py-2 bg-sky-600 hover:bg-sky-500 text-white text-sm font-semibold rounded-lg transition-colors"
            >
              Create New
            </button>
          </div>

          {showAnnouncementForm && (
            <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 space-y-4">
              <h3 className="text-lg font-bold text-white">
                {editingAnnouncementId ? 'Edit Announcement' : 'New Announcement'}
              </h3>

              <div>
                <label className="block text-sm font-medium text-slate-300 mb-1">Title</label>
                <input
                  type="text"
                  value={announcementForm.title}
                  onChange={e => setAnnouncementForm(prev => ({ ...prev, title: e.target.value }))}
                  placeholder="Announcement title"
                  className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
                />
              </div>

              <div className="flex gap-4">
                <div className="flex-1">
                  <label className="block text-sm font-medium text-slate-300 mb-1">Category</label>
                  <select
                    value={announcementForm.category}
                    onChange={e => setAnnouncementForm(prev => ({ ...prev, category: e.target.value }))}
                    className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500"
                  >
                    <option value="news">News</option>
                    <option value="patch-notes">Patch Notes</option>
                    <option value="community">Community</option>
                  </select>
                </div>
                {announcementForm.category === 'patch-notes' && (
                  <div className="flex-1">
                    <label className="block text-sm font-medium text-slate-300 mb-1">Version</label>
                    <input
                      type="text"
                      value={announcementForm.version}
                      onChange={e => setAnnouncementForm(prev => ({ ...prev, version: e.target.value }))}
                      placeholder="v0.1.0"
                      className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 font-mono"
                    />
                  </div>
                )}
              </div>

              <div>
                <div className="flex items-center justify-between mb-1">
                  <label className="text-sm font-medium text-slate-300">Body</label>
                  <div className="flex rounded-lg bg-slate-800 p-0.5">
                    <button
                      onClick={() => setPreviewMode(false)}
                      className={`px-3 py-1 text-xs font-medium rounded-md transition-colors ${!previewMode ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'}`}
                    >
                      Edit
                    </button>
                    <button
                      onClick={() => setPreviewMode(true)}
                      className={`px-3 py-1 text-xs font-medium rounded-md transition-colors ${previewMode ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-white'}`}
                    >
                      Preview
                    </button>
                  </div>
                </div>
                {previewMode ? (
                  <div className="bg-slate-900 border border-slate-700 rounded-lg px-4 py-3 min-h-[200px]">
                    {announcementForm.body ? (
                      <ReactMarkdown components={MD_PREVIEW_COMPONENTS}>{announcementForm.body}</ReactMarkdown>
                    ) : (
                      <p className="text-slate-500 text-sm italic">Nothing to preview</p>
                    )}
                  </div>
                ) : (
                  <textarea
                    value={announcementForm.body}
                    onChange={e => setAnnouncementForm(prev => ({ ...prev, body: e.target.value }))}
                    placeholder="Write your announcement... (supports Markdown)"
                    rows={10}
                    className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 resize-y font-mono text-sm"
                  />
                )}
              </div>

              <div className="flex items-center gap-6">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={announcementForm.is_pinned}
                    onChange={e => setAnnouncementForm(prev => ({ ...prev, is_pinned: e.target.checked }))}
                    className="w-4 h-4 rounded border-slate-600 bg-slate-900"
                  />
                  <span className="text-sm text-slate-300">Pinned</span>
                </label>
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={announcementForm.is_published}
                    onChange={e => setAnnouncementForm(prev => ({ ...prev, is_published: e.target.checked }))}
                    className="w-4 h-4 rounded border-slate-600 bg-slate-900"
                  />
                  <span className="text-sm text-slate-300">Published</span>
                </label>
              </div>

              <div className="flex gap-2">
                <button
                  onClick={saveAnnouncement}
                  disabled={!announcementForm.title.trim() || !announcementForm.body.trim()}
                  className="px-5 py-2 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white font-semibold rounded-lg transition-colors"
                >
                  {editingAnnouncementId ? 'Update' : 'Create'}
                </button>
                <button
                  onClick={() => { setShowAnnouncementForm(false); setEditingAnnouncementId(null); setAnnouncementForm(EMPTY_FORM); setPreviewMode(false) }}
                  className="px-5 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          {adminAnnouncements.length === 0 && !showAnnouncementForm ? (
            <div className="text-center text-slate-500 py-16">No announcements yet. Create your first one!</div>
          ) : (
            adminAnnouncements.map(a => {
              const cmts = announcementComments[a.id] ?? []
              const isExpanded = expandedAnnouncementComments.has(a.id)
              return (
                <div key={a.id} className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-5">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                        a.category === 'news' ? 'bg-sky-500/20 text-sky-400' :
                        a.category === 'patch-notes' ? 'bg-amber-500/20 text-amber-400' :
                        'bg-emerald-500/20 text-emerald-400'
                      }`}>
                        {a.category === 'patch-notes' ? 'Patch Notes' : a.category === 'news' ? 'News' : 'Community'}
                      </span>
                      {a.version && <span className="text-xs text-sky-300 font-mono">{a.version}</span>}
                      <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                        a.is_published ? 'bg-emerald-500/20 text-emerald-400' : 'bg-amber-500/20 text-amber-400'
                      }`}>
                        {a.is_published ? 'Published' : 'Draft'}
                      </span>
                      {a.is_pinned && <span className="text-xs text-sky-400">Pinned</span>}
                    </div>
                    <span className="text-xs text-slate-500">{new Date(a.created_at).toLocaleDateString()}</span>
                  </div>
                  <h3 className="text-white font-medium mb-2">{a.title}</h3>
                  <p className="text-slate-400 text-sm line-clamp-2">{a.body}</p>

                  <div className="flex items-center justify-between mt-3 pt-3 border-t border-slate-700/30">
                    <button
                      onClick={() => toggleAnnouncementComments(a.id)}
                      className="text-xs text-slate-400 hover:text-slate-300 transition-colors"
                    >
                      {isExpanded ? 'Hide' : 'Show'} Comments{cmts.length > 0 ? ` (${cmts.length})` : ''}
                    </button>
                    <div className="flex gap-2">
                      <button
                        onClick={() => startEditAnnouncement(a)}
                        className="px-3 py-1 bg-slate-700 hover:bg-slate-600 text-white text-xs rounded-lg transition-colors"
                      >
                        Edit
                      </button>
                      <button
                        onClick={() => deleteAnnouncement(a.id)}
                        className="px-3 py-1 bg-red-600 hover:bg-red-500 text-white text-xs rounded-lg transition-colors"
                      >
                        Delete
                      </button>
                    </div>
                  </div>

                  {isExpanded && (
                    <div className="mt-3 space-y-2">
                      {cmts.length === 0 ? (
                        <p className="text-slate-500 text-xs">No comments on this announcement.</p>
                      ) : (
                        cmts.map(c => (
                          <div key={c.id} className="bg-slate-900/50 rounded-lg px-3 py-2 flex items-start justify-between">
                            <div>
                              <div className="flex items-center gap-2 mb-0.5">
                                <Link to={`/player/${c.user_id}`} className="text-xs font-medium text-sky-400 hover:underline">{c.display_name}</Link>
                                <span className="text-xs text-slate-500">{new Date(c.created_at).toLocaleDateString()}</span>
                              </div>
                              <p className="text-sm text-slate-300">{c.body}</p>
                            </div>
                            <button
                              onClick={() => deleteComment(c.id, a.id)}
                              className="text-red-400 hover:text-red-300 text-xs ml-3 shrink-0"
                            >
                              Delete
                            </button>
                          </div>
                        ))
                      )}
                    </div>
                  )}
                </div>
              )
            })
          )}
        </div>
      )}
    </div>
  )
}
