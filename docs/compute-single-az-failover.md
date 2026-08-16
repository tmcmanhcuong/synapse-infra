# Compute Single-AZ và Failover Strategy

> Giải thích tại sao compute chỉ nằm ở 1 AZ và chiến lược recovery khi AZ failure.
> Liên quan: DR-01, DR-02, DR-06, CONSTRAINT-04, CONSTRAINT-05

---

## Câu hỏi

Trong architecture diagram, ECS/EC2 (Worker + API + MCP) chỉ nằm ở AZ-A. VPC có 2 AZ nhưng compute không spread. Vậy failover/DR hoạt động thế nào?

---

## Trả lời ngắn

**Compute không có HA (High Availability). Nếu AZ-A chết, services sẽ down 5-10 phút cho đến khi failover xong.**

Đây là **accepted trade-off**, không phải thiếu sót.

---

## Lý do: Code bắt buộc single-instance

Cả 3 control-plane services dùng PostgreSQL advisory lock để đảm bảo chỉ 1 instance chạy:

```go
// cmd/synapse-api/main.go:363-377
// "Single-instance guard...horizontal scaling is P5"

// cmd/synapse-worker/main.go:109
// "run ONE worker"

// cmd/synapse-mcp/main.go:67-73
// "run ONE per role"
```

**Hệ quả:**
- Không thể chạy 2 instances song song (instance thứ 2 fail closed)
- Không thể làm active-active across AZs
- Chỉ có thể làm **failover** (active-passive) — 1 instance chạy, nếu chết thì launch instance mới

---

## Multi-AZ dùng để làm gì?

| Component | Multi-AZ? | Mục đích |
|-----------|-----------|----------|
| RDS PostgreSQL | ✅ 2 AZ | **Data durability** — automatic failover, zero data loss. Mất AZ-A → standby AZ-B promote (~1-2 min) |
| NAT Gateway | ✅ 2 AZ | **Egress resilience** — mỗi AZ có NAT riêng. Mất 1 AZ, AZ còn lại vẫn có egress |
| ALB | ✅ 2 AZ | **AWS requirement** — ALB bắt buộc ≥2 AZ subnets |
| S3, CloudFront, Route 53 | ✅ Global/Regional | Managed services, AWS tự handle redundancy |
| **ECS/EC2 (compute)** | ❌ **Chỉ AZ-A** | Single-instance constraint từ code |

**Kết luận:** Multi-AZ bảo vệ **data** (RDS) và **network** (NAT, ALB), không bảo vệ **compute uptime**.

---

## Failure Scenarios

### Scenario 1: EC2 instance crash (AZ-A vẫn healthy)

```
EC2 dies → ASG detect unhealthy (health check fail)
         → ASG launch new instance (cùng AZ-A)
         → ECS agent register → ECS scheduler place tasks
         → Services acquire advisory locks → serve traffic
         
Downtime: ~3-5 phút
Data loss: Zero (RDS không bị ảnh hưởng)
```

### Scenario 2: AZ-A failure (toàn bộ AZ unavailable)

**Config hiện tại (ASG chỉ subnet AZ-A):**
```
AZ-A dies → EC2 dies → ASG CANNOT launch (subnet unavailable)
          → Services DOWN cho đến khi AZ-A recover
          
Downtime: Phụ thuộc AWS recovery (có thể hàng giờ)
Data loss: Zero (RDS auto-failover sang AZ-B)
```

**Config cải tiến (ASG span cả 2 AZ):**
```
AZ-A dies → EC2 dies → ASG launch new instance ở AZ-B
          → ECS tasks start → acquire locks (RDS đã failover sang AZ-B)
          → Serve traffic
          
Downtime: ~5-10 phút
Data loss: Zero
Cost change: $0 (chỉ thay đổi config)
```

### Scenario 3: ECS task crash (container OOM, bug)

```
Task dies → ECS restart task trên cùng EC2
          → Acquire advisory lock → serve traffic
          
Downtime: ~30 giây - 1 phút
Data loss: Zero
```

---

## Cải thiện: ASG span 2 AZ

Sửa 1 dòng Terraform để có auto-failover across AZ:

```hcl
# Hiện tại
resource "aws_autoscaling_group" "ecs" {
  vpc_zone_identifier = [module.foundation.private_app_subnet_a_id]  # chỉ AZ-A
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
}

# Cải tiến
resource "aws_autoscaling_group" "ecs" {
  vpc_zone_identifier = [
    module.foundation.private_app_subnet_a_id,  # AZ-A (preferred)
    module.foundation.private_app_subnet_b_id,  # AZ-B (failover)
  ]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
}
```

- Bình thường: ASG chọn 1 AZ (thường AZ-A, AWS balance)
- Nếu AZ đang chạy bị failure: ASG launch ở AZ còn lại
- **Cost: không đổi** — vẫn chỉ 1 instance chạy

---

## Tại sao accept trade-off này?

| Factor | Đánh giá |
|--------|----------|
| User impact | Single-user (Owner) — 5-10 min downtime acceptable |
| Data safety | ✅ Zero data loss nhờ RDS Multi-AZ |
| Cost | $0 additional cho failover across AZ |
| Code limitation | P5 priority cho horizontal scaling — upstream không sẽ fix sớm |
| Portfolio value | Vẫn demonstrate Multi-AZ pattern (data + network layer) |
| Recovery automation | ASG + ECS tự handle, không cần manual intervention |

---

## So sánh với các mức HA

| Level | Mô tả | Synapse đạt? | Chi phí thêm |
|-------|--------|--------------|--------------|
| **No HA** | Manual recovery | ❌ Hơn mức này | — |
| **Basic failover** | Auto-recover, downtime < 10 min | ✅ Đạt (với ASG 2 AZ) | $0 |
| **Warm standby** | Standby instance sẵn sàng, downtime < 1 min | ❌ Không thể — advisory lock | +$61/mo (instance thứ 2 idle) |
| **Active-Active** | Zero downtime | ❌ Không thể — code single-instance | Impossible |

**Synapse CE ở mức "Basic failover"** — phù hợp cho learning project và single-operator platform.

---

## Recommendation

Khi implement `synapse-aws-compute`:
1. ✅ Config ASG với cả 2 AZ subnets (failover miễn phí)
2. ✅ RDS Multi-AZ đã cover data durability
3. ⏭️ Không cần warm standby hay active-active (code không support, cost không justify)
4. 📝 Document expected downtime trong runbook: "AZ failure → ~5-10 min auto-recovery"

---

## Deep Dive: Tại sao không thể < 1 min

### Advisory lock là gì và tại sao nó chặn failover nhanh

PostgreSQL advisory lock là mechanism cho phép application "claim" một resource logic. Synapse dùng nó để đảm bảo chỉ 1 instance chạy:

```go
// Pseudocode từ synapse source
lock := pg_advisory_lock(role)  // role = "api" | "worker" | "mcp"
if !lock {
    log.Fatal("another instance running, exiting")  // EXIT ngay, không retry
}
```

**Quan trọng:** Code **fail closed** — nếu không lấy được lock thì tự kill. Không có retry loop.

### Flow khi failover

```
Instance cũ chết
    → TCP connection tới PostgreSQL bị reset
    → PostgreSQL detect disconnect → release advisory lock (gần instant)
    → Instance mới launch (đây là bottleneck)
    → Container start → connect DB → acquire lock → serve
```

Lock release **không phải bottleneck** (xảy ra instant). Bottleneck là thời gian launch infrastructure:

| Bước | Thời gian |
|------|-----------|
| ASG detect unhealthy | ~30s |
| Launch EC2 instance | ~60-90s |
| Boot OS + ECS agent register | ~30-60s |
| ECS place task + container start | ~15-30s |
| App startup + acquire lock + health check | ~10-20s |
| **Tổng** | **~3-5 min** |

### Warm standby cũng không giúp (vì code design)

Kể cả có instance thứ 2 **sẵn sàng**, không thể chạy container "chờ lock" vì:
- Container start → try lock → fail → `log.Fatal()` → container die
- ECS restart → try lock → fail → die again
- Loop vô tận cho đến khi instance 1 chết

Muốn warm standby hoạt động → phải **sửa code upstream** thành retry loop:
```go
// Cần sửa thành (nhưng không own code):
for {
    lock := pg_try_advisory_lock(role)
    if lock { break }
    time.Sleep(1 * time.Second)  // retry mỗi giây
}
```

---

## Cost vs Downtime Trade-off

| Target downtime | Cách làm | Cost thêm/mo | Khả thi? |
|-----------------|----------|--------------|-----------|
| **3-5 min** | ASG 2 AZ, auto-failover | **$0** | ✅ Chọn |
| **30-60s** | Warm standby EC2 (idle) | **+$61** | ⚠️ Vẫn bị code block (fail closed) |
| **< 10s** | Sửa code retry loop + 2 containers hot | +$61 + dev | ❌ Không own upstream code |
| **~0s (HA)** | Bỏ advisory lock, horizontal scale | +$61 + major refactor | ❌ Upstream nói P5 priority |

**Kết luận:** Mỗi bậc giảm downtime đều đổi bằng tiền hoặc engineering effort. Và ở case này, dù có tiền cũng bị ceiling ~30s vì code design.

---

## References

- CONSTRAINT-04: `cmd/synapse-api/main.go:363-377` — single-instance advisory lock
- CONSTRAINT-05: `cmd/synapse-mcp/main.go:67-73` — single-instance advisory lock
- DR-01: Worker on ECS/EC2, privileged
- DR-02: API+MCP cùng EC2 instance
- DR-03: RDS Multi-AZ (data protection)
- DR-06: VPC 2 AZ (network resilience)
- [AWS ASG — Multi-AZ deployment](https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-benefits.html)
- [AWS RDS Multi-AZ failover](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html)
