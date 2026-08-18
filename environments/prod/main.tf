# -----------------------------------------------------------------------------
# Synapse Infrastructure — Module Composition
# -----------------------------------------------------------------------------

module "foundation" {
  source = "../../modules/foundation"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = local.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  data_subnet_cidrs   = var.data_subnet_cidrs
  allowed_web_cidrs   = var.allowed_web_cidrs
  app_port            = var.app_port
}

module "identity_secrets" {
  source = "../../modules/identity-secrets"

  project             = var.project
  environment         = var.environment
  evidence_bucket_arn = "arn:aws:s3:::synapse-evidence-${data.aws_caller_identity.current.account_id}"
}

module "data_layer" {
  source = "../../modules/data-layer"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.foundation.vpc_id
  data_subnet_ids   = module.foundation.data_subnet_ids
  security_group_id = module.foundation.security_group_data_id
  kms_key_arn       = module.identity_secrets.kms_key_arn
}

module "compute" {
  source = "../../modules/compute"

  project                = var.project
  environment            = var.environment
  aws_region             = var.aws_region
  app_subnet_ids         = module.foundation.app_subnet_ids
  security_group_id      = module.foundation.security_group_app_id
  kms_key_arn            = module.identity_secrets.kms_key_arn
  ecs_execution_role_arn = module.identity_secrets.ecs_execution_role_arn
  api_task_role_arn      = module.identity_secrets.api_task_role_arn
  worker_task_role_arn   = module.identity_secrets.worker_task_role_arn
  mcp_task_role_arn      = module.identity_secrets.mcp_task_role_arn

  # ALB target group — wired from edge module
  alb_target_group_api_arn = module.edge.alb_target_group_api_arn

  # Secrets for container environment
  secret_api_token_arn = module.identity_secrets.secret_arns["api_token"]
  secret_db_dsn_arn    = module.identity_secrets.secret_arns["db_master_password"]
}

module "edge" {
  source = "../../modules/edge"

  project               = var.project
  environment           = var.environment
  vpc_id                = module.foundation.vpc_id
  public_subnet_ids     = module.foundation.public_subnet_ids
  ecs_security_group_id = module.foundation.security_group_app_id
  account_id            = data.aws_caller_identity.current.account_id
}

module "observability" {
  source = "../../modules/observability"

  project                 = var.project
  environment             = var.environment
  kms_key_arn             = module.identity_secrets.kms_key_arn
  alert_email             = var.alert_email
  asg_name                = module.compute.asg_name
  rds_instance_id         = module.data_layer.db_instance_id
  ecs_cluster_name        = module.compute.ecs_cluster_name
  ecs_service_name        = module.compute.api_service_name
  alb_arn_suffix          = module.edge.alb_arn_suffix
  target_group_arn_suffix = module.edge.target_group_arn_suffix
}
