/**
 * fetch() for the dashboard's Netlify Functions, with the Identity token attached.
 * The functions verify it server-side, so user.jwt() is used to refresh an
 * expired (1h) access token rather than sending a stale one.
 */
export async function authFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const user = window.netlifyIdentity?.currentUser()
  let token: string | null = null
  if (user) {
    try {
      token = typeof user.jwt === 'function' ? await user.jwt() : user.token?.access_token ?? null
    } catch {
      token = null
    }
  }
  const headers = new Headers(init.headers)
  if (token) headers.set('Authorization', `Bearer ${token}`)
  return fetch(input, { ...init, headers })
}
