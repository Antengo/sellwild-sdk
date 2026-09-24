/**
 * Netlify Function: /.netlify/functions/logs
 *
 * Queries PBS auction logs from CloudWatch.
 */

import type { Handler } from '@netlify/functions'
import { getRecentAuctions, getAuctionById } from './lib/cloudwatch'
import { isAuthenticated, UNAUTHORIZED, clampHours } from './lib/identity'

// CloudWatch Logs Insights bills per GB scanned; the UI never asks for more than 72h.
const MAX_HOURS = 168

// PBS auction ids are UUIDs / `auction-<ts>`-style tokens. Anything else is rejected
// before it reaches the Insights query string.
const AUCTION_ID_RE = /^[A-Za-z0-9_-]{1,128}$/

function json(body: unknown, status = 200) {
  return {
    statusCode: status,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }
}

export const handler: Handler = async (event, context) => {
  if (!isAuthenticated(context)) return UNAUTHORIZED

  const url = new URL(event.rawUrl)
  const type = url.searchParams.get('type') || 'recent'
  const hours = clampHours(url.searchParams.get('hours'), 24, MAX_HOURS)

  try {
    if (type === 'detail') {
      const auctionId = url.searchParams.get('auctionId')
      if (!auctionId) {
        return json({ error: 'auctionId required' }, 400)
      }
      if (!AUCTION_ID_RE.test(auctionId)) {
        return json({ error: 'Invalid auctionId' }, 400)
      }
      const auction = await getAuctionById(auctionId, hours)
      if (!auction) {
        return json({ error: 'Auction not found' }, 404)
      }
      return json(auction)
    }

    const auctions = await getRecentAuctions(hours)
    return json(auctions)
  } catch (err: unknown) {
    // Log the detail server-side only — AWS errors can carry account ids / ARNs.
    console.error('[CloudWatch]', err instanceof Error ? err.message : err)
    return json({ error: 'Query failed' }, 500)
  }
}
