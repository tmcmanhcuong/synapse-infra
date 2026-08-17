################################################################################
# Data Sources
################################################################################

data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

################################################################################
# CloudWatch Log Groups
################################################################################

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/synapse-api"
  retention_in_days = 30

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-api"
  }
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/synapse-worker"
  retention_in_days = 30

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-worker"
  }
}

resource "aws_cloudwatch_log_group" "mcp" {
  name              = "/ecs/synapse-mcp"
  retention_in_days = 30

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-mcp"
  }
}

################################################################################
# ECR Repositories
################################################################################

locals {
  ecr_repositories = ["synapse-worker", "synapse-api", "synapse-mcp"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.ecr_repositories)

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

################################################################################
# IAM Role for ECS EC2 Instances
################################################################################

resource "aws_iam_role" "ecs_instance" {
  name = "${var.project}-ecs-instance-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecs" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.project}-ecs-instance-${var.environment}"
  role = aws_iam_role.ecs_instance.name
}

################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  name = "synapse-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

################################################################################
# EC2 Launch Template
################################################################################

resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.project}-ecs-${var.environment}-"
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  vpc_security_group_ids = [var.security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.this.name}" >> /etc/ecs/ecs.config
  EOF
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project}-ecs-${var.environment}"
      Project     = var.project
      Environment = var.environment
    }
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

################################################################################
# Auto Scaling Group
################################################################################

resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project}-ecs-asg-${var.environment}"
  vpc_zone_identifier = var.app_subnet_ids
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-ecs-${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# ECS Capacity Provider
################################################################################

resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.project}-ec2-${var.environment}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      maximum_scaling_step_size = 1
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ec2.name
  }
}

################################################################################
# ECS Task Definitions
################################################################################

resource "aws_ecs_task_definition" "api" {
  family                   = "synapse-api-${var.environment}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "2048"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.api_task_role_arn

  container_definitions = jsonencode([
    {
      name       = "synapse-api"
      image      = "${aws_ecr_repository.this["synapse-api"].repository_url}:latest"
      cpu        = 512
      memory     = 2048
      essential  = true
      privileged = false

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-api"
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "synapse-worker-${var.environment}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "1024"
  memory                   = "3072"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.worker_task_role_arn

  container_definitions = jsonencode([
    {
      name       = "synapse-worker"
      image      = "${aws_ecr_repository.this["synapse-worker"].repository_url}:latest"
      cpu        = 1024
      memory     = 3072
      essential  = true
      privileged = true

      linuxParameters = {
        capabilities = {
          add = ["NET_ADMIN", "SYS_ADMIN"]
        }
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-worker"
  }
}

resource "aws_ecs_task_definition" "mcp" {
  family                   = "synapse-mcp-${var.environment}"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "1024"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.mcp_task_role_arn

  container_definitions = jsonencode([
    {
      name       = "synapse-mcp"
      image      = "${aws_ecr_repository.this["synapse-mcp"].repository_url}:latest"
      cpu        = 256
      memory     = 1024
      essential  = true
      privileged = false

      portMappings = [
        {
          containerPort = 8081
          hostPort      = 8081
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mcp.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-mcp"
  }
}

################################################################################
# ECS Service - API
################################################################################

resource "aws_ecs_service" "api" {
  name            = "synapse-api-${var.environment}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.ecs_api_desired_count

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    base              = 1
    weight            = 100
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  # Attach to ALB target group when provided
  dynamic "load_balancer" {
    for_each = var.alb_target_group_api_arn != "" ? [1] : []
    content {
      target_group_arn = var.alb_target_group_api_arn
      container_name   = "synapse-api"
      container_port   = 8080
    }
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    Service     = "synapse-api"
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}
