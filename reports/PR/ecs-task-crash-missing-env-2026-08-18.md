# ECS Task Crash — synapse-api Exit Code 1

**Date:** 2026-08-18 11:00 UTC+7
**Service:** synapse-api-prod (ECS cluster synapse-cluster-prod)
**Symptom:** Tasks start then immediately exit with code 1. Deployment times out.

## Root Cause: Missing Required Environment Variable

synapse-api server requires `SYNAPSE_API_TOKEN` — fail-closed, no anonymous access:

```go
// cmd/synapse-api/main.go:228
log.Error("SYNAPSE_API_TOKEN is required (no anonymous access). Set it...")
os.Exit(1)
```

### Task Definition hiện tại

```json
{
  "Name": "synapse-api",
  "Image": "945125812908.dkr.ecr.ap-southeast-1.amazonaws.com/synapse-api:f4cf7c4",
  "Env": [],      ← TRỐNG
  "Secrets": null  ← KHÔNG CÓ
}
```

## Environment Variables cần thiết

### Bắt buộc (crash nếu thiếu)

| Variable | Mô tả | Source |
|----------|--------|--------|
| `SYNAPSE_API_TOKEN` | Auth token cho API + UI | Secrets Manager → `synapse-api-token-prod` |

### Optional (cho production)

| Variable | Mô tả | Default |
|----------|--------|---------|
| `SYNAPSE_HTTP_ADDR` | Listen address | `:8080` (OK) |
| `SYNAPSE_DB_DSN` | PostgreSQL connection string | `""` (in-memory mode) |
| `SYNAPSE_DB_MIGRATION_DSN` | DDL migration DSN (required if DB_DSN set) | `""` |
| `SYNAPSE_LOG_LEVEL` | Log level | `info` |
| `SYNAPSE_ENVIRONMENT` | Environment name | `development` |

### Giai đoạn 1 (minimal — just get it running)

Chỉ cần `SYNAPSE_API_TOKEN`. Server sẽ chạy in-memory mode (không cần DB).

### Giai đoạn 2 (production — persistent data)

Thêm `SYNAPSE_DB_DSN` + `SYNAPSE_DB_MIGRATION_DSN` pointing tới RDS.

## Fix

### Option A: Thêm env vars vào Terraform task definition

```hcl
# modules/compute/main.tf - container_definitions
environment = [
  { name = "SYNAPSE_HTTP_ADDR", value = ":8080" },
  { name = "SYNAPSE_ENVIRONMENT", value = "production" },
]
secrets = [
  { name = "SYNAPSE_API_TOKEN", valueFrom = aws_secretsmanager_secret.api_token.arn },
]
```

### Option B: Thêm trực tiếp vào ECS console (quick test)

Không recommended — sẽ bị overwrite lần deploy sau.

## Lưu ý

- `SYNAPSE_DB_DSN` format: `postgres://user:pass@host:5432/dbname?sslmode=require`
- RDS đã tạo bởi Terraform (module data-layer), password trong Secrets Manager
- Cần tạo database `synapse` trên RDS instance trước khi connect
