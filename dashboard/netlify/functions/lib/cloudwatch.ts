/**
 * CloudWatch Logs client for querying PBS auction logs.
 *
 * Each auction produces a LogAnalyticsReporter DEBUG line with the full
 * OpenRTB response embedded in the "message" JSON field.
 */

import {
  CloudWatchLogsClient,
  StartQueryCommand,
  GetQueryResultsCommand,
} from '@aws-sdk/client-cloudwatch-logs'

const cwl = new CloudWatchLogsClient({
  region: process.env.SW_AWS_REGION || process.env.AWS_REGION || 'us-west-1',
  ...(process.env.SW_AWS_ACCESS_KEY_ID && {
    credentials: {
      accessKeyId: process.env.SW_AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.SW_AWS_SECRET_ACCESS_KEY!,
    },
  }),
})

const LOG_GROUP = process.env.PBS_LOG_GROUP
if (!LOG_GROUP) throw new Error('PBS_LOG_GROUP environment variable is required')

const MAX_POLL = 30
const POLL_MS = 1000

interface ParsedAuction {
  id: string
  timestamp: string
  seatbid: Array<{
    bid: Array<{
      id?: string
      impid?: string
      price?: number
      adm?: string
      w?: number
      h?: number
    }>
    seat?: string
  }>
  cur: string
  nbr?: number
  source: string
  ext: Record<string, unknown>
}

async function insightsQuery(query: string, hours: number): Promise<Record<string, string>[]> {
  const now = Math.floor(Date.now() / 1000)
  const { queryId } = await cwl.send(
    new StartQueryCommand({
      logGroupName: LOG_GROUP,
      startTime: now - hours * 3600,
      endTime: now,
      queryString: query,
    })
  )
  if (!queryId) throw new Error('Failed to start query')
  console.log('[CW] Started query:', queryId, 'hours:', hours)

  for (let i = 0; i < MAX_POLL; i++) {
    const result = await cwl.send(new GetQueryResultsCommand({ queryId }))
    if (result.status === 'Complete') {
      const rows = (result.results || []).map((row) => {
        const obj: Record<string, string> = {}
        row.forEach((f) => { if (f.field && f.value) obj[f.field] = f.value })
        return obj
      })
      console.log('[CW] Query complete:', rows.length, 'rows')
      return rows
    }
    if (result.status === 'Failed' || result.status === 'Cancelled') {
      throw new Error(`Query ${result.status}`)
    }
    await new Promise((r) => setTimeout(r, POLL_MS))
  }
  throw new Error('Query timed out')
}

function parseAuctionFromLog(logLine: string): ParsedAuction | null {
  try {
    if (!logLine.includes('/openrtb2/auction')) return null

    const tsMatch = logLine.match(/"timestamp":"([^"]+)"/)
    const timestamp = tsMatch?.[1] || ''

    const msgStart = logLine.indexOf('"message":"') + '"message":"'.length
    const msgEnd = logLine.lastIndexOf('", "containerId"')
    if (msgStart < 12 || msgEnd < 0) return null

    const innerJson = logLine.substring(msgStart, msgEnd)
    const inner = JSON.parse(innerJson)
    if (inner.type !== '/openrtb2/auction') return null

    const resolved = inner.ext?.debug?.resolvedrequest
    const app = resolved?.app
    let source = 'Web Widget'
    if (app?.name) {
      source = `${app.name} (${app.bundle || 'unknown'})`
    } else if (inner.id?.startsWith('auction-')) {
      source = 'Demo App'
    }

    return {
      id: inner.id,
      timestamp,
      seatbid: inner.seatbid || [],
      cur: inner.cur || 'USD',
      nbr: inner.nbr,
      source,
      ext: inner.ext || {},
    }
  } catch {
    return null
  }
}

export async function getRecentAuctions(hours = 24): Promise<ParsedAuction[]> {
  const rows = await insightsQuery(
    `fields @timestamp, @message
     | filter @message like /LogAnalyticsReporter/ and @message like /openrtb2/ and @message not like /cookie_sync/
     | sort @timestamp desc
     | limit 200`,
    hours
  )

  console.log('[CW] getRecentAuctions: got', rows.length, 'raw rows')
  const seen = new Set<string>()
  const auctions: ParsedAuction[] = []
  for (const row of rows) {
    const msg = row['@message'] || ''
    const a = parseAuctionFromLog(msg)
    if (a && !seen.has(a.id)) {
      seen.add(a.id)
      auctions.push(a)
    }
  }
  console.log('[CW] Parsed', auctions.length, 'unique auctions')
  return auctions
}

export async function getAuctionById(auctionId: string, hours = 72): Promise<ParsedAuction | null> {
  const safeId = auctionId.replace(/"/g, '')
  const rows = await insightsQuery(
    `fields @timestamp, @message
     | filter @message like /LogAnalyticsReporter/
       and @message like /"${safeId}"/
     | sort @timestamp desc
     | limit 5`,
    hours
  )

  for (const row of rows) {
    const a = parseAuctionFromLog(row['@message'] || '')
    if (a && a.id === auctionId) return a
  }
  return null
}
