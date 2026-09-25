/**
 * Netlify Identity gate for the dashboard functions.
 *
 * Netlify verifies the `Authorization: Bearer <jwt>` header against the site's
 * Identity instance and only then populates `context.clientContext.user`. A
 * missing, forged, or expired token leaves it unset. The login page alone never
 * protected these endpoints — they were callable anonymously.
 */

import type { HandlerContext } from '@netlify/functions'

export function isAuthenticated(context: HandlerContext): boolean {
  const user = (context.clientContext as { user?: { sub?: string } } | undefined)?.user
  return Boolean(user && user.sub)
}

export const UNAUTHORIZED = {
  statusCode: 401,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ error: 'Unauthorized' }),
}

/** Parse `hours`, defaulting to `fallback` and clamping to 1..max (each query is billed by scan size). */
export function clampHours(raw: string | null | undefined, fallback: number, max: number): number {
  const n = parseInt(raw || '', 10)
  if (!Number.isFinite(n) || n <= 0) return fallback
  return Math.min(n, max)
}
