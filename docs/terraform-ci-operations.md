# Terraform CI/CD Operations Guide

> Generated from `aws-terraform-ci-pipeline` skill for `tmcmanhcuong/synapse-infra`

---

## Files Created

| File | Purpose |
|------|---------|
| `.github/workflows/terraform-ci.yml` | PR validation: fmt, validate, TFLint, Checkov, plan, Infracost, artifact upload |
| `.github/workflows/terraform-apply.yml` | Apply reviewed plan artifact with environment approval gate |
| `.github/workflows/terraform-drift.yml` | Scheduled drift detection (Mon-Fri 2:00 AM UTC) |
| `.github/actions/setup-terraform-cached/action.yml` | Composite action: Terraform install + provider cache |
| `.tflint.hcl` | TFLint config: AWS ruleset + naming/docs rules |
| `environments/prod/backend.tf` | S3 backend with `use_lockfile = true` (native locking) |

---

## Pipeline Behavior

| Aspect | Value |
|--------|-------|
| PR validation | fmt → init → validate → TFLint → terraform test → Checkov → plan → Infracost |
| Apply model | `reviewed-pr-plan-artifact` (not re-plan) |
| Apply trigger | `workflow_dispatch` with PR number + environment |
| Environment approval | Required for `production` |
| Drift detection | `terraform plan -detailed-exitcode`, fails on exit code 2 |
| Checkov | ✅ Enabled, fail on HIGH/CRITICAL |
| TFLint | ✅ Enabled, AWS ruleset |
| Terraform tests | ✅ Conditional (runs if `.tftest.hcl` files exist) |
| Infracost | ✅ Conditional (runs if `INFRACOST_API_KEY` secret exists) |
| Provider cache | ✅ Enabled via composite action |
| Actions pinning | Version tags (readability mode) |
| State locking | S3 native (`use_lockfile = true`) — no DynamoDB table needed |

---

## GitHub Secrets To Create

### Repository Secrets (for PR plan jobs — no Environment attached)

| Secret | Value | Required |
|--------|-------|----------|
| `AWS_TERRAFORM_PLAN_ROLE_ARN` | ARN of the OIDC plan role | Yes |
| `AWS_REGION` | `us-east-1` | Yes |
| `TF_STATE_BUCKET` | S3 bucket name for state | Yes |
| `TF_BACKEND_REGION` | Region of state bucket (if different from AWS_REGION) | No |
| `INFRACOST_API_KEY` | Infracost API key | Optional |

### Environment Secrets (Environment: `production`, with approval gate)

| Secret | Value | Required |
|--------|-------|----------|
| `AWS_TERRAFORM_APPLY_ROLE_ARN` | ARN of the OIDC apply role | Yes |
---

## AWS Setup Commands

### 1. Create OIDC Provider (one-time)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list sts.amazonaws.com \
  --profile cuong-admin
```

### 2. Create Plan Role

```bash
cat > github-actions-plan-trust.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GitHubActionsOIDC",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:tmcmanhcuong/synapse-infra:ref:refs/heads/main",
            "repo:tmcmanhcuong/synapse-infra:pull_request"
          ]
        }
      }
    }
  ]
}
JSON

aws iam create-role \
  --role-name synapse-github-actions-plan \
  --profile cuong-admin

aws iam attach-role-policy \
  --role-name synapse-github-actions-plan \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess \
  --profile cuong-admin
```

### 3. Create Apply Role

```bash
cat > github-actions-apply-trust.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GitHubActionsOIDC",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:tmcmanhcuong/synapse-infra:environment:production"
        }
      }
    }
  ]
}
JSON

aws iam create-role \
  --role-name synapse-github-actions-apply \
  --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GitHubActionsOIDC",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:tmcmanhcuong/synapse-infra:environment:production"
        }
      }
    }
  ]
}' \
--profile cuong-admin

aws iam attach-role-policy \
  --role-name synapse-github-actions-apply \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess \
  --profile cuong-admin

aws iam attach-role-policy \
  --role-name synapse-github-actions-apply \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
  --profile cuong-admin
```

### 4. Create S3 State Bucket

```bash
aws s3api create-bucket \
  --bucket synapse-terraform-state-945125812908 \
  --region us-east-1 \
  --profile cuong-admin

aws s3api put-bucket-versioning \
  --bucket synapse-terraform-state-945125812908 \
  --versioning-configuration Status=Enabled \
  --profile cuong-admin

aws s3api put-bucket-encryption \
  --bucket synapse-terraform-state-945125812908 \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]
  }' \
  --profile cuong-admin

aws s3api put-public-access-block \
  --bucket synapse-terraform-state-945125812908 \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }' \
  --profile cuong-admin
```

### 5. Get Role ARNs

```bash
aws iam get-role --role-name synapse-github-actions-plan --query 'Role.Arn' --output text
aws iam get-role --role-name synapse-github-actions-apply --query 'Role.Arn' --output text
```

---

## GitHub Repository Setup

1. **Settings → Environments** → Create `production` environment
2. **Environment protection rules** → Add required reviewer
3. **Settings → Secrets and variables → Actions** → Add repository secrets
4. **Settings → Branches** → Add branch protection on `main`:
   - Require PR before merge
   - Require status checks: `Validate & Plan`
   - Require approvals: 1

---

## OIDC Trust Compatibility Notes

- Plan job does NOT set `environment:` — trust uses `pull_request` sub claim
- Apply job sets `environment: production` — trust uses `environment:production` sub claim
- Fork PRs: static checks only (no OIDC access, no secrets)

---

## Workflow Usage

### Normal flow:

1. Create feature branch, make changes
2. Open PR → `terraform-ci.yml` runs automatically
3. Review plan output in PR comment + artifacts
4. Merge PR
5. Go to Actions → `Terraform Apply` → Run workflow → Enter PR number + `production`
6. Approval gate fires → reviewer approves → apply runs

### Drift check:

- Runs automatically Mon-Fri at 2:00 AM UTC
- Manual trigger: Actions → `Terraform Drift Detection` → Run workflow
- If drift detected: workflow fails, review manually

---

## Verification Status

- [x] Workflow YAML syntax valid
- [x] Backend uses `use_lockfile = true` (S3 native locking)
- [x] No hardcoded role ARNs or bucket names
- [x] Secrets referenced via `${{ secrets.* }}`
- [x] Concurrency groups prevent parallel state modifications
- [x] Apply uses saved plan artifact with checksum verification
- [ ] AWS IAM roles: manual creation required (see commands above)
- [ ] GitHub secrets: manual creation required
- [ ] End-to-end test: pending first PR
