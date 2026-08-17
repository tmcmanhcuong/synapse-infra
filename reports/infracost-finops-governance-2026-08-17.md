# Infracost FinOps Governance Report

**Ngày:** 2026-08-17
**PR:** Feat/phase4 edge observability #2
**Status:** Deferred (soft-fail) — ưu tiên triển khai hạ tầng trước

## Tóm tắt

Infracost Cloud governance policies detected 7 FinOps recommendations. Đây là cost optimization suggestions, không phải security issues. Tạm soft-fail để CI pass, xử lý trong optimization phase.

## Findings

### 1. Tag Policy — FinOps tags thiếu

**Resources affected:** Resources mới trong edge + observability modules
**Recommendation:** Thêm cost allocation tags (Service, CostCenter) cho tất cả resources mới
**Priority:** Medium
**Action:** Thêm tags vào edge + observability modules

### 2. EC2 — Consider using Graviton instances

**Current:** `t3.large` (x86_64, Intel/AMD)
**Recommendation:** `t4g.large` (ARM64, Graviton) — ~20% rẻ hơn
**Priority:** Low
**Risk:** Cần verify ECS agent + synapse binary compatible ARM64. Go binary build với `GOARCH=arm64` cần test.
**Action:** Test ARM build trước, đổi instance type sau

### 3. ECS — Consider using Graviton instances

**Current:** Task definitions không specify architecture constraint
**Recommendation:** ECS tasks chạy trên Graviton EC2 instances
**Priority:** Low
**Depends on:** EC2 Graviton migration (#2 ở trên)

### 4. RDS — Consider using Graviton instances

**Current:** `db.t3.medium` (x86_64)
**Recommendation:** `db.t4g.medium` (Graviton) — ~20% rẻ hơn
**Priority:** Medium
**Risk:** Thấp — RDS Graviton là transparent, không ảnh hưởng application
**Action:** Đổi `db_instance_class` trong tfvars. Cần maintenance window.

### 5. S3 — Delete incomplete multi-part uploads

**Buckets affected:** synapse-evidence, synapse-web
**Recommendation:** Thêm `abort_incomplete_multipart_upload` lifecycle rule
**Priority:** Low
**Cost impact:** Minimal (chỉ tiết kiệm storage cho uploads bị abandon)
**Action:** Thêm lifecycle rule `abort_incomplete_multipart_upload_days = 7`

### 6. S3 — Move non-current versions to cheaper storage

**Buckets affected:** synapse-evidence (versioning enabled)
**Recommendation:** Transition non-current versions to Glacier/IA after 30-90 days
**Priority:** Low
**Risk:** Evidence bucket dùng Object Lock — lifecycle transitions có thể conflict
**Action:** Research Object Lock + lifecycle compatibility trước khi thay đổi

### 7. S3 — Intelligent-Tiering or lifecycle policy

**Buckets affected:** synapse-evidence, synapse-web
**Recommendation:** Enable Intelligent-Tiering hoặc lifecycle policy
**Priority:** Low
**Action:** Web bucket không cần (CI/CD sync + delete). Evidence bucket cân nhắc tiering cho objects cũ.

## Cost Saving Estimate

| Change | Monthly Savings (est.) |
|--------|----------------------|
| EC2 t3.large → t4g.large | ~$15-20 |
| RDS db.t3.medium → db.t4g.medium | ~$8-12 |
| S3 lifecycle + tiering | ~$1-3 |
| **Total** | **~$24-35/month** |

## Decision

**Deferred** — Tất cả findings là optimization, không block deployment. Xử lý sau khi:
1. Hạ tầng triển khai thành công
2. Application chạy ổn định
3. Có thời gian test Graviton compatibility (ARM64 builds)

## Để soft-fail governance

Workflow sửa: thêm `|| true` sau `infracost comment` command hoặc dùng `continue-on-error: true` cho step.
