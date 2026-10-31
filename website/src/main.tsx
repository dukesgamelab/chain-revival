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
import { RegimentManage } from './pages/RegimentManage'
import { BugReport } from './pages/BugReport'
import { Feedback } from './pages/Feedback'
import { Privacy } from './pages/Privacy'
import { Terms } from './pages/Terms'
import { AuthProvider, useAuth } from './hooks/AuthProvider'
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
        {user && <Route path="regiment/manage" element={<RegimentManage />} />}
        <Route path="download" element={<Download />} />
        <Route path="appeal" element={<Appeal />} />
        {user && <Route path="bugs" element={<BugReport />} />}
        {user && <Route path="feedback" element={<Feedback />} />}
        <Route path="privacy" element={<Privacy />} />
        <Route path="terms" element={<Terms />} />
        {profile?.is_admin && <Route path="admin" element={<Admin />} />}
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  )
}

function NotFound() {
  return (
    <div className="max-w-4xl mx-auto px-4 py-24 text-center">
      <div className="text-6xl font-bold text-slate-700 mb-4">404</div>
      <h1 className="text-2xl font-bold mb-2">Page Not Found</h1>
      <p className="text-slate-400 mb-8">The page you're looking for doesn't exist or has been moved.</p>
      <a href="/" className="px-6 py-2 bg-sky-600 hover:bg-sky-500 text-white font-medium rounded-lg transition-colors inline-block">
        Back to Home
      </a>
    </div>
  )
}

createRoot(document.getElementById('root')!).render(
  <BrowserRouter>
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  </BrowserRouter>,
)
