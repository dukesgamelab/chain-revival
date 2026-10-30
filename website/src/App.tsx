import { Outlet, useLocation } from 'react-router-dom'
import { Nav } from './components/Nav'
import { Footer } from './components/Footer'
import { GlobalChat } from './components/GlobalChat'
import { useAuth } from './hooks/useAuth'
import { useSiteSettings } from './hooks/useSiteSettings'

export default function App() {
  const { user, profile, signOut } = useAuth()
  const { settings } = useSiteSettings()
  const location = useLocation()
  const isLoginPage = location.pathname === '/login'

  return (
    <div className="flex flex-col min-h-dvh">
      <Nav user={user} profile={profile} onSignOut={signOut} />

      <main className="flex-1">
        <Outlet context={{ user, profile }} />
      </main>

      <Footer />

      {user && profile && settings.chat_enabled && !isLoginPage && (
        <GlobalChat
          userId={user.id}
          displayName={profile.display_name}
          regimentTag={profile.regiment_tag}
        />
      )}
    </div>
  )
}
