import { Link, useLocation } from 'react-router-dom'

interface User {
  id: string
  email: string
  name?: string
  avatarUrl?: string
  token: string
}

interface LayoutProps {
  user: User | null
  onLogout: () => void
  children: React.ReactNode
}

export default function Layout({ user, onLogout, children }: LayoutProps) {
  const location = useLocation()

  const navLinks = [
    { href: '/', label: 'Overview' },
    { href: '/auctions', label: 'Auctions' },
  ]

  return (
    <>
      <nav className="border-b border-gray-800 bg-gray-900/80 backdrop-blur sticky top-0 z-50">
        <div className="max-w-[1400px] mx-auto px-6 h-14 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-emerald-500 to-emerald-700 flex items-center justify-center font-bold text-sm">
              SW
            </div>
            <span className="font-semibold text-lg">Auction Dashboard</span>
          </Link>
          <div className="flex items-center gap-6 text-sm text-gray-400">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                to={link.href}
                className={`hover:text-white transition-colors ${
                  location.pathname === link.href ? 'text-white' : ''
                }`}
              >
                {link.label}
              </Link>
            ))}
            <span className="px-2 py-1 rounded bg-emerald-900/50 text-emerald-400 text-xs font-medium">
              Athena
            </span>
            <div className="flex items-center gap-3 ml-2 pl-4 border-l border-gray-800">
              <span className="text-xs text-gray-500">
                {user?.name || user?.email}
              </span>
              <button
                onClick={onLogout}
                className="text-xs text-gray-500 hover:text-white transition-colors"
              >
                Sign out
              </button>
            </div>
          </div>
        </div>
      </nav>
      <main className="max-w-[1400px] mx-auto px-6 py-8">{children}</main>
    </>
  )
}
