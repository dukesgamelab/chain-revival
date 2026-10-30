export function Footer() {
  return (
    <footer className="border-t border-slate-800 bg-slate-950 py-8 mt-auto">
      <div className="max-w-6xl mx-auto px-4 text-center text-slate-500 text-sm">
        <p>&copy; {new Date().getFullYear()} Chain Revival. All rights reserved.</p>
        <p className="mt-1">Inspired by Chain of Command by 2AM Games</p>
      </div>
    </footer>
  )
}
