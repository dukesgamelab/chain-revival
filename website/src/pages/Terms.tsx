export function Terms() {
  return (
    <div className="max-w-3xl mx-auto px-4 py-12">
      <h1 className="text-3xl font-bold mb-8">Terms of Service</h1>
      <p className="text-slate-400 text-sm mb-8">Last updated: October 30, 2026</p>

      <div className="space-y-8 text-slate-300 text-sm leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Acceptance</h2>
          <p>By creating an account or playing Chain Revival, you agree to these terms. If you do not agree, do not use the service.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">The Service</h2>
          <p>Chain Revival is a free-to-play tactical squad combat game currently in alpha. The game includes online multiplayer, leaderboards, regiments, and chat features. The service is provided "as is" with no guarantees of availability or uptime.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Accounts</h2>
          <ul className="list-disc list-inside space-y-1">
            <li>You must provide a valid email address to create an account</li>
            <li>You are responsible for keeping your account credentials secure</li>
            <li>One account per person &mdash; alt accounts are not permitted</li>
            <li>You must be at least 13 years old to create an account</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Conduct</h2>
          <p>You agree not to:</p>
          <ul className="list-disc list-inside space-y-1 mt-2">
            <li>Cheat, exploit bugs, or use unauthorized third-party tools</li>
            <li>Harass, abuse, or threaten other players</li>
            <li>Spam or flood chat channels</li>
            <li>Impersonate other players or staff</li>
            <li>Attempt to disrupt the game server or website</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Moderation</h2>
          <p>We reserve the right to ban, mute, or restrict accounts that violate these terms. Banned players may submit an appeal through the website. Moderation decisions are at our discretion.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Alpha Status</h2>
          <p>Chain Revival is in alpha testing. This means:</p>
          <ul className="list-disc list-inside space-y-1 mt-2">
            <li>Features may change, break, or be removed without notice</li>
            <li>Stats, ranks, and progress may be reset during development</li>
            <li>The game may have bugs &mdash; please report them</li>
            <li>Service interruptions should be expected</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Intellectual Property</h2>
          <p>Chain Revival is inspired by Chain of Command by 2AM Games. All original content, code, and assets are the property of their respective creators. User-generated content (chat messages, display names, regiment descriptions) remains yours, but you grant us a license to display it within the service.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Limitation of Liability</h2>
          <p>Chain Revival is provided "as is" without warranty. We are not liable for any damages arising from the use of the service, including loss of data or progress.</p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-white mb-3">Changes to Terms</h2>
          <p>We may update these terms at any time. Continued use of the service after changes constitutes acceptance of the new terms.</p>
        </section>
      </div>
    </div>
  )
}
