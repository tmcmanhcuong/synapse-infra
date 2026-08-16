# Synapse Infrastructure

Terraform infrastructure for Synapse CE platform on AWS.

## Structure

```
synapse-infra/
├── modules/
│   ├── foundation/         # VPC, subnets, NAT, Security Groups
│   ├── identity-secrets/   # IAM roles, KMS, Secrets Manager
│   ├── data-layer/         # RDS PostgreSQL, S3
│   ├── compute/            # ECS Fargate, Task Defs, ALB
│   ├── edge/               # CloudFront, WAF
│   └── observability/      # CloudWatch, Alarms, Dashboards
├── environments/
│   └── prod/               # Production environment config
└── scripts/                # Helper scripts
```

## Usage

```bash
cd environments/prod
terraform init
terraform plan
terraform apply
```

## Module Dependency Order

1. foundation (VPC + network)
2. identity-secrets (IAM + KMS)
3. data-layer (RDS + S3)
4. compute (ECS + ALB)
5. edge (CloudFront + WAF)
6. observability (CloudWatch)

## Prerequisites

- Terraform >= 1.9
- AWS CLI configured with appropriate credentials
- S3 state bucket + DynamoDB lock table created (bootstrap)
