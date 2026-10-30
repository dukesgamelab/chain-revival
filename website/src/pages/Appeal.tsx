import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export function Appeal() {
  const [searchParams] = useSearchParams()
  const playerId = searchParams.get('id') ?? ''
  const [email, setEmail] = useState('')
  const [appealText, setAppealText] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!playerId || !email || !appealText.trim()) {
      setError('All fields are required')
      return
    }

    setLoading(true)
    setError(null)

    const { error: insertError } = await supabase
      .from('ban_appeals')
      .insert({
        player_id: playerId,
        email,
        appeal_text: appealText.trim(),
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
        <div className="text-5xl mb-4">✓</div>
        <h1 className="text-2xl font-bold mb-2">Appeal Submitted</h1>
        <p className="text-slate-400">Your appeal has been received and will be reviewed by an administrator.</p>
      </div>
    )
  }

  return (
    <div className="max-w-lg mx-auto px-4 py-16">
      <h1 className="text-3xl font-bold mb-2 text-center">Ban Appeal</h1>
      <p className="text-slate-400 text-center mb-8">
        If you believe your ban was issued in error, submit an appeal below.
      </p>

      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm text-slate-400 mb-1">Player ID</label>
            <input
              type="text"
              value={playerId}
              readOnly
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-slate-500 cursor-not-allowed"
            />
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Email</label>
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600"
              placeholder="Your account email"
              required
            />
          </div>

          <div>
            <label className="block text-sm text-slate-400 mb-1">Appeal</label>
            <textarea
              value={appealText}
              onChange={e => setAppealText(e.target.value)}
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 h-32 resize-none"
              placeholder="Explain why you believe your ban should be reconsidered..."
              required
              maxLength={1000}
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
            {loading ? 'Submitting...' : 'Submit Appeal'}
          </button>
        </form>
      </div>
    </div>
  )
}
