# ADR-002: CloudFront SPA Routing via CloudFront Function

## Status

Accepted (2026-08-19)

## Context

Synapse frontend is a React SPA served from S3 via CloudFront. The API backend runs on ECS behind the same CloudFront distribution (path `/api/*` → ALB origin).

### Problem

The original implementation used `custom_error_response` to handle SPA routing:

```hcl
custom_error_response {
  error_code         = 403  # S3 returns 403 for non-existent keys (OAC)
  response_code      = 200
  response_page_path = "/index.html"
}
custom_error_response {
  error_code         = 404
  response_code      = 200
  response_page_path = "/index.html"
}
```

This caused a critical bug: when the API returns a legitimate 404 (e.g., no threat model data, no SLA configured), CloudFront intercepts the response and replaces it with `index.html` (HTML). The frontend then fails to parse it as JSON:

```
Unexpected token '<', "<!doctype "... is not valid JSON
```

`custom_error_response` is distribution-wide — it applies to ALL origins (S3 AND ALB), not just S3. There is no way to scope it to a single origin.

## Decision

Replace `custom_error_response` with a **CloudFront Function** (`cloudfront-js-2.0`) attached to the default cache behavior's `viewer-request` event.

The function rewrites SPA deep-link paths to `/index.html` BEFORE the request reaches the origin, so S3 never returns 403/404 for SPA routes. API paths pass through unmodified.

```javascript
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  // API, health checks, and static assets (files with extensions) pass through.
  if (uri.startsWith('/api/') || uri.startsWith('/healthz') || uri.includes('.')) {
    return request;
  }
  // Everything else is a SPA route → serve index.html.
  request.uri = '/index.html';
  return request;
}
```

## Consequences

### Positive

- API error responses (401, 403, 404, 500) are preserved exactly as returned by the backend
- SPA deep links (`/engagements/abc`, `/fleet`, `/code-quality`) continue to work
- No hidden assumptions about S3 error behavior (OAC returns 403 vs website hosting returns 404)
- CloudFront Functions are free up to 10M invocations/month (well within our usage)
- Sub-millisecond execution at edge — no latency impact

### Negative

- One additional resource to maintain (trivial — ~10 lines of JS)
- Function logic must be updated if new non-API, non-file paths are added that should NOT serve index.html (unlikely — all app routes are SPA)

### Neutral

- Pattern is industry-standard for SPA + API on CloudFront (AWS docs, community best practice)
- Function runs at viewer-request (before cache check), so it does not interfere with caching

## Alternatives Considered

### Keep custom_error_response but only for 403

- Works today because S3 + OAC returns 403 for missing keys
- Fragile: breaks if we enable S3 website hosting (returns 404 instead) or if API returns 403 for auth errors without a body
- Does not solve the 404 problem for API

### Remove custom_error_response entirely (no replacement)

- Breaks SPA deep links completely
- Users must always enter via root `/` and navigate via JS

### Lambda@Edge viewer-request

- Heavier (cold starts, higher cost, region-locked deployment)
- Overkill for simple URI rewrite
