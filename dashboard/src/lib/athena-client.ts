/**
 * AWS Athena client for querying Prebid Server metrics stored in S3 (Parquet).
 *
 * Tables: counter, gauge, histogram, meter, timer
 * Database: prebid-server-us-west-1-metricsetl-database
 * S3 bucket: prebid-server-metricsetlbucket69cb3729-igodkemqy1sc
 *
 * Env overrides:
 *   ATHENA_DATABASE        (default: prebid-server-us-west-1-metricsetl-database)
 *   ATHENA_OUTPUT_LOCATION (default: s3://prebid-server-metricsetlbucket69cb3729-igodkemqy1sc/athena-results/)
 *   ATHENA_WORKGROUP       (default: primary)
 *   AWS_REGION             (default: us-west-1)
 */

import {
  AthenaClient,
  StartQueryExecutionCommand,
  GetQueryExecutionCommand,
  GetQueryResultsCommand,
  QueryExecutionState,
} from '@aws-sdk/client-athena';

const athena = new AthenaClient({
  region: process.env.AWS_REGION || 'us-west-1',
});

const DATABASE =
  process.env.ATHENA_DATABASE ||
  'prebid-server-us-west-1-metricsetl-database';
const OUTPUT_LOCATION =
  process.env.ATHENA_OUTPUT_LOCATION ||
  's3://prebid-server-metricsetlbucket69cb3729-igodkemqy1sc/athena-results/';
const WORKGROUP = process.env.ATHENA_WORKGROUP || 'primary';

const MAX_POLL_ATTEMPTS = 60;
const POLL_INTERVAL_MS = 1000;

export async function queryAthena<T = Record<string, string>>(
  sql: string
): Promise<T[]> {
  const { QueryExecutionId } = await athena.send(
    new StartQueryExecutionCommand({
      QueryString: sql,
      QueryExecutionContext: { Database: DATABASE },
      ResultConfiguration: { OutputLocation: OUTPUT_LOCATION },
      WorkGroup: WORKGROUP,
    })
  );

  if (!QueryExecutionId) throw new Error('Failed to start Athena query');

  for (let i = 0; i < MAX_POLL_ATTEMPTS; i++) {
    const { QueryExecution } = await athena.send(
      new GetQueryExecutionCommand({ QueryExecutionId })
    );
    const state = QueryExecution?.Status?.State;

    if (state === QueryExecutionState.SUCCEEDED) break;
    if (state === QueryExecutionState.FAILED) {
      throw new Error(
        `Athena query failed: ${QueryExecution?.Status?.StateChangeReason}`
      );
    }
    if (state === QueryExecutionState.CANCELLED) {
      throw new Error('Athena query was cancelled');
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }

  const results = await athena.send(
    new GetQueryResultsCommand({ QueryExecutionId, MaxResults: 1000 })
  );

  const rows = results.ResultSet?.Rows || [];
  if (rows.length <= 1) return [];

  const headers = rows[0].Data?.map((d) => d.VarCharValue || '') || [];
  return rows.slice(1).map((row) => {
    const obj: Record<string, string> = {};
    row.Data?.forEach((d, i) => {
      obj[headers[i]] = d.VarCharValue || '';
    });
    return obj as unknown as T;
  });
}
