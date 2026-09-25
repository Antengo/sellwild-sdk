/// <reference types="vite/client" />

interface NetlifyUser {
  id: string
  email: string
  user_metadata: {
    full_name?: string
    avatar_url?: string
  }
  app_metadata: {
    roles?: string[]
  }
  token: {
    access_token: string
    token_type: string
    expires_in: number
    refresh_token: string
    expires_at: number
  }
  /** Current access token, refreshed first if expired. */
  jwt?: (forceRefresh?: boolean) => Promise<string>
}

declare global {
  interface Window {
    netlifyIdentity?: {
      init: () => void
      open: (tab?: string) => void
      close: () => void
      logout: () => void
      currentUser: () => NetlifyUser | null
      on: (event: string, callback: (user?: NetlifyUser) => void) => void
      off: (event: string, callback?: (user?: NetlifyUser) => void) => void
    }
  }
  type NetlifyUser = NetlifyUser
}

export { NetlifyUser }
