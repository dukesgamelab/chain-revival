import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import './index.css'
import App from './App'
import { Home } from './pages/Home'
import { Login } from './pages/Login'
import { Leaderboard } from './pages/Leaderboard'
import { Player } from './pages/Player'
import { Regiments } from './pages/Regiments'
import { Download } from './pages/Download'
import { Appeal } from './pages/Appeal'
import { Admin } from './pages/Admin'
import { useAuth } from './hooks/useAuth'
import { useSiteSettings } from './hooks/useSiteSettings'

function AppRoutes() {
  const { user, profile, signIn, signUp } = useAuth()
  const { settings } = useSiteSettings()

  return (
    <Routes>
      <Route path="/" element={<App />}>
        <Route index element={<Home />} />
        <Route path="login" element={<Login onSignIn={signIn} onSignUp={signUp} registrationEnabled={settings.registration_enabled} />} />
        <Route path="leaderboard" element={<Leaderboard userId={user?.id ?? null} />} />
        <Route path="player/:id" element={<Player />} />
        <Route path="regiments" element={<Regiments />} />
        <Route path="download" element={<Download />} />
        <Route path="appeal" element={<Appeal />} />
        {profile?.is_admin && <Route path="admin" element={<Admin />} />}
      </Route>
    </Routes>
  )
}

createRoot(document.getElementById('root')!).render(
  <BrowserRouter>
    <AppRoutes />
  </BrowserRouter>,
)
