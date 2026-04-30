import { Routes, Route } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import Login from './pages/Login'
import Layout from './components/Layout'
import OverviewPage from './pages/Overview'
import AuctionFeedPage from './pages/AuctionFeed'
import AuctionDetailPage from './pages/AuctionDetail'

function App() {
  const { isLoading, isAuthenticated, user, login, logout } = useAuth()

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-950">
        <div className="animate-pulse text-gray-500">Loading...</div>
      </div>
    )
  }

  if (!isAuthenticated) {
    return <Login onLogin={login} />
  }

  return (
    <Layout user={user} onLogout={logout}>
      <Routes>
        <Route path="/" element={<OverviewPage />} />
        <Route path="/auctions" element={<AuctionFeedPage />} />
        <Route path="/auctions/:auctionId" element={<AuctionDetailPage />} />
      </Routes>
    </Layout>
  )
}

export default App
