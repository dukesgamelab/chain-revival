import { useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export function Footer() {
  const [email, setEmail] = useState('')
  const [subscribing, setSubscribing] = useState(false)
  const [subscribed, setSubscribed] = useState(false)

  async function handleSubscribe(e: React.FormEvent) {
    e.preventDefault()
    setSubscribing(true)
    const { error } = await supabase
      .from('newsletter_subscribers')
      .upsert(
        { email: email.trim().toLowerCase(), unsubscribed_at: null },
        { onConflict: 'email' },
      )
    setSubscribing(false)
    if (!error) { setSubscribed(true); setEmail('') }
  }

  return (
    <footer className="border-t border-slate-800 bg-slate-950 py-8 mt-auto">
      <div className="max-w-6xl mx-auto px-4 text-center text-slate-500 text-sm">
        {!subscribed ? (
          <form onSubmit={handleSubscribe} className="flex flex-col sm:flex-row items-center justify-center gap-2 mb-4">
            <span className="text-slate-400 text-sm">Get game updates:</span>
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="your@email.com"
              required
              className="bg-slate-900 border border-slate-700 rounded-lg px-3 py-1.5 text-sm text-white outline-none focus:ring-2 focus:ring-sky-500 placeholder-slate-600 w-52"
            />
            <button
              type="submit"
              disabled={subscribing}
              className="px-4 py-1.5 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 text-white text-sm font-medium rounded-lg transition-colors"
            >
              {subscribing ? '...' : 'Subscribe'}
            </button>
          </form>
        ) : (
          <p className="text-emerald-400 text-sm mb-4">Subscribed!</p>
        )}
        <p>&copy; {new Date().getFullYear()} Chain Revival. All rights reserved.</p>
        <p className="mt-1">Inspired by Chain of Command by 2AM Games</p>
        <div className="mt-3 flex justify-center gap-4">
          <Link to="/privacy" className="hover:text-slate-300 transition-colors">Privacy Policy</Link>
          <Link to="/terms" className="hover:text-slate-300 transition-colors">Terms of Service</Link>
        </div>
      </div>
    </footer>
  )
}
