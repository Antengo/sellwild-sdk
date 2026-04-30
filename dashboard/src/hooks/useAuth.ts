import { useEffect, useState, useCallback } from 'react'

interface User {
  id: string
  email: string
  name?: string
  avatarUrl?: string
  token: string
}

interface AuthState {
  user: User | null
  isLoading: boolean
  isAuthenticated: boolean
}

export function useAuth() {
  const [state, setState] = useState<AuthState>({
    user: null,
    isLoading: true,
    isAuthenticated: false,
  })

  useEffect(() => {
    const identity = window.netlifyIdentity

    if (!identity) {
      setState({ user: null, isLoading: false, isAuthenticated: false })
      return
    }

    identity.init()

    const handleLogin = (user?: NetlifyUser) => {
      if (user) {
        setState({
          user: {
            id: user.id,
            email: user.email,
            name: user.user_metadata.full_name,
            avatarUrl: user.user_metadata.avatar_url,
            token: user.token.access_token,
          },
          isLoading: false,
          isAuthenticated: true,
        })
      }
    }

    const handleLogout = () => {
      setState({ user: null, isLoading: false, isAuthenticated: false })
    }

    const handleInit = (user?: NetlifyUser) => {
      if (user) {
        handleLogin(user)
      } else {
        setState({ user: null, isLoading: false, isAuthenticated: false })
      }
    }

    identity.on('init', handleInit)
    identity.on('login', handleLogin)
    identity.on('logout', handleLogout)

    const currentUser = identity.currentUser()
    if (currentUser) {
      handleLogin(currentUser)
    } else {
      setState({ user: null, isLoading: false, isAuthenticated: false })
    }

    return () => {
      identity.off('init', handleInit)
      identity.off('login', handleLogin)
      identity.off('logout', handleLogout)
    }
  }, [])

  const login = useCallback(() => {
    window.netlifyIdentity?.open('login')
  }, [])

  const logout = useCallback(() => {
    window.netlifyIdentity?.logout()
  }, [])

  return {
    ...state,
    login,
    logout,
  }
}
