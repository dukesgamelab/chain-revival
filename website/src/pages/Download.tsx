import { Link } from 'react-router-dom'
import { useSiteSettings } from '../hooks/useSiteSettings'

export function Download() {
  const { settings } = useSiteSettings()
  const hasDownload = settings.download_url !== ''
  const version = settings.game_version || 'TBD'

  return (
    <div className="max-w-4xl mx-auto px-4 py-16">
      <div className="text-center mb-12">
        <h1 className="text-4xl font-bold mb-4">Download Chain Revival</h1>
        <p className="text-xl text-slate-400">Tactical squad combat for Windows</p>
      </div>

      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-8 text-center mb-8">
        {hasDownload ? (
          <>
            <div className="inline-block bg-sky-900/30 border border-sky-700/50 rounded-lg px-4 py-1.5 text-sm text-sky-300 font-mono mb-6">
              v{version}
            </div>
            <h2 className="text-2xl font-bold mb-2">Windows Build</h2>
            <p className="text-slate-400 mb-6">
              Download the latest build and extract it to any folder. No installer required.
            </p>
            <a
              href={settings.download_url}
              className="inline-block px-8 py-3 bg-sky-600 hover:bg-sky-500 text-white font-semibold rounded-lg transition-colors text-lg"
            >
              Download (.zip)
            </a>
          </>
        ) : (
          <>
            <div className="text-6xl mb-4 opacity-60">&#128230;</div>
            <h2 className="text-2xl font-bold mb-2">Coming Soon</h2>
            <p className="text-slate-400 mb-2">
              The downloadable client is being prepared. Check back soon for the Windows release.
            </p>
            {version !== 'TBD' && (
              <p className="text-sm text-slate-500">Next version: v{version}</p>
            )}
          </>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
          <h3 className="text-lg font-semibold text-white mb-4">System Requirements</h3>
          <div className="space-y-3 text-sm">
            <div className="flex justify-between">
              <span className="text-slate-400">OS</span>
              <span className="text-slate-200">Windows 10 / 11 (64-bit)</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-400">CPU</span>
              <span className="text-slate-200">Any modern x86_64</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-400">RAM</span>
              <span className="text-slate-200">4 GB</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-400">GPU</span>
              <span className="text-slate-200">OpenGL 3.3 / Vulkan 1.0</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-400">Storage</span>
              <span className="text-slate-200">~200 MB</span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-400">Network</span>
              <span className="text-slate-200">Internet for online play</span>
            </div>
          </div>
        </div>

        <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-6">
          <h3 className="text-lg font-semibold text-white mb-4">Installation</h3>
          <ol className="space-y-3 text-sm text-slate-300">
            <li className="flex gap-3">
              <span className="text-sky-400 font-bold shrink-0">1.</span>
              Download the .zip file above
            </li>
            <li className="flex gap-3">
              <span className="text-sky-400 font-bold shrink-0">2.</span>
              Extract to any folder (e.g. <code className="text-xs bg-slate-900 px-1.5 py-0.5 rounded">C:\Games\ChainRevival</code>)
            </li>
            <li className="flex gap-3">
              <span className="text-sky-400 font-bold shrink-0">3.</span>
              Run <code className="text-xs bg-slate-900 px-1.5 py-0.5 rounded">ChainRevival.exe</code>
            </li>
            <li className="flex gap-3">
              <span className="text-sky-400 font-bold shrink-0">4.</span>
              Sign in with your website account to play online
            </li>
          </ol>
          <div className="mt-4 pt-4 border-t border-slate-700/50">
            <p className="text-xs text-slate-500">
              Windows SmartScreen may warn on first run. Click "More info" then "Run anyway" — the game is not code-signed yet.
            </p>
          </div>
        </div>
      </div>

      <div className="text-center">
        <p className="text-slate-400 mb-4">Don't have an account yet?</p>
        <Link
          to="/login"
          className="inline-block px-6 py-2 bg-slate-800 hover:bg-slate-700 text-white font-medium rounded-lg border border-slate-700 transition-colors"
        >
          Create Account
        </Link>
      </div>
    </div>
  )
}
