# Terraform Apply Failure — ASG AlreadyExists (PR #4 re-run)

**Date:** 2026-08-18 00:55 UTC+7
**Commit:** 9d9409a (fix: add Auto Scaling KMS grant for EBS encryption)
**Error:** `AlreadyExists: AutoScalingGroup by this name already exists`

## Lỗi

```
Error: creating Auto Scaling Group (synapse-ecs-asg-prod):
  AlreadyExists: AutoScalingGroup by this name already exists
```

## Root Cause

Đây là **state desync** do lỗi trước đó:

1. Lần apply #3: Terraform tạo ASG thành công, nhưng **timeout** chờ instances healthy (do KMS key issue) → Terraform đánh dấu ASG là **tainted** trong state.

2. Lần apply #4+: Terraform thấy ASG tainted → quyết định **destroy rồi create lại**.

3. Nhưng khi destroy: Terraform gửi lệnh delete ASG → AWS bắt đầu draining (process mất thời gian) HOẶC destroy thất bại/chưa hoàn tất.

4. Terraform tiếp tục **create** ASG mới cùng tên → AWS trả `AlreadyExists` vì ASG cũ vẫn còn tồn tại.

### Trạng thái hiện tại

- **AWS:** ASG `synapse-ecs-asg-prod` **tồn tại** (created 2026-08-17T17:15:10)
- **Terraform state:** ASG marked **tainted** (muốn replace)
- **Conflict:** Terraform muốn tạo mới nhưng tên đã bị chiếm

## Fix: Untaint ASG trong state

Vì KMS key policy đã fix (commit trước), ASG hiện tại CÓ THỂ hoạt động được. Không cần destroy/recreate -- chỉ cần **untaint** để Terraform nhận lại ASG hiện tại rồi update in-place.

```bash
terraform taint -untaint module.compute.aws_autoscaling_group.ecs
# hoặc (Terraform >= 1.0):
terraform untaint module.compute.aws_autoscaling_group.ecs
```

Sau đó `terraform apply` sẽ:
- KHÔNG destroy ASG (vì đã untaint)
- Update ASG nếu cần (desired_count, tags, etc.)
- Tạo capacity provider + ECS service + dashboard + alarm

## Alternative: Import ASG vào state

Nếu untaint không work (state corrupt):
```bash
terraform state rm module.compute.aws_autoscaling_group.ecs
terraform import module.compute.aws_autoscaling_group.ecs synapse-ecs-asg-prod
```

## Lưu ý

- Untaint chỉ sửa remote state (S3) → phải chạy trên máy CÓ backend access
- CI workflow (GitHub Actions) không có cách untaint trước apply
- Fix trong CI: hoặc chạy untaint thủ công trước push, hoặc thay đổi code để force_name_prefix thay vì static name
