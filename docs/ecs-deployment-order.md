# Thứ tự triển khai ECS: Infrastructure → Image → Service

Giải quyết bài toán con gà - quả trứng: ECS cần image để chạy, nhưng ECR (registry chứa image) là hạ tầng do Terraform tạo.

## Vấn đề

```
ECS Task Definition yêu cầu: image = "<account>.dkr.ecr.<region>.amazonaws.com/synapse-api:<tag>"

Nếu image đó KHÔNG tồn tại trong ECR khi ECS cố pull:
  → Task fail với "CannotPullContainerError"
  → Service liên tục retry (crashloop)
  → Terraform apply có thể timeout khi chờ service stability
```

## Thứ tự triển khai

```
Phase 1: Infrastructure (Terraform)
  ├── foundation (VPC, subnets, NAT, SGs)
  ├── identity-secrets (KMS, Secrets Manager, IAM roles)
  ├── data-layer (RDS, S3)
  └── compute (ECS cluster, ECR repos, ASG, task defs, service với desired_count=0)
              ↑
              └── ECR repos TRỐNG tại thời điểm này — hoàn toàn OK

Phase 2: Bootstrap Image (làm 1 lần, thủ công)
  └── Build synapse-ce → push lên ECR với tag "initial" hoặc git SHA

Phase 3: First Deploy
  └── Update desired_count → ECS tasks pull image → service healthy
```

## Strategy: desired_count = 0

Cách sạch nhất cho lần deploy đầu tiên:

```hcl
# modules/compute/main.tf
resource "aws_ecs_service" "api" {
  name            = "synapse-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.initial_desired_count  # default = 0 cho lần apply đầu
  # ...
}
```

```hcl
# environments/prod/terraform.tfvars
initial_desired_count = 0  # Đổi thành 2 sau khi push image đầu tiên
```

### Tại sao cách này hoạt động:
- Terraform apply thành công (service tồn tại, nhưng không schedule task nào)
- Không có image pull → không có error
- Sau khi push image: update `desired_count = 2` rồi re-apply (hoặc pipeline tự làm)

## Strategy: Bootstrap Image (thủ công, 1 lần duy nhất)

Cho lần deploy đầu tiên:

```bash
# 1. Authenticate với ECR
aws ecr get-login-password --region ap-southeast-1 --profile cuong-admin | \
  docker login --username AWS --password-stdin 945125812908.dkr.ecr.ap-southeast-1.amazonaws.com

# 2. Build từ source synapse-ce
cd synapse-ce
docker build -f deploy/Dockerfile -t synapse-api:initial .

# 3. Tag cho ECR
docker tag synapse-api:initial \
  945125812908.dkr.ecr.ap-southeast-1.amazonaws.com/synapse-api:initial

# 4. Push
docker push 945125812908.dkr.ecr.ap-southeast-1.amazonaws.com/synapse-api:initial

# 5. Giờ ECS có thể pull image này
```

Sau bước bootstrap này, CI/CD pipeline xử lý tất cả các lần deploy tiếp theo tự động.

## Luồng hoạt động ổn định (sau bootstrap)

```
Developer push code lên fork main
       │
       ▼
GitHub Actions (deploy-ecs.yml)
       │
       ├── Build Docker image từ deploy/Dockerfile
       ├── Tag với git SHA: <ecr-uri>:abc123f
       ├── Push lên ECR
       ├── Render ECS task definition mới (với image tag mới)
       └── Update ECS service → rolling deploy (zero-downtime)
```

## Sơ đồ phụ thuộc components

```
                    ┌─────────────┐
                    │  ECR Repos  │ ← Terraform tạo (trống)
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        synapse-api   synapse-web  synapse-agent
              │            │            │
              ▼            ▼            ▼
        ┌──────────────────────────────────┐
        │       ECS Task Definitions       │ ← Reference image URIs
        └──────────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │         ECS Service(s)           │ ← Schedule tasks, pull images
        └──────────────────────────────────┘
```

## Synapse-CE Components cần deploy

Dựa trên `deploy/Dockerfile` và `deploy/docker-compose.yml`:

| Component | Image | Port | Ghi chú |
|-----------|-------|------|---------|
| synapse-api | `deploy/Dockerfile` (Go binary) | 8080 | API server chính, cần PostgreSQL |
| synapse-web | `web/` (React + Vite) | 80 (nginx) | Static frontend, serve qua nginx |
| synapse-agent | Go binary | N/A | Fleet agent (chạy trên target hosts, KHÔNG deploy lên ECS) |

Lưu ý: synapse-agent được thiết kế để chạy trên target hosts (Debian/Ubuntu/RHEL/Windows), không phải trong ECS. Chỉ `synapse-api` và `synapse-web` cần deploy lên ECS.

## Terraform variable cho phased deploy

```hcl
variable "initial_desired_count" {
  description = "ECS service desired count. Set 0 cho lần deploy đầu trước khi có image."
  type        = number
  default     = 0

  validation {
    condition     = var.initial_desired_count >= 0 && var.initial_desired_count <= 10
    error_message = "desired_count phải nằm trong khoảng 0 đến 10"
  }
}
```

## Checklist: Lần deploy đầu tiên

- [ ] `terraform apply` hoàn tất cho tất cả modules (ECR repos đã tạo, ECS service ở 0)
- [ ] Build Docker image locally từ `synapse-ce/deploy/Dockerfile`
- [ ] Push image lên ECR với tag `initial`
- [ ] Update `initial_desired_count = 2` trong terraform.tfvars
- [ ] `terraform apply` lần nữa (ECS service scale lên 2, pull image)
- [ ] Xác nhận: `aws ecs describe-services` hiện `runningCount: 2`
- [ ] Xác nhận: ALB health check trả về 200 trên `/healthz`
- [ ] Enable CI/CD pipeline (các lần deploy sau hoàn toàn tự động)

## Checklist: Các lần deploy sau (Pipeline tự động)

- [ ] Pipeline trigger khi push to main
- [ ] Build image với SHA tag
- [ ] Push lên ECR
- [ ] Render task definition mới với image mới
- [ ] Update ECS service
- [ ] Chờ service stability (min 100%, max 200% → zero-downtime)
- [ ] Health check pass

## Tại sao cần deploy stage? (ECS KHÔNG tự pull image mới)

Một hiểu lầm phổ biến: "push image mới lên ECR → ECS tự pull về". **Sai.**

### Cơ chế thực tế (từ AWS docs)

ECS lock image bằng **digest** ngay khi deploy lần đầu. Dù bạn push image mới với cùng tag `:latest`, ECS vẫn chạy image cũ vì digest đã lock:

> "After the container image digests have been established, Amazon ECS uses the digests to start any other desired tasks. This leads to all tasks in a service always running identical container images, resulting in **version consistency**."
> — [AWS Docs: Container image resolution](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html)

### 3 cách để ECS nhận image mới

| Cách | Cơ chế | Tự động? |
|------|--------|----------|
| Register task definition mới + update service | Pipeline render task def với image tag mới → ECS schedule tasks mới | Cần pipeline trigger |
| `forceNewDeployment` | ECS re-resolve digest từ tag hiện tại → pull image mới | Cần trigger (CLI/pipeline) |
| EventBridge + Lambda | ECR push event → Lambda gọi `update-service` | ✅ Tự động nhưng phải tự setup |

### Kết luận

- **ECS Express Mode** (mới 2025) đơn giản hóa setup (auto ALB, auto scaling, SSL) nhưng **vẫn không auto-deploy khi ECR có image mới**
- Deploy stage trong pipeline (Job 3 của `deploy-ecs.yml`) là cách chuẩn nhất: register task definition mới → update service → zero-downtime rolling
- Đây là cơ chế mặc định, không phải thiếu config gì — ECS thiết kế như vậy vì **version consistency** (đảm bảo tất cả tasks chạy cùng 1 image)
