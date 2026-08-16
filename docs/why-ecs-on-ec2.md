# Tại sao chọn ECS on EC2 cho Synapse Worker

> Decision Record: DR-01, DR-02
> Ngày quyết định: 2026-08-16

---

## Bối cảnh

Synapse CE có 3 control-plane services cần deploy:
- **Worker** — chạy scan jobs (privileged, sandboxed execution)
- **API** — HTTP server chính (:8080)
- **MCP** — Model Context Protocol server (:8081)

Tất cả đều `single-instance-only` (code dùng PostgreSQL advisory lock để enforce).

---

## Vấn đề: Worker yêu cầu privileged Linux capabilities

Source code Worker có 3 hard constraints loại bỏ hầu hết serverless/managed compute:

### CONSTRAINT-01: CAP_NET_ADMIN + CAP_SYS_ADMIN

```go
// internal/infrastructure/egress/applier.go:9,49,65,77
// "Privileged operations need CAP_NET_ADMIN"
```

Worker tạo **network namespace riêng** cho mỗi scan job, rồi dùng iptables rules để chỉ cho phép egress tới domains đã approve (npm registry, Maven Central, OSV.dev...). Điều này cần:
- `CAP_NET_ADMIN` — tạo netns, sửa iptables
- `CAP_SYS_ADMIN` — enter netns, thao tác cgroup

### CONSTRAINT-02: Bubblewrap (bwrap) + systemd-run

```go
// internal/infrastructure/sandbox/runner.go:3,17,44
// "orchestrates bubblewrap (bwrap)...Linux-only"
```

Mọi tool chạy bên trong Worker (CSPM scanner, AST parser, callgraph builder) đều bị sandbox bằng bubblewrap. Nếu host không có binary `bwrap`, startup **FAIL CLOSED** — không fallback.

### CONSTRAINT-03: eBPF connection logging

```go
// internal/infrastructure/ebpf/connlog_linux.go:3-8
// "cgroup connect4/connect6 eBPF program"
```

Worker attach eBPF program vào cgroup để log mọi outbound TCP connection từ scan job. Cần Linux kernel ≥ 5.8 với BPF enabled.

---

## Options đã xét

| Option | Privileged? | Cost/mo | Verdict |
|--------|-------------|---------|---------|
| **AWS Fargate** | ❌ Không cho privileged containers | $35+ | **LOẠI** — hard block |
| **AWS Lambda** | ❌ Không cho privileged, timeout 15 min | ~$5 | **LOẠI** — hard block |
| **App Runner** | ❌ Không cho privileged | $25+ | **LOẠI** — hard block |
| **EKS** | ✅ Privileged pods supported | $73 control plane + EC2 | **LOẠI** — overkill, thêm $73/mo cho 3 containers |
| **EC2 standalone** | ✅ Full control | ~$61 | Khả thi nhưng thiếu isolation |
| **ECS on EC2** | ✅ `privileged: true` trong task def | ~$61 | **✅ CHỌN** |

---

## Tại sao ECS on EC2 thắng EC2 standalone

Cùng giá ($0 cho ECS control plane), nhưng ECS cho thêm:

| Feature | EC2 standalone | ECS on EC2 |
|---------|---------------|------------|
| IAM isolation per container | ❌ Shared instance profile | ✅ Task role riêng biệt |
| Auto-restart khi crash | ❌ Phải viết systemd | ✅ ECS scheduler tự restart |
| Deploy new version | ❌ SSH → pull → restart | ✅ `ecs update-service --force-new-deployment` |
| Logging | ❌ Cài CloudWatch agent | ✅ awslogs driver built-in |
| Health check | ❌ Tự build | ✅ ECS health check + ALB integration |
| Rollback | ❌ Thủ công | ✅ Previous task definition revision |

---

## Tại sao không EKS

- **+$73/mo** chỉ cho EKS control plane (25% total budget)
- 3 containers, single-instance mỗi cái — không cần Kubernetes orchestration
- Thêm complexity: kubectl, helm charts, node groups, IRSA, CoreDNS, kube-proxy
- Code nói rõ "horizontal scaling is P5" — Kubernetes solving a problem that doesn't exist here

---

## Kết luận

```
Worker constraints (privileged + bwrap + eBPF)
        │
        ▼
  Loại Fargate, Lambda, App Runner (hard block)
        │
        ▼
  Còn: EC2 standalone vs ECS on EC2 vs EKS
        │
        ▼
  Loại EKS (overkill + $73/mo thừa)
        │
        ▼
  ECS on EC2 > EC2 standalone (task role isolation + auto-restart + deploy automation + $0 extra)
        │
        ▼
  ✅ DR-01: Worker = ECS on EC2, privileged task
  ✅ DR-02: API + MCP = cùng EC2 instance, ECS tasks non-privileged
```

**Accepted risk:** Worker (privileged) chạy cùng host với API/MCP. Mitigated bằng:
- ECS task role separation (IAM boundary)
- Docker network isolation (container-level)
- Worker không listen port (không có attack surface từ network)

---

## References

- `cmd/synapse-worker/main.go:1-6` — "sandbox + kernel egress allowlist...runs with CAP_NET_ADMIN/SYS_ADMIN"
- `cmd/synapse-worker/main.go:109` — "run ONE worker"
- `internal/infrastructure/egress/applier.go:9,49,65,77` — "Privileged operations need CAP_NET_ADMIN"
- `internal/infrastructure/sandbox/runner.go:3,17,44` — "orchestrates bubblewrap (bwrap)...Linux-only"
- `internal/infrastructure/ebpf/connlog_linux.go:3-8` — "cgroup connect4/connect6 eBPF program"
- [AWS ECS Task Definition — Linux Parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#container_definition_linuxparameters)
- [AWS Fargate — No privileged containers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-defs.html)
