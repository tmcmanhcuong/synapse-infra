# -----------------------------------------------------------------------------
# GitHub Actions OIDC Roles — synapse-ce repo (app CI/CD)
# -----------------------------------------------------------------------------
# OIDC Provider đã tạo thủ công cho synapse-infra.
# Reference nó qua data source, thêm roles cho synapse-ce repo.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# -----------------------------------------------------------------------------
# Build Role — push ECR + pull for scan
# Trust: synapse-ce repo, any branch (build runs on PR + push)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "synapse_ce_build" {
  name = "synapse-ce-github-actions-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:tmcmanhcuong@101078914/synapse-ce@1334183147:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Project     = "synapse"
    Environment = "prod"
    Purpose     = "github-actions-build"
    Repository  = "tmcmanhcuong/synapse-ce"
  }
}

resource "aws_iam_role_policy" "synapse_ce_build_ecr" {
  name = "ecr-push"
  role = aws_iam_role.synapse_ce_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
        ]
        Resource = "arn:aws:ecr:ap-southeast-1:${data.aws_caller_identity.current.account_id}:repository/synapse-*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Deploy Role — update ECS + S3 write + CloudFront invalidation
# Trust: synapse-ce repo, main branch only (deploy gate)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "synapse_ce_deploy" {
  name = "synapse-ce-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:tmcmanhcuong@101078914/synapse-ce@1334183147:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Project     = "synapse"
    Environment = "prod"
    Purpose     = "github-actions-deploy"
    Repository  = "tmcmanhcuong/synapse-ce"
  }
}

resource "aws_iam_role_policy" "synapse_ce_deploy_ecs" {
  name = "ecs-deploy"
  role = aws_iam_role.synapse_ce_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSTaskDefinition"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSServiceOps"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
        ]
        Resource = "arn:aws:ecs:ap-southeast-1:${data.aws_caller_identity.current.account_id}:service/synapse-*"
      },
      {
        Sid    = "ECSTaskOps"
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
        ]
        Resource = "arn:aws:ecs:ap-southeast-1:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/synapse-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "synapse_ce_deploy_s3" {
  name = "s3-web-deploy"
  role = aws_iam_role.synapse_ce_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3WebDeploy"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:aws:s3:::synapse-web-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::synapse-web-${data.aws_caller_identity.current.account_id}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "synapse_ce_deploy_cloudfront" {
  name = "cloudfront-invalidation"
  role = aws_iam_role.synapse_ce_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CFInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "synapse_ce_build_role_arn" {
  description = "OIDC role ARN for synapse-ce build jobs (set as AWS_ROLE_ARN secret)"
  value       = aws_iam_role.synapse_ce_build.arn
}

output "synapse_ce_deploy_role_arn" {
  description = "OIDC role ARN for synapse-ce deploy jobs (set as AWS_DEPLOY_ROLE_ARN secret)"
  value       = aws_iam_role.synapse_ce_deploy.arn
}
