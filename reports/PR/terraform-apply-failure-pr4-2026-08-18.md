# Terraform Apply Failure Report — PR #4 (Run #32050584424)

**Date:** 2026-08-18 00:32 UTC+7
**Commit:** 07337bc (fix: resolve terraform apply failures)
**Duration:** 16m 8s
**Result:** FAILED — exit code 1 tại step "Terraform apply"

## Trạng thái hiện tại (từ terraform state)

Resources **ĐÃ TẠO THÀNH CÔNG** (từ 2 lần apply):
- ✅ module.foundation: 21 resources (VPC, subnets, NATs, SGs, flow logs)
- ✅ module.identity_secrets: 17 resources (KMS, Secrets, IAM roles)
- ✅ module.data_layer: 10 resources (RDS PostgreSQL 17, S3 evidence bucket)
- ✅ module.compute: ECR repos (3), ECS cluster, task defs (3), log groups (3), launch template, ASG, IAM
- ✅ module.edge: ALB, listener, target group, S3 web bucket, CloudFront, OAC, SG
- ✅ module.observability: SNS topic, 4 alarms (rds_cpu, rds_storage, ecs_unhealthy, alb_5xx), budget
- ✅ OIDC roles: synapse-ce build + deploy roles

Resources **CHƯA TẠO ĐƯỢC** (plan shows 7 to add, 1 to change, 2 to destroy):
- ❌ module.compute.aws_ecs_capacity_provider.ec2 — chưa tạo
- ❌ module.compute.aws_ecs_cluster_capacity_providers.this — chưa tạo
- ❌ module.compute.aws_ecs_service.api — chưa tạo
- ❌ module.observability.aws_cloudwatch_dashboard.overview — chưa tạo
- ❌ module.observability.aws_cloudwatch_metric_alarm.ec2_cpu — chưa tạo
- ⚠️ module.compute.aws_autoscaling_group.ecs — TAINTED (cần replace)
- ⚠️ module.compute.aws_ecs_task_definition.worker — cần replace

## Root Cause: KMS Key Policy thiếu Auto Scaling Grant

### Lỗi chính xác (từ ASG Activity Log)

```
StatusMessage: Instance became unhealthy while waiting for instance to be in InService state.
Termination Reason: Client.InvalidKMSKey.InvalidState: The KMS key provided is in an incorrect state
```

**6 instances đã bị terminated** liên tiếp với cùng lỗi này.

### Giải thích kỹ thuật

1. Launch template yêu cầu EBS volume encrypted bằng CMK:
   ```
   kms_key_id = arn:aws:kms:ap-southeast-1:945125812908:key/0ae5919e-18b2-4986-8683-f4e3ac9b84ff
   ```

2. Auto Scaling Group dùng **AWS service-linked role** (`AWSServiceRoleForAutoScaling`) để launch instances.

3. Service-linked role này cần **KMS grant** để:
   - `kms:CreateGrant` — delegate encrypt/decrypt cho EC2 instance
   - `kms:Decrypt` — decrypt EBS volume khi attach
   - `kms:DescribeKey` — verify key state
   - `kms:GenerateDataKeyWithoutPlaintext` — encrypt EBS volume
   - `kms:ReEncryptFrom` / `kms:ReEncryptTo` — re-encryption operations

4. KMS key policy hiện tại **CHỈ CÓ**:
   - Root account (`kms:*`)
   - Secrets Manager service
   - RDS service
   - CloudWatch Logs service

5. **THIẾU**: Auto Scaling service (`autoscaling.amazonaws.com`) hoặc explicit grant cho service-linked role.

### Tại sao Root Account access không đủ?

Root account statement cho phép **IAM users/roles trong account** quản lý key. Nhưng Auto Scaling **service-linked role** (`arn:aws:iam::945125812908:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling`) hoạt động khác:
- Nó là role do AWS manage, KHÔNG nằm dưới root account principal
- Nó cần **explicit key policy statement** hoặc **KMS grant** để sử dụng CMK cho EBS encryption

### Cascade failures

```
KMS key deny ASG service role
  → EC2 instances fail to launch (EBS can't be encrypted)
    → ASG capacity = 0 (timeout after 10+ min)
      → ASG tainted in Terraform state
        → Capacity Provider can't be created (depends on healthy ASG)
          → ECS Service can't be created (depends on capacity provider)
```

## Fix cần thiết

Thêm statement vào KMS key policy (`modules/identity-secrets/main.tf`):

```hcl
statement {
  sid    = "AllowAutoScalingUse"
  effect = "Allow"

  principals {
    type        = "AWS"
    identifiers = [
      "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
    ]
  }

  actions = [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:Encrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncryptFrom",
    "kms:ReEncryptTo",
    "kms:CreateGrant",
  ]

  resources = ["*"]

  condition {
    test     = "StringEquals"
    variable = "kms:ViaService"
    values   = ["ec2.ap-southeast-1.amazonaws.com"]
  }
}
```

### Sau khi fix KMS policy

Terraform sẽ:
1. Update KMS key policy (in-place change)
2. Destroy tainted ASG + recreate
3. Create capacity provider
4. Create ECS service (với desired_count = 0, do variable)
5. Create dashboard + ec2_cpu alarm
6. Replace worker task definition (drift)

## Lỗi phụ (warnings, không block)

- **Node.js 20 deprecation**: Actions `checkout@v4`, `configure-aws-credentials@v4`, `setup-terraform@v3` dùng Node.js 20. GitHub đang force chạy trên Node.js 24. Warning only, không gây fail.

## References

- [AWS Docs: Required CMK key policy for use with encrypted EBS volumes](https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html)
- Previous report: `reports/PR/terraform-apply-failure-2026-08-18.md`
- ASG service-linked role: `arn:aws:iam::945125812908:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling`
