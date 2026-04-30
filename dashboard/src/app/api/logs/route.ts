/**
 * GET /api/logs?type=recent|detail&auctionId=&hours=24
 *
 * Queries PBS auction logs from CloudWatch.
 */

import { NextRequest, NextResponse } from 'next/server';
import { getRecentAuctions, getAuctionById } from '@/lib/cloudwatch';

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const type = url.searchParams.get('type') || 'recent';
  const hours = parseInt(url.searchParams.get('hours') || '24', 10);

  try {
    if (type === 'detail') {
      const auctionId = url.searchParams.get('auctionId');
      if (!auctionId) {
        return NextResponse.json({ error: 'auctionId required' }, { status: 400 });
      }
      const auction = await getAuctionById(auctionId, hours);
      if (!auction) {
        return NextResponse.json({ error: 'Auction not found' }, { status: 404 });
      }
      return NextResponse.json(auction);
    }

    const auctions = await getRecentAuctions(hours);
    return NextResponse.json(auctions);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    console.error('[CloudWatch]', message);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
