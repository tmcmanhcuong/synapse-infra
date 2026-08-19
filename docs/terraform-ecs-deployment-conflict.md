# Terraform + ECS: Tại sao apply SG rule lại restart container?

## Vấn đề gặp phải

Chỉ thêm 1 Security Group ingress rule (ALB → App), không đụng gì tới ECS. Nhưng sau `terraform apply`, ECS tự restart task → container crash do advisory lock conflict.

## Tại sao xảy ra

### ECS Task Definition là IMMUTABLE

Không giống EC2 instance (update in-place), ECS task definition hoạt động kiểu versioning:

```
Revision 1 → Revision 2 → Revision 3 → ...
```

Mỗi lần Terraform detect bất kỳ thay đổi nào trong `container_definitions` (dù chỉ thứ tự key JSON khác), nó **register revision MỚI**. Không thể update revision cũ.

### ECS Service auto-redeploy khi revision đổi

```
Terraform register revision 5
  → ECS service thấy "ơ, revision mới"
    → Rolling deployment: start task mới + drain task cũ
      → 2 tasks cùng tồn tại tạm thời
```

### Kết hợp với single-instance lock

Synapse chỉ cho 1 instance chạy (advisory lock trong PostgreSQL). Rolling deployment = 2 instances overlap = lock conflict = crash.

## Root Cause sâu hơn: State Drift từ thao tác thủ công

Khi chạy `aws ecs update-service --force-new-deployment` thủ công:
- AWS service giờ reference revision X
- Terraform state vẫn nghĩ nó manage revision Y
- Lần apply sau: Terraform thấy drift → "sửa" lại → register revision mới → restart

```
Terraform state: service dùng revision 3
AWS thực tế:     service dùng revision 4 (do force-deploy thủ công)
                       ↓
terraform apply: "service cần update" → register revision 5 → restart
```

## Giải pháp

### Option A: `lifecycle { ignore_changes }` (Recommended)

```hcl
resource "aws_ecs_service" "api" {
  name            = "synapse-api-${var.environment}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.ecs_api_desired_count
  
  # ...

  lifecycle {
    ignore_changes = [task_definition]
  }
}
```

**Ý nghĩa:** Terraform quản lý infra (SG, ALB, cluster, desired_count). Pipeline quản lý deployments (task definition revision). Hai domain không đạp lên nhau.

**Khi nào task def được update:**
- Deploy pipeline (`amazon-ecs-deploy-task-definition` action) → register revision + update service
- KHÔNG phải terraform apply

**Trade-off:**
- ✅ Terraform apply không trigger ECS restart ngoài ý muốn
- ✅ Pipeline là single source of truth cho deployment
- ⚠️ Terraform lần đầu vẫn tạo task def + service (initial setup)
- ⚠️ Nếu muốn đổi container config qua Terraform (port, memory), phải tạm bỏ ignore rồi apply rồi thêm lại

### Option B: Deploy chỉ qua Terraform (không dùng pipeline deploy job)

Bỏ Job 4 (Deploy ECS) khỏi pipeline. Pipeline chỉ build+push image. Mỗi lần muốn deploy image mới → update image tag trong Terraform code → PR → apply.

**Trade-off:**
- ✅ Single source of truth (Terraform)
- ❌ Mỗi deploy cần PR (chậm)
- ❌ Phải commit image SHA vào code

### Option C: Tách ECS service ra khỏi Terraform hoàn toàn

Terraform chỉ tạo cluster, ECR, task definition template. Service được quản lý bởi pipeline.

**Trade-off:**
- ✅ Zero conflict
- ❌ Service config không trong IaC (drift risk)

## Recommendation cho Synapse

**Option A** — thêm `ignore_changes = [task_definition]`. Lý do:
1. Pipeline đã handle deployment (render image → register → update service)
2. Terraform handle infra (SG, ALB, scaling, networking)
3. Không cần mix 2 concern

## ✅ Resolution (2026-08-19)

Cả hai fix đã được implement trong PR `fix/ecs-single-instance-deploy`:

### 1. Deployment config cho single-instance app

```hcl
# modules/compute/main.tf — aws_ecs_service.api
deployment_minimum_healthy_percent = 0
deployment_maximum_percent         = 100

deployment_circuit_breaker {
  enable   = true
  rollback = true
}
```

**Hành vi mới:** ECS stop task cũ TRƯỚC khi start task mới → advisory lock được release → task mới acquire lock thành công. Chấp nhận ~10-30s downtime mỗi lần deploy (trade-off hợp lý cho single-instance app).

Circuit breaker tự rollback nếu task mới fail liên tục (thay vì retry vô hạn).

### 2. Pipeline owns task_definition

```hcl
lifecycle {
  ignore_changes = [task_definition]
}
```

**Hành vi mới:** `terraform apply` không trigger ECS redeploy khi chỉ thay đổi infra (SG, ALB, scaling). Chỉ deploy pipeline (`deploy-ecs.yml`) mới update task definition revision.

### Quy trình deploy sau fix

```
Developer push code → Pipeline build image → Push ECR → Register revision N+1
  → aws ecs update-service --task-definition rev:N+1
    → ECS stop task (rev N) — lock released
      → ECS start task (rev N+1) — lock acquired
        → Healthy ✅
```

Không còn crash loop do lock conflict.

### Lần đầu sau apply

Sau khi merge PR và `terraform apply`, cần **kill task cũ đang DRAINING 1 lần cuối** (nó giữ lock từ trước khi fix được apply). Từ lần deploy sau trở đi, flow tự động hoạt động đúng.

```bash
# Tìm task đang DRAINING giữ lock
aws ecs list-tasks --cluster synapse-cluster-prod --service-name synapse-api-prod \
  --profile cuong-admin --region ap-southeast-1

# Stop task cũ
aws ecs stop-task --cluster synapse-cluster-prod --task <TASK_ID> \
  --reason "Release advisory lock for new deployment config" \
  --profile cuong-admin --region ap-southeast-1
```

## Quy tắc khi dùng Option A

1. **KHÔNG** chạy `aws ecs update-service --force-new-deployment` thủ công trừ khi debug
2. **KHÔNG** đổi container config (env vars, secrets, port, memory) trực tiếp qua Terraform sau initial setup — đổi qua pipeline hoặc tạm remove ignore_changes
3. **NẾU** cần đổi infra-level config (desired_count, deployment config, load balancer): Terraform vẫn quản lý bình thường
4. **MUỐN** redeploy image mới: push commit → pipeline tự chạy

## Liên quan: Advisory Lock + Rolling Deploy

Synapse dùng PostgreSQL advisory lock cho single-instance guarantee. Khi ECS rolling deploy:

```
Task cũ: đang hold lock
Task mới: start → cố acquire lock → fail → crash
```

Fix:
- Dùng `deployment_minimum_healthy_percent = 0` (stop old before start new)
- Hoặc: `deployment_maximum_percent = 100` + `minimum_healthy_percent = 0` (replace, not rolling)

```hcl
deployment_minimum_healthy_percent = 0
deployment_maximum_percent         = 100
```

Kiểu này ECS stop task cũ TRƯỚC → lock released → start task mới → acquire lock OK. Downtime ngắn (~10s) nhưng không conflict.
