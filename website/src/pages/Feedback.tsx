import { useState } from 'react'
import { useOutletContext } from 'react-router-dom'
import { supabase } from '../lib/supabase'

const CATEGORIES = ['general', 'gameplay', 'balance', 'ui', 'maps', 'feature-request'] as const

export function Feedback() {
  const { user, profile } = useOutletContext<{
    user: { id: string; email?: string } | null
    profile: { display_name: string } | null
  }>()

  const [rating, setRating] = useState(0)
  const [hoverRating, setHoverRating] = useState(0)
  const [category, setCategory] = useState<string>('general')
  const [message, setMessage] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!message.trim()) {
      setError('Please write some feedback')
      return
    }
    if (rating === 0) {
      setError('Please select a rating')
      return
    }

    setLoading(true)
    setError(null)

    const { error: insertError } = await supabase
      .from('feedback')
      .insert({
        player_id: user!.id,
        display_name: profile?.display_name ?? null,
        rating,
        category,
        message: message.trim(),
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
        <h1 className="text-2xl font-bold mb-2">Feedback Received</h1>
        <p className="text-slate-400 mb-6">
          Thanks for your feedback! It helps us make Chain Revival better.
        </p>
        <button
          onClick={() => {
            setSubmitted(false)
            setRating(0)
            setCategory('general')
            setMessage('')
          }}
          className="px-6 py-2 bg-slate-700 hover:bg-slate-600 text-white font-medium rounded-lg transition-colors"
        >
          Send More Feedback
        </button>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-12">
      <h1 className="text-3xl font-bold mb-2 text-center">Alpha Feedback</h1>
      <p className="text-slate-400 text-center mb-8">
        Help shape Chain Revival &mdash; tell us what you think.
      </p>

      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-sm text-slate-400 mb-2">Overall Rating</label>
            <div className="flex gap-2">
              {[1, 2, 3, 4, 5].map(n => (
                <button
                  key={n}
                  type="button"
                  onClick={() => setRating(n)}
                  onMouseEnter={() => setHoverRating(n)}
                  onMouseLeave={() => setHoverRating(0)}
                  className="text-3xl transition-transform hover:scale-110"
                >
                  <span className={
                    (hoverRating || rating) >= n ? 'text-amber-400' : 'text-slate-600'
                  }>
                    &#9733;
                  </span>
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Category</label>
            <select
              value={category}
              onChange={e => setCategory(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500"
            >
              {CATEGORIES.map(c => (
                <option key={c} value={c}>
                  {c.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Your Feedback</label>
            <textarea
              value={message}
              onChange={e => setMessage(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 h-36 resize-none"
              placeholder="What do you like? What could be better? Any suggestions?"
              required
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
            {loading ? 'Submitting...' : 'Send Feedback'}
          </button>
        </form>
      </div>
    </div>
  )
}
