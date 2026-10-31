import { Link } from 'react-router-dom'

export function Footer() {
  return (
    <footer className="border-t border-slate-800 bg-slate-950 py-8 mt-auto">
      <div className="max-w-6xl mx-auto px-4 text-center text-slate-500 text-sm">
        <p>&copy; {new Date().getFullYear()} Chain Revival. All rights reserved.</p>
        <p className="mt-1">Inspired by Chain of Command by 2AM Games</p>
        <div className="mt-3 flex justify-center gap-4">
          <Link to="/privacy" className="hover:text-slate-300 transition-colors">Privacy Policy</Link>
          <Link to="/terms" className="hover:text-slate-300 transition-colors">Terms of Service</Link>
        </div>
      </div>
    </footer>
  )
}
