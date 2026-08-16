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

# module "identity_secrets" {
#   source = "../../modules/identity-secrets"
#
#   project     = var.project
#   environment = var.environment
#   vpc_id      = module.foundation.vpc_id
# }

# module "data_layer" {
#   source = "../../modules/data-layer"
#
#   project            = var.project
#   environment        = var.environment
#   vpc_id             = module.foundation.vpc_id
#   data_subnet_ids    = module.foundation.data_subnet_ids
#   security_group_id  = module.foundation.security_group_data_id
# }

# module "compute" {
#   source = "../../modules/compute"
#
#   project            = var.project
#   environment        = var.environment
#   vpc_id             = module.foundation.vpc_id
#   app_subnet_ids     = module.foundation.app_subnet_ids
#   public_subnet_ids  = module.foundation.public_subnet_ids
#   security_group_id  = module.foundation.security_group_app_id
# }

# module "edge" {
#   source = "../../modules/edge"
#
#   project     = var.project
#   environment = var.environment
# }

# module "observability" {
#   source = "../../modules/observability"
#
#   project     = var.project
#   environment = var.environment
# }
