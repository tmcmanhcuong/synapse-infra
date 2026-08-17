# Terraform Apply Failure Report — 2026-08-18 00:14 UTC

**Run:** #32049414088
**Trigger:** push to main (commit ec06651)
**Duration:** 11m 8s
**Result:** 5 errors

## Errors

### 1. CloudWatch Log Groups — KMS key permission denied (x3)

```
Error: creating CloudWatch Logs Log Group (/ecs/synapse-api):
  AccessDeniedException: The specified KMS key does not exist or is not allowed
  to be used with Arn 'arn:aws:logs:ap-southeast-1:945125812908:log-group:/ecs/synapse-api'
```

**Root cause:** KMS key policy trong `identity-secrets` module không grant `logs.amazonaws.com` service quyền sử dụng key. CloudWatch Logs cần explicit permission trong KMS key policy.

**Fix:** Thêm statement cho `logs.ap-southeast-1.amazonaws.com` vào KMS key policy:
```json
{
  "Effect": "Allow",
  "Principal": { "Service": "logs.ap-southeast-1.amazonaws.com" },
  "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"],
  "Resource": "*",
  "Condition": {
    "ArnLike": {
      "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:ap-southeast-1:945125812908:log-group:*"
    }
  }
}
```

### 2. Auto Scaling Group — EC2 instances not launching

```
Error: waiting for Auto Scaling Group (synapse-ecs-asg-prod) capacity satisfied:
  timeout: want at least 1 healthy instance(s), have 0
```

**Root cause:** EC2 instances failing to launch. Possible causes:
- Launch template references AMI not available
- Instance profile/role not yet propagated (IAM eventual consistency)
- Security group egress rules preventing ECS agent registration
- Subnet has no route to internet (NAT Gateway route)

**Fix:** Check ASG activity log for exact failure. Likely needs IAM instance profile association or NAT route fix.

### 3. RDS Parameter Group — Static parameter immediate apply

```
Error: modifying RDS DB Parameter Group (synapse-pg17-prod):
  InvalidParameterCombination: cannot use immediate apply method for static parameter
```

**Root cause:** `rds.force_ssl` parameter được thêm vào parameter group. `shared_preload_libraries` là **static parameter** — chỉ apply khi reboot. Terraform mặc định dùng `immediate` apply method.

**Fix:** Thêm `apply_method = "pending-reboot"` cho parameter `shared_preload_libraries`:
```hcl
parameter {
  name         = "shared_preload_libraries"
  value        = "pg_stat_statements"
  apply_method = "pending-reboot"
}
```

### 4. Secrets Manager Rotation — No Lambda function

```
Error: creating Secrets Manager Secret Rotation:
  InvalidRequestException: No Lambda rotation function ARN is associated with this secret.
```

**Root cause:** Module `identity-secrets` có resource `aws_secretsmanager_secret_rotation` cho db-master-password, nhưng không có Lambda rotation function. Secrets Manager yêu cầu Lambda ARN để rotate.

**Fix:** Xóa `aws_secretsmanager_secret_rotation` resource (vì RDS `manage_master_user_password = true` tự quản lý rotation), hoặc dùng RDS-managed rotation.

## Priority

1. KMS key policy (blocks log groups → blocks ECS)
2. RDS parameter apply_method (blocks parameter group)
3. Secrets Manager rotation (remove resource)
4. ASG timeout (diagnose after above fixes — may self-resolve)
