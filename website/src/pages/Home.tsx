import { Link } from 'react-router-dom'

const features = [
  {
    icon: '🎯',
    title: 'Tactical Combat',
    desc: 'Real-time squad-level tactics. Move, prone, face, and fire with precision. Every decision matters.',
  },
  {
    icon: '⭐',
    title: 'Rank & Prestige',
    desc: 'Earn Prestige Points from wins, kills, and terrain. Rise from Private to Captain through 10 military ranks.',
  },
  {
    icon: '🛡️',
    title: 'Regiments',
    desc: 'Form or join a regiment. Build your team, assign officer ranks, and fight together for shared glory.',
  },
  {
    icon: '🏆',
    title: 'Competitive Play',
    desc: 'Real-time leaderboards, match history, and stats tracking. Every battle counts toward your legacy.',
  },
]

export function Home() {
  return (
    <div>
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-b from-sky-900/20 via-slate-950 to-slate-950" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-sky-900/30 via-transparent to-transparent" />

        <div className="relative max-w-4xl mx-auto px-4 pt-24 pb-20 text-center">
          <h1 className="text-5xl md:text-7xl font-bold tracking-tight">
            <span className="text-sky-400">Chain</span> Revival
          </h1>
          <p className="text-xl md:text-2xl text-slate-400 mt-6 max-w-2xl mx-auto leading-relaxed">
            A tactical squad combat game inspired by the classic Chain of Command.
            Command your soldiers. Outmaneuver your enemy. Claim victory.
          </p>

          <div className="flex flex-col sm:flex-row gap-4 justify-center mt-10">
            <Link
              to="/download"
              className="px-8 py-3 bg-sky-600 hover:bg-sky-500 text-white font-semibold rounded-lg transition-colors text-lg"
            >
              Download Game
            </Link>
            <Link
              to="/leaderboard"
              className="px-8 py-3 bg-slate-800 hover:bg-slate-700 text-white font-semibold rounded-lg border border-slate-700 transition-colors text-lg"
            >
              View Leaderboard
            </Link>
          </div>
        </div>
      </section>

      <section className="max-w-6xl mx-auto px-4 py-20">
        <h2 className="text-3xl font-bold text-center mb-12">Built for Tactical Players</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {features.map(f => (
            <div
              key={f.title}
              className="rounded-xl bg-slate-800/50 border border-slate-700/50 p-6 hover:border-slate-600 transition-colors"
            >
              <div className="text-3xl mb-3">{f.icon}</div>
              <h3 className="text-lg font-semibold text-white mb-2">{f.title}</h3>
              <p className="text-slate-400 text-sm leading-relaxed">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="max-w-4xl mx-auto px-4 py-16 text-center">
        <h2 className="text-3xl font-bold mb-4">Ready to Play?</h2>
        <p className="text-slate-400 mb-8">
          Join the battle. Create your account, join a regiment, and prove yourself on the field.
        </p>
        <Link
          to="/login"
          className="inline-block px-8 py-3 bg-sky-600 hover:bg-sky-500 text-white font-semibold rounded-lg transition-colors"
        >
          Create Account
        </Link>
      </section>
    </div>
  )
}
