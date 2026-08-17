# Phase 4 — Những gì còn thiếu và cần triển khai

Cập nhật: 2026-08-17

## Tổng quan

Module foundation, identity-secrets, data-layer, compute đã implemented. Còn thiếu:
- **Edge module** (ALB, S3 SPA bucket, CloudFront)
- **Observability module** (Alarms, SNS, Budget)
- **OIDC roles** cho repo synapse-ce (CI/CD deploy)
- **ALB** (compute module không có, chuyển vào edge)

## Quyết định thiết kế

| Quyết định | Lựa chọn | Lý do |
|------------|-----------|-------|
| Domain/ACM | Skip (dùng default URLs) | Chưa có domain, thêm sau |
| Route 53 | Skip | Phụ thuộc domain |
| Frontend hosting | S3 + CloudFront (default URL) | Rẻ, CDN, không tốn ECS resource cho static |
| ALB placement | Edge module (không phải compute) | ALB là entry point, thuộc edge layer |
| Worker/MCP services | Skip (chỉ API) | Đủ cho mục đích host + test thử |
| WAF | Skip | Nice-to-have, thêm sau khi có domain |

---

## 1. Edge Module — Cần implement

### Resources

| Resource | Terraform Type | Chi tiết |
|----------|---------------|----------|
| ALB Security Group | `aws_security_group` | Ingress 80/443 from 0.0.0.0/0, egress 8080 to ECS SG |
| ALB | `aws_lb` | Internet-facing, public subnets, dualstack |
| Target Group (API) | `aws_lb_target_group` | Port 8080, health check `/healthz`, HTTP |
| Listener HTTP | `aws_lb_listener` | Port 80, redirect → 443 (hoặc forward nếu chưa có cert) |
| Listener HTTPS | `aws_lb_listener` | Port 443 + ACM cert (skip nếu chưa có domain → dùng HTTP:80 forward tạm) |
| S3 SPA Bucket | `aws_s3_bucket` | `synapse-web-{account_id}`, block public, versioning |
| S3 Bucket Policy | `aws_s3_bucket_policy` | Allow CloudFront OAC read |
| CloudFront OAC | `aws_cloudfront_origin_access_control` | S3 origin signing |
| CloudFront Distribution | `aws_cloudfront_distribution` | S3 origin (web), ALB origin (/api/*), SPA error pages (403/404 → index.html) |

### Inputs (từ modules khác)
- `public_subnet_ids` ← foundation
- `vpc_id` ← foundation
- `ecs_security_group_id` ← foundation (app SG)
- `ecs_service_api_id` hoặc manual target registration

### Outputs
- `alb_dns_name`
- `cloudfront_domain_name`
- `s3_web_bucket_name`
- `alb_target_group_api_arn`

---

## 2. Observability Module — Cần implement

### Resources

| Resource | Terraform Type | Chi tiết |
|----------|---------------|----------|
| SNS Topic | `aws_sns_topic` | `synapse-alerts`, KMS encrypted |
| SNS Subscription | `aws_sns_topic_subscription` | Email (owner) |
| Alarm: EC2 CPU | `aws_cloudwatch_metric_alarm` | CPUUtilization > 80%, ASG |
| Alarm: RDS CPU | `aws_cloudwatch_metric_alarm` | CPUUtilization > 70% |
| Alarm: RDS Storage | `aws_cloudwatch_metric_alarm` | FreeStorageSpace < 5 GiB |
| Alarm: ECS Unhealthy | `aws_cloudwatch_metric_alarm` | UnHealthyHostCount > 0 (target group) |
| Alarm: ALB 5xx | `aws_cloudwatch_metric_alarm` | HTTPCode_Target_5XX_Count > 10/min |
| Budget | `aws_budgets_budget` | $320/mo, threshold $250 warning + $320 action |
| Dashboard | `aws_cloudwatch_dashboard` | synapse-overview (ECS, ALB, RDS widgets) |

### Inputs
- `ecs_cluster_name` ← compute
- `ecs_service_name` ← compute
- `rds_instance_id` ← data-layer
- `alb_arn_suffix` ← edge
- `target_group_arn_suffix` ← edge
- `asg_name` ← compute
- `kms_key_arn` ← identity-secrets
- `alert_email` ← variable

### Outputs
- `sns_topic_arn`
- `dashboard_url`

---

## 3. OIDC Roles cho synapse-ce repo — Cần implement

Đặt trong module `identity-secrets` (hoặc file riêng trong environments/prod).

| Resource | Chi tiết |
|----------|----------|
| OIDC Provider | Đã tồn tại (dùng chung cho cả synapse-infra + synapse-ce) |
| Build Role | `synapse-ce-github-actions-build` — push ECR |
| Deploy Role | `synapse-ce-github-actions-deploy` — update ECS + S3 write + CF invalidation |

Trust policy condition (immutable format):
```
repo:tmcmanhcuong@101078914/synapse-ce@<REPO_ID>:ref:refs/heads/main
```

Cần lấy repo ID của synapse-ce fork (`gh api repos/tmcmanhcuong/synapse-ce --jq .id`).

---

## 4. Compute Module — Cần sửa

| Fix | Chi tiết |
|-----|----------|
| Kết nối ECS service với ALB target group | Thêm `load_balancer` block vào `aws_ecs_service.api` |
| Network mode | Chuyển từ bridge → awsvpc (yêu cầu cho ALB target type `ip`) HOẶC giữ bridge + target type `instance` |

---

## Thứ tự implement

```
1. Edge module (ALB + S3 + CloudFront)
2. Compute fix (wire ECS service → ALB target group)
3. Observability module (alarms, budget, dashboard)
4. OIDC roles cho synapse-ce
5. Uncomment modules trong environments/prod/main.tf
6. terraform validate
```

---

## Không triển khai (out of scope hiện tại)

- ACM certificate (cần domain)
- Route 53 hosted zone + records (cần domain)
- WAF Web ACL (nice-to-have)
- ECS services cho worker + mcp (thêm sau)
- Service discovery / Cloud Map
- Auto-scaling ECS services
