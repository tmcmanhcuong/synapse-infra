################################################################################
# Observability Module - SNS, CloudWatch Alarms, Budget, Dashboard
################################################################################

locals {
  tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# SNS Topic & Subscription
# ------------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name              = "synapse-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = merge(local.tags, {
    Name = "synapse-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------------------------
# CloudWatch Alarm - EC2 ASG CPU Utilization
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${var.project}-ec2-cpu-high"
  alarm_description   = "EC2 ASG CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, {
    Name = "${var.project}-ec2-cpu-high"
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Alarm - RDS CPU Utilization
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project}-rds-cpu-high"
  alarm_description   = "RDS CPU utilization exceeds 70%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, {
    Name = "${var.project}-rds-cpu-high"
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Alarm - RDS Free Storage Space
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.project}-rds-storage-low"
  alarm_description   = "RDS free storage space below 5 GiB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, {
    Name = "${var.project}-rds-storage-low"
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Alarm - ECS Unhealthy Hosts
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ecs_unhealthy" {
  alarm_name          = "${var.project}-ecs-unhealthy-hosts"
  alarm_description   = "ECS target group has unhealthy hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  treat_missing_data  = "missing"

  dimensions = {
    TargetGroup  = var.target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, {
    Name = "${var.project}-ecs-unhealthy-hosts"
  })
}

# ------------------------------------------------------------------------------
# CloudWatch Alarm - ALB 5xx Errors
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx-high"
  alarm_description   = "ALB target 5XX count exceeds 10"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(local.tags, {
    Name = "${var.project}-alb-5xx-high"
  })
}

# ------------------------------------------------------------------------------
# AWS Budget
# ------------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly-cost"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 78
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# CloudWatch Dashboard
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "synapse-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS CPU Utilization"
          region  = "ap-southeast-1"
          metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]]
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS Memory Utilization"
          region  = "ap-southeast-1"
          metrics = [["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]]
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "ALB Request Count"
          region  = "ap-southeast-1"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]]
          period  = 300
          stat    = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "RDS CPU Utilization"
          region  = "ap-southeast-1"
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id]]
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "RDS Free Storage Space"
          region  = "ap-southeast-1"
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id]]
          period  = 300
          stat    = "Average"
        }
      }
    ]
  })
}
