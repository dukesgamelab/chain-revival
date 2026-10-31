export function Privacy() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="text-3xl font-bold mb-8">Privacy Policy</h1>
      <p className="text-slate-400 text-sm mb-8">Last updated: October 30, 2026</p>

      <div className="space-y-8 text-slate-300 text-sm leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-white mb-3">What We Collect</h2>
          <p>When you create an account, we collect your email address and a display name you choose. When you play matches, we record match results (wins, losses, kills, points) to power leaderboards and player profiles. We also store chat messages you send through the in-game and website chat systems.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">How We Use Your Data</h2>
          <ul className="list-disc list-inside space-y-1">
            <li>Account authentication and session management</li>
            <li>Displaying leaderboards, player profiles, and match history</li>
            <li>Enabling in-game and website chat</li>
            <li>Moderation and enforcing community rules</li>
            <li>Processing bug reports and feedback you submit</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Third-Party Services</h2>
          <p>We use the following third-party services:</p>
          <ul className="list-disc list-inside space-y-1 mt-2">
            <li><strong className="text-white">Supabase</strong> &mdash; database hosting and authentication</li>
            <li><strong className="text-white">Fly.io</strong> &mdash; game server and website hosting</li>
          </ul>
          <p className="mt-2">We do not sell, rent, or share your personal data with third parties for marketing purposes.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Data Retention</h2>
          <p>Your account data is retained as long as your account exists. Match history and chat messages are retained indefinitely for leaderboard and moderation purposes. You may request deletion of your account by contacting us.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Cookies</h2>
          <p>We use essential cookies for authentication only. We do not use tracking cookies or analytics.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Children's Privacy</h2>
          <p>Chain Revival is not intended for children under the age of 13. We do not knowingly collect personal information from children under 13.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Contact</h2>
          <p>For privacy-related questions or data deletion requests, use the bug report / feedback form on this website or contact us through the in-game chat.</p>
        </section>
      </div>
    </div>
  )
}
