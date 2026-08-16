terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name

  default_tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  secrets = {
    db_master_password    = "${var.project}/${var.environment}/db-master-password"
    api_token             = "${var.project}/${var.environment}/api-token"
    vault_master_key      = "${var.project}/${var.environment}/vault-master-key"
    evidence_signing_seed = "${var.project}/${var.environment}/evidence-signing-seed"
  }
}

# ------------------------------------------------------------------------------
# KMS CMK
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_key_policy" {
  # Allow account root full access
  statement {
    sid    = "EnableRootAccountAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Allow Secrets Manager to use the key
  statement {
    sid    = "AllowSecretsManagerUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Allow RDS to use the key
  statement {
    sid    = "AllowRDSUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "Synapse platform encryption key - ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = local.default_tags
}

resource "aws_kms_alias" "platform" {
  name          = "alias/synapse-platform"
  target_key_id = aws_kms_key.platform.key_id
}

# ------------------------------------------------------------------------------
# Secrets Manager
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets

  name        = each.value
  description = "Synapse ${var.environment} secret: ${each.key}"
  kms_key_id  = aws_kms_key.platform.arn

  tags = local.default_tags
}

# Auto-rotation for db-master-password (30 days)
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id = aws_secretsmanager_secret.this["db_master_password"].id

  rotation_rules {
    automatically_after_days = 30
  }
}

# ------------------------------------------------------------------------------
# IAM: ECS Execution Role
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_execution" {
  name_prefix        = "${local.name_prefix}-ecs-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_custom" {
  statement {
    sid    = "SecretsAccess"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = [for s in aws_secretsmanager_secret.this : s.arn]
  }

  statement {
    sid    = "ECRAuth"
    effect = "Allow"

    actions = ["ecr:GetAuthorizationToken"]

    resources = ["*"]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = [aws_kms_key.platform.arn]
  }
}

resource "aws_iam_policy" "ecs_execution_custom" {
  name_prefix = "${local.name_prefix}-ecs-exec-custom-"
  description = "Custom permissions for Synapse ECS execution role"
  policy      = data.aws_iam_policy_document.ecs_execution_custom.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_custom" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.ecs_execution_custom.arn
}

# ------------------------------------------------------------------------------
# IAM: API Task Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "api_task" {
  name_prefix        = "${local.name_prefix}-api-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "api_task" {
  statement {
    sid    = "EvidenceBucketAccess"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]

    resources = ["${var.evidence_bucket_arn}/*"]
  }

  statement {
    sid    = "SecretsAccess"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = [for s in aws_secretsmanager_secret.this : s.arn]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = [aws_kms_key.platform.arn]
  }
}

resource "aws_iam_policy" "api_task" {
  name_prefix = "${local.name_prefix}-api-task-"
  description = "Permissions for Synapse API task role"
  policy      = data.aws_iam_policy_document.api_task.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "api_task" {
  role       = aws_iam_role.api_task.name
  policy_arn = aws_iam_policy.api_task.arn
}

# ------------------------------------------------------------------------------
# IAM: Worker Task Role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "worker_task" {
  name_prefix        = "${local.name_prefix}-worker-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "worker_task" {
  statement {
    sid    = "EvidenceBucketObjectAccess"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]

    resources = ["${var.evidence_bucket_arn}/*"]
  }

  statement {
    sid    = "EvidenceBucketListAccess"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = [var.evidence_bucket_arn]
  }

  statement {
    sid    = "SecretsAccess"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = [for s in aws_secretsmanager_secret.this : s.arn]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = [aws_kms_key.platform.arn]
  }
}

resource "aws_iam_policy" "worker_task" {
  name_prefix = "${local.name_prefix}-worker-task-"
  description = "Permissions for Synapse worker task role"
  policy      = data.aws_iam_policy_document.worker_task.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "worker_task" {
  role       = aws_iam_role.worker_task.name
  policy_arn = aws_iam_policy.worker_task.arn
}

# ------------------------------------------------------------------------------
# IAM: MCP Task Role (read-only)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "mcp_task" {
  name_prefix        = "${local.name_prefix}-mcp-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "mcp_task" {
  statement {
    sid    = "SecretsAccess"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = [for s in aws_secretsmanager_secret.this : s.arn]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"

    actions = ["kms:Decrypt"]

    resources = [aws_kms_key.platform.arn]
  }
}

resource "aws_iam_policy" "mcp_task" {
  name_prefix = "${local.name_prefix}-mcp-task-"
  description = "Permissions for Synapse MCP task role (read-only)"
  policy      = data.aws_iam_policy_document.mcp_task.json

  tags = local.default_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "mcp_task" {
  role       = aws_iam_role.mcp_task.name
  policy_arn = aws_iam_policy.mcp_task.arn
}
