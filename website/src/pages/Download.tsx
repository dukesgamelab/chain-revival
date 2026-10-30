import { Link } from 'react-router-dom'

export function Download() {
  return (
    <div className="max-w-4xl mx-auto px-4 py-16">
      <div className="text-center mb-12">
        <h1 className="text-4xl font-bold mb-4">Download Chain Revival</h1>
        <p className="text-xl text-slate-400">Get ready for tactical squad combat</p>
      </div>

      <div className="bg-slate-800/60 border border-slate-700/50 rounded-xl p-8 text-center mb-8">
        <div className="text-6xl mb-4">🎮</div>
        <h2 className="text-2xl font-bold mb-2">Coming Soon</h2>
        <p className="text-slate-400 mb-6">
          The downloadable client is being prepared. Check back soon for the Windows release.
        </p>

        <div className="inline-block bg-slate-900 rounded-lg px-6 py-4 text-left">
          <h3 className="text-sm font-semibold text-slate-300 mb-3">System Requirements</h3>
          <div className="space-y-2 text-sm text-slate-400">
            <div className="flex justify-between gap-8">
              <span>OS</span>
              <span className="text-slate-300">Windows 10 / 11</span>
            </div>
            <div className="flex justify-between gap-8">
              <span>Engine</span>
              <span className="text-slate-300">Godot 4.7+</span>
            </div>
            <div className="flex justify-between gap-8">
              <span>Network</span>
              <span className="text-slate-300">Internet connection for online play</span>
            </div>
          </div>
        </div>
      </div>

      <div className="text-center">
        <p className="text-slate-400 mb-4">While you wait, check out the competition:</p>
        <Link
          to="/leaderboard"
          className="inline-block px-6 py-2 bg-sky-600 hover:bg-sky-500 text-white font-medium rounded-lg transition-colors"
        >
          View Leaderboard
        </Link>
      </div>
    </div>
  )
}
