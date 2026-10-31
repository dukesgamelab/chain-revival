import { useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { supabase } from '../lib/supabase'

const CATEGORIES = ['gameplay', 'ui', 'multiplayer', 'performance', 'crash', 'other'] as const
const SEVERITIES = ['low', 'medium', 'high', 'critical'] as const

export function BugReport() {
  const { user, profile } = useOutletContext<{
    user: { id: string; email?: string } | null
    profile: { display_name: string } | null
  }>()

  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [category, setCategory] = useState<string>('gameplay')
  const [severity, setSeverity] = useState<string>('medium')
  const [steps, setSteps] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim() || !description.trim()) {
      setError('Title and description are required')
      return
    }
    setLoading(true)
    setError(null)

    const { error: insertError } = await supabase
      .from('bug_reports')
      .insert({
        player_id: user!.id,
        display_name: profile?.display_name ?? null,
        email: user!.email ?? null,
        title: title.trim(),
        description: description.trim(),
        category,
        severity,
        steps_to_reproduce: steps.trim() || null,
      })

    setLoading(false)
    if (insertError) {
      setError(insertError.message)
    } else {
      setSubmitted(true)
    }
  }

  if (submitted) {
    return (
      <div className="max-w-lg mx-auto px-4 py-16 text-center">
        <div className="text-5xl mb-4 text-emerald-400">&#10003;</div>
        <h1 className="text-2xl font-bold mb-2">Bug Report Submitted</h1>
        <p className="text-slate-400 mb-6">
          Thanks for helping improve Chain Revival! We'll look into this.
        </p>
        <button
          onClick={() => {
            setSubmitted(false)
            setTitle('')
            setDescription('')
            setCategory('gameplay')
            setSeverity('medium')
            setSteps('')
          }}
          className="px-6 py-2 bg-slate-700 hover:bg-slate-600 text-white font-medium rounded-lg transition-colors"
        >
          Report Another Bug
        </button>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-12">
      <h1 className="text-3xl font-bold mb-2 text-center">Report a Bug</h1>
      <p className="text-slate-400 text-center mb-8">
        Found something wrong? Let us know so we can fix it.
      </p>

      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm text-slate-400 mb-1">Title</label>
            <input
              type="text"
              value={title}
              onChange={e => setTitle(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
              placeholder="Short description of the bug"
              required
              maxLength={200}
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm text-slate-400 mb-1">Category</label>
              <select
                value={category}
                onChange={e => setCategory(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500"
              >
                {CATEGORIES.map(c => (
                  <option key={c} value={c}>
                    {c.charAt(0).toUpperCase() + c.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm text-slate-400 mb-1">Severity</label>
              <select
                value={severity}
                onChange={e => setSeverity(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500"
              >
                {SEVERITIES.map(s => (
                  <option key={s} value={s}>
                    {s.charAt(0).toUpperCase() + s.slice(1)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Description</label>
            <textarea
              value={description}
              onChange={e => setDescription(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 h-28 resize-none"
              placeholder="What happened? What did you expect to happen?"
              required
              maxLength={2000}
            />
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Steps to Reproduce (optional)</label>
            <textarea
              value={steps}
              onChange={e => setSteps(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 h-24 resize-none"
              placeholder="1. Go to...&#10;2. Click on...&#10;3. See error"
              maxLength={2000}
            />
          </div>

          {error && (
            <div className="text-red-400 text-sm bg-red-400/10 border border-red-400/20 rounded-lg px-4 py-2">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white font-semibold rounded-lg transition-colors"
          >
            {loading ? 'Submitting...' : 'Submit Bug Report'}
          </button>
        </form>
      </div>
    </div>
  )
}
