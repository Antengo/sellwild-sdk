# Deploying the Docs Site

The docs site is a VitePress static site deployed to S3 + CloudFront at https://sdk.sellwild.com.

## Prerequisites

- AWS CLI configured with account `457870823482`
- Node.js 18+

## Build

```bash
cd docs-site
npm install
npm run build
```

Output lands in `docs-site/.vitepress/dist/`.

## Deploy to S3

```bash
aws s3 sync .vitepress/dist/ s3://sdk.sellwild.com/ \
  --cache-control "max-age=3600,public" \
  --delete
```

## Invalidate CloudFront Cache

```bash
aws cloudfront create-invalidation \
  --distribution-id E2I8MYVEM6ZX5R \
  --paths "/*"
```

Invalidation takes 1-2 minutes to propagate globally.

## One-liner

```bash
npm run build && \
aws s3 sync .vitepress/dist/ s3://sdk.sellwild.com/ --cache-control "max-age=3600,public" --delete && \
aws cloudfront create-invalidation --distribution-id E2I8MYVEM6ZX5R --paths "/*"
```

## Infrastructure

| Resource | Value |
|---|---|
| S3 Bucket | `sdk.sellwild.com` |
| CloudFront Distribution | `E2I8MYVEM6ZX5R` |
| CloudFront Domain | `d3dsg4mdklzb65.cloudfront.net` |
| ACM Certificate | `arn:aws:acm:us-east-1:457870823482:certificate/98b905b8-c410-4280-b3b9-c32aa5b0dc8a` |
| Route53 Zone | `Z3G3982AWLHGHP` (sellwild.com) |
| DNS | `sdk.sellwild.com` CNAME → CloudFront |

## Local Development

```bash
cd docs-site
npm install
npm run dev
```

Runs at `http://localhost:5173` with hot reload.
