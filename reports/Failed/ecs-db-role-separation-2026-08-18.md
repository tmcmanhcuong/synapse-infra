# ECS Task Crash — DB Role Separation & RLS Enforcement

**Date:** 2026-08-18 11:00-12:00 UTC+7
**Service:** synapse-api-prod
**Duration to resolve:** ~1 hour (3 iterations)

---

## Tóm tắt

Sau khi fix thiếu env vars (SYNAPSE_API_TOKEN), container crash thêm 3 lần vì DB configuration issues. Mỗi lần fix 1 layer, lộ ra layer tiếp theo.

## Iteration 1: DSN URL Parse Failure

**Error:**
```
"db migrate failed": "cannot parse postgres://synapse_admin:1x:FS_]|QxKn)zDH6yl:...@host:5432/postgres?sslmode=require: failed to parse as URL (net/url: invalid userinfo)"
```

**Root cause:** RDS `manage_master_user_password` generates passwords chứa special URL characters (`:`, `|`, `]`, `)`). Khi đặt raw vào DSN URL format, Go `net/url` parser không phân biệt được password vs host separator.

**Fix:** URL-encode password trước khi construct DSN:
```python
encoded = urllib.parse.quote(raw_password, safe='')
dsn = f"postgres://user:{encoded}@host:5432/db?sslmode=require"
```

## Iteration 2: RLS Role Ownership Conflict

**Error:**
```
"rls: runtime DB role cannot enforce isolation: role owns an RLS table"
```

**Root cause:** Dùng `synapse_admin` (master/owner user) cho cả migration VÀ runtime. Synapse có Row Level Security (RLS) trên tables → owner role bypass RLS → app từ chối serve vì security risk.

**Giải thích RLS:**
- RLS = database-level multi-tenant isolation (user A chỉ thấy data của user A)
- Table owner tự động bypass RLS (PostgreSQL design)
- Nếu app runtime dùng owner role → RLS vô nghĩa → security hole
- Synapse detect và refuse to start

**Fix chọn:** Tạo **app user riêng** (`synapse_app`) với quyền limited + cấu hình 2 DSN:
- `SYNAPSE_DB_MIGRATION_DSN` = admin user (DDL, schema changes)
- `SYNAPSE_DB_DSN` = app user (DML only, RLS enforced)

**Thực hiện:**
1. SSM vào EC2 instance trong ECS cluster
2. `psql` connect RDS bằng admin (password URL-encoded, dùng PGPASSWORD approach)
3. `CREATE ROLE synapse_app LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS`
4. Update secret `synapse/prod/db-master-password` với app user DSN
5. Tạo secret mới `synapse/prod/db-migration-dsn` với admin DSN
6. App tự chạy `GrantRuntimePrivileges()` khi start (grant SELECT/INSERT/UPDATE/DELETE cho app user)

## Iteration 3: Malformed DSN Secret

**Error:**
```
"grant runtime privileges: ERROR: role "nonroot" does not exist (SQLSTATE 42704)"
```

**Root cause:** Khi bạn chạy `put-secret-value` trên local terminal, DSN bị lỗi format (thiếu `postgres://` prefix do shell quoting issue). App không parse được username → fallback dùng container OS user (`nonroot` từ distroless image) → role not found.

**Fix:** Re-set secret với đúng format từ tôi (trong dashboard session, verified bằng urlparse).

## Lessons Learned

1. **RDS managed passwords + DSN URL format = luôn URL-encode**
2. **Synapse yêu cầu role separation** — không dùng admin user cho runtime
3. **Shell quoting hell** — password chứa `$`, `~`, `|`, `:` break cả double quotes, single quotes, và variable expansion. Safest: generate hex passwords cho app users (không có special chars)
4. **Verify secrets** sau khi set — parse URL trong script để confirm format đúng
5. **Distroless containers** chạy as user `nonroot` → nếu app fallback tới OS username, sẽ thấy `nonroot`

## Trạng thái sau fix

- ✅ Task revision 4 RUNNING (12:06 UTC+7)
- ✅ Migration: version 103 (complete)
- ✅ Runtime: `synapse_app` với RLS enforced
- ⚠️ ALB → ECS: 504 (SG rule thiếu — fix riêng)

## Secrets hiện tại

| Secret | Nội dung |
|--------|----------|
| `synapse/prod/api-token` | Random 32-byte hex token |
| `synapse/prod/db-master-password` | `postgres://synapse_app:<hex>@rds-host:5432/postgres?sslmode=require` |
| `synapse/prod/db-migration-dsn` | `postgres://synapse_admin:<url-encoded>@rds-host:5432/postgres?sslmode=require` |
| `synapse/prod/vault-master-key` | (chưa set — ephemeral mode) |
