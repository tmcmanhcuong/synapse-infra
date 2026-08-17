################################################################################
# Data Layer Module - RDS PostgreSQL + S3 Evidence Bucket
# Platform: Synapse CE
################################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
}

################################################################################
# RDS PostgreSQL
################################################################################

# Custom parameter group with pg_stat_statements
resource "aws_db_parameter_group" "synapse" {
  name        = "synapse-pg17-${var.environment}"
  family      = "postgres17"
  description = "Custom parameter group for Synapse PostgreSQL 17"

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = {
    Name        = "synapse-pg17-${var.environment}"
    Project     = var.project
    Environment = var.environment
  }
}

# DB subnet group
resource "aws_db_subnet_group" "synapse" {
  name       = "synapse-db-${var.environment}"
  subnet_ids = var.data_subnet_ids

  tags = {
    Name        = "synapse-db-${var.environment}"
    Project     = var.project
    Environment = var.environment
  }
}

# IAM role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "synapse-rds-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "synapse-rds-monitoring-${var.environment}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS PostgreSQL instance
# NOTE: db.t3.medium is burstable (T-class). For production workloads with
# sustained CPU usage, consider db.r6g.large or higher (Graviton, memory-optimized).
resource "aws_db_instance" "synapse" {
  identifier = "synapse-db-${var.environment}"

  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.synapse.name
  vpc_security_group_ids = [var.security_group_id]

  # AWS-managed master credentials via Secrets Manager
  manage_master_user_password = true
  username                    = "synapse_admin"

  parameter_group_name = aws_db_parameter_group.synapse.name

  # Backup configuration
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:00-Sun:05:00"

  # Snapshot and deletion protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "synapse-db-final-${var.environment}"
  deletion_protection       = true

  # Performance Insights
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  # CloudWatch Logs exports
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Enhanced Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "synapse-db-${var.environment}"
    Project     = var.project
    Environment = var.environment
  }
}

################################################################################
# S3 Evidence Bucket
################################################################################

resource "aws_s3_bucket" "evidence" {
  bucket              = "synapse-evidence-${data.aws_caller_identity.current.account_id}"
  object_lock_enabled = true

  tags = {
    Name        = "synapse-evidence-${data.aws_caller_identity.current.account_id}"
    Project     = var.project
    Environment = var.environment
  }
}

# Versioning (required for Object Lock)
resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Object Lock default retention
resource "aws_s3_bucket_object_lock_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 365
    }
  }

  depends_on = [aws_s3_bucket_versioning.evidence]
}

# Server-side encryption with KMS CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy: explicit deny on delete operations
data "aws_iam_policy_document" "evidence_deny_delete" {
  statement {
    sid    = "DenyObjectDeletion"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
    ]

    resources = [
      "${aws_s3_bucket.evidence.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "evidence" {
  bucket = aws_s3_bucket.evidence.id
  policy = data.aws_iam_policy_document.evidence_deny_delete.json
}
