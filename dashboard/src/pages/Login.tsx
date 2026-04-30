interface LoginProps {
  onLogin: () => void
}

export default function Login({ onLogin }: LoginProps) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-950">
      <div className="w-full max-w-sm p-8 bg-gray-900 rounded-xl shadow-lg border border-gray-800">
        <div className="text-center mb-8">
          <div className="w-12 h-12 rounded-lg bg-gradient-to-br from-emerald-500 to-emerald-700 flex items-center justify-center font-bold text-lg mx-auto mb-4">
            SW
          </div>
          <h1 className="text-2xl font-bold text-white">Auction Dashboard</h1>
          <p className="text-gray-500 mt-2 text-sm">
            Sign in to view auction analytics
          </p>
        </div>
        <button
          onClick={onLogin}
          className="w-full py-3 px-4 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg transition-colors font-medium"
        >
          Sign in with Netlify Identity
        </button>
      </div>
    </div>
  )
}
