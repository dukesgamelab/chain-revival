import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

interface LoginProps {
  onSignIn: (email: string, password: string) => Promise<{ error: string | null }>
  onSignUp: (email: string, password: string, displayName: string) => Promise<{ error: string | null }>
  registrationEnabled: boolean
}

export function Login({ onSignIn, onSignUp, registrationEnabled }: LoginProps) {
  const [mode, setMode] = useState<'signin' | 'signup' | 'forgot'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setSuccess(null)
    setLoading(true)

    if (mode === 'forgot') {
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/login`,
      })
      setLoading(false)
      if (resetError) {
        setError(resetError.message)
      } else {
        setSuccess('Password reset email sent. Check your inbox.')
      }
      return
    }

    let result: { error: string | null }
    if (mode === 'signin') {
      result = await onSignIn(email, password)
    } else {
      if (!displayName.trim()) {
        setError('Display name is required')
        setLoading(false)
        return
      }
      result = await onSignUp(email, password, displayName.trim())
    }

    setLoading(false)
    if (result.error) {
      setError(result.error)
    } else {
      navigate('/leaderboard')
    }
  }

  return (
    <div className="min-h-[calc(100vh-8rem)] flex items-center justify-center px-4">
      <div className="w-full max-w-md">
        <h1 className="text-3xl font-bold text-center mb-8">
          {mode === 'forgot' ? 'Reset Password' : mode === 'signin' ? 'Sign In' : 'Create Account'}
        </h1>

        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
          {mode === 'forgot' ? (
            <button
              onClick={() => { setMode('signin'); setError(null); setSuccess(null) }}
              className="text-sm text-sky-400 hover:text-sky-300 mb-6 block"
            >
              &larr; Back to Sign In
            </button>
          ) : (
            <div className="flex rounded-lg bg-slate-900 p-1 mb-6">
              <button
                onClick={() => { setMode('signin'); setError(null); setSuccess(null) }}
                className={`flex-1 py-2 text-sm font-medium rounded-md transition-colors ${
                  mode === 'signin' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-slate-300'
                }`}
              >
                Sign In
              </button>
              <button
                onClick={() => { setMode('signup'); setError(null); setSuccess(null) }}
                disabled={!registrationEnabled}
                className={`flex-1 py-2 text-sm font-medium rounded-md transition-colors ${
                  mode === 'signup' ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-slate-300'
                } ${!registrationEnabled ? 'opacity-50 cursor-not-allowed' : ''}`}
              >
                Sign Up
              </button>
            </div>
          )}

          {!registrationEnabled && mode === 'signup' && (
            <div className="text-amber-400 text-sm text-center mb-4">
              Registration is currently disabled.
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            {mode === 'signup' && (
              <div>
                <label className="block text-sm text-slate-400 mb-1">Display Name</label>
                <input
                  type="text"
                  value={displayName}
                  onChange={e => setDisplayName(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent placeholder-slate-600"
                  placeholder="Your in-game name"
                  maxLength={30}
                />
              </div>
            )}

            <div>
              <label className="block text-sm text-slate-400 mb-1">Email</label>
              <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent placeholder-slate-600"
                placeholder="you@example.com"
                required
              />
            </div>

            {mode !== 'forgot' && (
              <div>
                <label className="block text-sm text-slate-400 mb-1">Password</label>
                <input
                  type="password"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-2.5 text-white outline-none focus:ring-2 focus:ring-sky-500 focus:border-transparent placeholder-slate-600"
                  placeholder="••••••••"
                  required
                  minLength={6}
                />
              </div>
            )}

            {mode === 'signin' && (
              <button
                type="button"
                onClick={() => { setMode('forgot'); setError(null); setSuccess(null) }}
                className="text-sm text-slate-400 hover:text-sky-400 transition-colors"
              >
                Forgot password?
              </button>
            )}

            {success && (
              <div className="text-emerald-400 text-sm bg-emerald-400/10 border border-emerald-400/20 rounded-lg px-4 py-2">
                {success}
              </div>
            )}

            {error && (
              <div className="text-red-400 text-sm bg-red-400/10 border border-red-400/20 rounded-lg px-4 py-2">
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading || (mode === 'signup' && !registrationEnabled)}
              className="w-full py-2.5 bg-sky-600 hover:bg-sky-500 disabled:bg-slate-700 disabled:text-slate-500 text-white font-semibold rounded-lg transition-colors"
            >
              {loading ? 'Please wait...' : mode === 'forgot' ? 'Send Reset Link' : mode === 'signin' ? 'Sign In' : 'Create Account'}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
