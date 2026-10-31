import { Link, useLocation } from 'react-router-dom'
import { useState } from 'react'
import { useSiteSettings } from '../hooks/useSiteSettings'

interface NavProps {
  user: { id: string; email?: string } | null
  profile: { display_name: string; is_admin: boolean } | null
  onSignOut: () => void
}

export function Nav({ user, profile, onSignOut }: NavProps) {
  const [menuOpen, setMenuOpen] = useState(false)
  const location = useLocation()
  const { settings } = useSiteSettings()

  const links = [
    { to: '/', label: 'Home', always: true },
    { to: '/leaderboard', label: 'Leaderboard', always: false, setting: 'leaderboard_enabled' as const },
    { to: '/regiments', label: 'Regiments', always: false, setting: 'regiments_enabled' as const },
    { to: '/download', label: 'Download', always: false, setting: 'download_enabled' as const },
    { to: '/bugs', label: 'Bug Report', always: false, setting: 'bugreports_enabled' as const, auth: true },
    { to: '/feedback', label: 'Feedback', always: false, setting: 'feedback_enabled' as const, auth: true },
  ]

  const visibleLinks = links.filter(l => {
    if (l.auth && !user) return false
    return l.always || settings[l.setting!]
  })

  function isActive(path: string) {
    if (path === '/') return location.pathname === '/'
    return location.pathname.startsWith(path)
  }

  return (
    <nav className="sticky top-0 z-50 border-b border-slate-800 bg-slate-950/90 backdrop-blur-md">
      <div className="max-w-6xl mx-auto px-4 flex items-center justify-between h-16">
        <Link to="/" className="flex items-center gap-2 text-white font-bold text-lg hover:text-sky-400 transition-colors">
          <span className="text-sky-400">&#9670;</span>
          Chain Revival
        </Link>

        <div className="hidden md:flex items-center gap-1">
          {visibleLinks.map(link => (
            <Link
              key={link.to}
              to={link.to}
              className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                isActive(link.to)
                  ? 'bg-slate-800 text-white'
                  : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
              }`}
            >
              {link.label}
            </Link>
          ))}
          {profile?.is_admin && (
            <Link
              to="/admin"
              className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                isActive('/admin')
                  ? 'bg-amber-900/50 text-amber-300'
                  : 'text-amber-400/70 hover:text-amber-300 hover:bg-amber-900/30'
              }`}
            >
              Admin
            </Link>
          )}
        </div>

        <div className="hidden md:flex items-center gap-3">
          {user ? (
            <>
              <Link to={`/player/${user.id}`} className="text-sm text-slate-300 hover:text-white transition-colors">
                {profile?.display_name ?? user.email}
              </Link>
              <button
                onClick={onSignOut}
                className="text-sm text-slate-500 hover:text-slate-300 transition-colors"
              >
                Sign Out
              </button>
            </>
          ) : (
            <Link
              to="/login"
              className="px-4 py-2 rounded-md bg-sky-600 text-white text-sm font-medium hover:bg-sky-500 transition-colors"
            >
              Sign In
            </Link>
          )}
        </div>

        <button
          className="md:hidden text-slate-400 hover:text-white p-2"
          onClick={() => setMenuOpen(!menuOpen)}
          aria-label="Toggle menu"
        >
          <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            {menuOpen ? (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            ) : (
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            )}
          </svg>
        </button>
      </div>

      {menuOpen && (
        <div className="md:hidden border-t border-slate-800 bg-slate-950 px-4 pb-4">
          {visibleLinks.map(link => (
            <Link
              key={link.to}
              to={link.to}
              onClick={() => setMenuOpen(false)}
              className={`block px-3 py-2 rounded-md text-sm font-medium mt-1 ${
                isActive(link.to) ? 'bg-slate-800 text-white' : 'text-slate-400'
              }`}
            >
              {link.label}
            </Link>
          ))}
          {profile?.is_admin && (
            <Link
              to="/admin"
              onClick={() => setMenuOpen(false)}
              className="block px-3 py-2 rounded-md text-sm font-medium mt-1 text-amber-400"
            >
              Admin
            </Link>
          )}
          <div className="mt-3 pt-3 border-t border-slate-800">
            {user ? (
              <button onClick={() => { onSignOut(); setMenuOpen(false) }} className="text-sm text-slate-400">
                Sign Out ({profile?.display_name})
              </button>
            ) : (
              <Link to="/login" onClick={() => setMenuOpen(false)} className="text-sm text-sky-400">
                Sign In
              </Link>
            )}
          </div>
        </div>
      )}
    </nav>
  )
}
