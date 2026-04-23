/**
 * Netlify Function: /.netlify/functions/logs
 *
 * Queries PBS auction logs from CloudWatch.
 */

import type { Handler } from '@netlify/functions'
import { getRecentAuctions, getAuctionById } from './lib/cloudwatch'

function json(body: unknown, status = 200) {
  return {
    statusCode: status,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }
}

export const handler: Handler = async (event) => {
  const url = new URL(event.rawUrl)
  const type = url.searchParams.get('type') || 'recent'
  const hours = parseInt(url.searchParams.get('hours') || '24', 10)

  try {
    if (type === 'detail') {
      const auctionId = url.searchParams.get('auctionId')
      if (!auctionId) {
        return json({ error: 'auctionId required' }, 400)
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
    const message = err instanceof Error ? err.message : 'Unknown error'
    console.error('[CloudWatch]', message)
    return json({ error: message }, 500)
  }
}
