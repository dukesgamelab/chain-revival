import { useEffect, useState, useCallback } from 'react'
import { Link, useOutletContext } from 'react-router-dom'
import ReactMarkdown from 'react-markdown'
import { supabase } from '../lib/supabase'

interface Announcement {
  id: string
  title: string
  body: string
  category: string
  version: string | null
  is_pinned: boolean
  created_at: string
}

interface Comment {
  id: string
  announcement_id: string
  user_id: string
  display_name: string
  body: string
  created_at: string
}

type TabKey = 'all' | 'news' | 'patch-notes' | 'community'

const CATEGORY_STYLES: Record<string, { bg: string; text: string; label: string }> = {
  'news': { bg: 'bg-sky-500/20', text: 'text-sky-400', label: 'News' },
  'patch-notes': { bg: 'bg-amber-500/20', text: 'text-amber-400', label: 'Patch Notes' },
  'community': { bg: 'bg-emerald-500/20', text: 'text-emerald-400', label: 'Community' },
}

const TABS: { key: TabKey; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'news', label: 'News' },
  { key: 'patch-notes', label: 'Patch Notes' },
  { key: 'community', label: 'Community' },
]

const MD_COMPONENTS = {
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

function timeAgo(dateStr: string): string {
  const seconds = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000)
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d ago`
  return new Date(dateStr).toLocaleDateString()
}

export function Announcements() {
  const { user, profile } = useOutletContext<{ user: { id: string } | null; profile: { display_name: string } | null }>()
  const [announcements, setAnnouncements] = useState<Announcement[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<TabKey>('all')

  const [comments, setComments] = useState<Record<string, Comment[]>>({})
  const [expandedComments, setExpandedComments] = useState<Set<string>>(new Set())
  const [commentInputs, setCommentInputs] = useState<Record<string, string>>({})
  const [postingComment, setPostingComment] = useState<string | null>(null)

  const [email, setEmail] = useState('')
  const [subscribing, setSubscribing] = useState(false)
  const [subscribed, setSubscribed] = useState(false)
  const [subError, setSubError] = useState<string | null>(null)

  useEffect(() => {
    async function load() {
      const { data } = await supabase
        .from('announcements')
        .select('id, title, body, category, version, is_pinned, created_at')
        .eq('is_published', true)
        .order('is_pinned', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(50)
      if (data) setAnnouncements(data)
      setLoading(false)
    }
    load()
  }, [])

  useEffect(() => {
    const channel = supabase
      .channel(`announcement-comments-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'announcement_comments',
      } as never, (payload) => {
        const newComment = payload.new as Comment
        setComments(prev => ({
          ...prev,
          [newComment.announcement_id]: [...(prev[newComment.announcement_id] ?? []), newComment],
        }))
      })
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, [])

  const loadComments = useCallback(async (announcementId: string) => {
    if (comments[announcementId]) return
    const { data } = await supabase
      .from('announcement_comments')
      .select('id, announcement_id, user_id, display_name, body, created_at')
      .eq('announcement_id', announcementId)
      .order('created_at', { ascending: true })
    if (data) setComments(prev => ({ ...prev, [announcementId]: data }))
  }, [comments])

  function toggleComments(announcementId: string) {
    setExpandedComments(prev => {
      const next = new Set(prev)
      if (next.has(announcementId)) {
        next.delete(announcementId)
      } else {
        next.add(announcementId)
        loadComments(announcementId)
      }
      return next
    })
  }

  async function postComment(announcementId: string) {
    const body = (commentInputs[announcementId] ?? '').trim()
    if (!body || !user || !profile) return
    setPostingComment(announcementId)
    await supabase.from('announcement_comments').insert({
      announcement_id: announcementId,
      user_id: user.id,
      display_name: profile.display_name,
      body,
    })
    setCommentInputs(prev => ({ ...prev, [announcementId]: '' }))
    setPostingComment(null)
  }

  async function handleSubscribe(e: React.FormEvent) {
    e.preventDefault()
    setSubscribing(true)
    setSubError(null)
    const { error } = await supabase
      .from('newsletter_subscribers')
      .upsert(
        { email: email.trim().toLowerCase(), player_id: user?.id ?? null, unsubscribed_at: null },
        { onConflict: 'email' },
      )
    setSubscribing(false)
    if (error) setSubError(error.message)
    else { setSubscribed(true); setEmail('') }
  }

  const filtered = activeTab === 'all'
    ? announcements
    : announcements.filter(a => a.category === activeTab)

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div className="mb-8">
        <h1 className="text-3xl font-bold mb-2">News &amp; Updates</h1>
        <p className="text-slate-400">Stay up to date with Chain Revival development.</p>
      </div>

      <div className="flex flex-wrap rounded-lg bg-slate-800 p-1 mb-6 w-fit gap-0.5">
        {TABS.map(t => (
          <button
            key={t.key}
            onClick={() => setActiveTab(t.key)}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-colors ${
              activeTab === t.key
                ? 'bg-slate-700 text-white'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="text-slate-500 py-16 text-center">Loading...</p>
      ) : filtered.length === 0 ? (
        <p className="text-slate-500 py-16 text-center">No announcements yet. Check back soon!</p>
      ) : (
        <div className="space-y-6">
          {filtered.map(a => {
            const style = CATEGORY_STYLES[a.category] ?? CATEGORY_STYLES['news']
            const announcementComments = comments[a.id] ?? []
            const isExpanded = expandedComments.has(a.id)

            return (
              <article
                key={a.id}
                className={`bg-slate-800/60 border rounded-xl p-6 ${
                  a.is_pinned ? 'border-sky-700/50' : 'border-slate-700/50'
                }`}
              >
                <div className="flex items-center gap-3 mb-3">
                  <span className={`${style.bg} ${style.text} text-xs font-medium px-2.5 py-0.5 rounded-full`}>
                    {style.label}
                  </span>
                  {a.is_pinned && (
                    <span className="text-sky-400 text-xs font-medium">Pinned</span>
                  )}
                  {a.version && (
                    <span className="bg-sky-900/30 border border-sky-700/50 rounded-lg px-2 py-0.5 text-sm text-sky-300 font-mono">
                      {a.version}
                    </span>
                  )}
                  <span className="text-slate-500 text-xs ml-auto">
                    {new Date(a.created_at).toLocaleDateString()}
                  </span>
                </div>

                <h2 className="text-xl font-bold text-white mb-3">{a.title}</h2>

                <div className="prose-sm">
                  <ReactMarkdown components={MD_COMPONENTS}>{a.body}</ReactMarkdown>
                </div>

                {/* Comments */}
                <div className="mt-4 pt-4 border-t border-slate-700/50">
                  <button
                    onClick={() => toggleComments(a.id)}
                    className="text-sm text-slate-400 hover:text-slate-300 transition-colors"
                  >
                    {isExpanded ? 'Hide' : 'Show'} Comments
                    {announcementComments.length > 0 && ` (${announcementComments.length})`}
                  </button>

                  {isExpanded && (
                    <div className="mt-3 space-y-3">
                      {announcementComments.length === 0 && (
                        <p className="text-slate-500 text-sm">No comments yet. Be the first!</p>
                      )}
                      {announcementComments.map(c => (
                        <div key={c.id} className="bg-slate-900/50 rounded-lg px-4 py-3">
                          <div className="flex items-center gap-2 mb-1">
                            <Link to={`/player/${c.user_id}`} className="text-sm font-medium text-sky-400 hover:underline">
                              {c.display_name}
                            </Link>
                            <span className="text-xs text-slate-500">{timeAgo(c.created_at)}</span>
                          </div>
                          <p className="text-sm text-slate-300">{c.body}</p>
                        </div>
                      ))}

                      {user && profile ? (
                        <div className="flex gap-2 mt-2">
                          <textarea
                            value={commentInputs[a.id] ?? ''}
                            onChange={e => setCommentInputs(prev => ({ ...prev, [a.id]: e.target.value }))}
                            placeholder="Write a comment..."
                            rows={2}
                            className="flex-1 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 resize-none"
                          />
                          <button
                            onClick={() => postComment(a.id)}
                            disabled={!(commentInputs[a.id] ?? '').trim() || postingComment === a.id}
                            className="self-end px-4 py-2 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white text-sm font-medium rounded-lg transition-colors"
                          >
                            {postingComment === a.id ? '...' : 'Post'}
                          </button>
                        </div>
                      ) : (
                        <p className="text-sm text-slate-500">
                          <Link to="/login" className="text-sky-400 hover:underline">Sign in</Link> to comment.
                        </p>
                      )}
                    </div>
                  )}
                </div>
              </article>
            )
          })}
        </div>
      )}

      {/* Newsletter Signup */}
      <div className="mt-12 bg-slate-800/60 border border-slate-700/50 rounded-xl p-6 text-center">
        <h3 className="text-lg font-bold text-white mb-2">Stay in the Loop</h3>
        <p className="text-slate-400 text-sm mb-4">Get notified about major updates and patch notes.</p>
        {subscribed ? (
          <p className="text-emerald-400 font-medium">Subscribed! You'll hear from us soon.</p>
        ) : (
          <form onSubmit={handleSubscribe} className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="your@email.com"
              required
              className="bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 w-full sm:w-72"
            />
            <button
              type="submit"
              disabled={subscribing}
              className="px-6 py-2.5 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 text-white font-semibold rounded-lg transition-colors"
            >
              {subscribing ? 'Subscribing...' : 'Subscribe'}
            </button>
          </form>
        )}
        {subError && <p className="text-red-400 text-sm mt-2">{subError}</p>}
        <p className="text-slate-500 text-xs mt-3">We'll only email about major updates. Unsubscribe any time.</p>
      </div>
    </div>
  )
}
