# Composición del entorno dev. modulo añade una seccion aqui:
#
#   module "network"       { source = "../../modules/network" ... }        
#   module "security"      { source = "../../modules/security" ... }       
#   module "data"          { source = "../../modules/data" ... }           
#   module "compute"       { source = "../../modules/compute" ... }        
#   module "edge"          { source = "../../modules/edge" ... }           
#   module "serverless"    { source = "../../modules/serverless" ... }    
#   module "observability" { source = "../../modules/observability" ... }  
#   module "cost"          { source = "../../modules/cost" ... }

data "aws_caller_identity" "current" {} # Le preguntamos a aws el id de la cuenta

data "aws_region" "current" {} # Le preguntamos a aws que region esta trabajando la cuenta

locals {
  name_prefix       = "${var.project}-${var.environment}" # prefijo de los nombres
  metrics_namespace = "ShopFlow"
}

# seguridad. dos servicios activables (se explican en el modulo)
module "security" {
  source = "../../modules/security"

  name                   = local.name_prefix
  enable_guardduty       = var.enable_guardduty
  enable_access_analyzer = var.enable_access_analyzer
}

# red. VPC en 2 AZ con subredes pública / app / datos.
module "network" {
  source = "../../modules/network"

  name               = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  nat_mode           = var.nat_mode
  nat_gateway_per_az = false

  flow_logs_kms_key_arn = module.security.logs_kms_key_arn
}

# almacenamiento
module "data" {
  source = "../../modules/data"

  name             = local.name_prefix
  vpc_id           = module.network.vpc_id
  data_subnet_ids  = module.network.data_subnet_ids
  app_subnet_ids   = module.network.app_subnet_ids
  data_kms_key_arn = module.security.data_kms_key_arn
  logs_kms_key_arn = module.security.logs_kms_key_arn

  enable_cache       = var.enable_cache
  enable_test_client = var.enable_test_client
}

# computo
module "compute" {
  source = "../../modules/compute"

  name                           = local.name_prefix
  vpc_id                         = module.network.vpc_id
  public_subnet_ids              = module.network.public_subnet_ids
  app_subnet_ids                 = module.network.app_subnet_ids
  data_clients_security_group_id = module.data.clients_security_group_id
  data_kms_key_arn               = module.security.data_kms_key_arn
  logs_kms_key_arn               = module.security.logs_kms_key_arn

  db_host          = module.data.db_endpoint
  db_port          = module.data.db_port
  db_name          = module.data.db_name
  db_secret_arn    = module.data.db_master_secret_arn
  cache_host       = module.data.cache_endpoint
  carts_table_name = module.data.carts_table_name
  carts_table_arn  = module.data.carts_table_arn

  certificate_arn      = module.edge.alb_certificate_arn
  origin_verify_header = module.edge.origin_verify_header
  origin_verify_value  = module.edge.origin_verify_value
  cognito_user_pool_id = module.edge.user_pool_id
  cognito_client_id    = module.edge.user_pool_client_id

  orders_table_name    = module.serverless.orders_table_name
  orders_table_arn     = module.serverless.orders_table_arn
  stock_table_name     = module.serverless.stock_table_name
  stock_table_arn      = module.serverless.stock_table_arn
  orders_topic_arn     = module.serverless.orders_topic_arn
  invoices_bucket_name = module.data.bucket_names["invoices"]
  invoices_bucket_arn  = module.data.bucket_arns["invoices"]

  enable_backup = var.enable_backup
}

# edge

module "edge" {
  source = "../../modules/edge"

  # Tenemos que poner el bloque providers porque este modulo trabaja con varias regiones, es decir, varias conexiones a regiones diferentes de aws
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name               = local.name_prefix
  domain_name        = var.domain_name
  shop_subdomain     = var.shop_subdomain
  alb_dns_name       = module.compute.alb_dns_name
  alb_zone_id        = module.compute.alb_zone_id
  frontend_dir       = "${path.root}/../../../app/frontend"
  auth_domain_prefix = "shopflow-${var.environment}-${data.aws_caller_identity.current.account_id}"
  enable_waf         = var.enable_waf
}

module "serverless" {
  source = "../../modules/serverless"

  name                 = local.name_prefix
  data_kms_key_arn     = module.security.data_kms_key_arn
  logs_kms_key_arn     = module.security.logs_kms_key_arn
  lambdas_dir          = "${path.root}/../../../app/lambdas"
  carts_stream_arn     = module.data.carts_stream_arn
  invoices_bucket_name = module.data.bucket_names["invoices"]
  invoices_bucket_arn  = module.data.bucket_arns["invoices"]
  notification_email   = var.notification_email
  metrics_namespace    = local.metrics_namespace
}

module "observability" {
  source = "../../modules/observability"

  name              = local.name_prefix
  metrics_namespace = local.metrics_namespace
  alarm_topic_arn   = module.serverless.notifications_topic_arn

  alb_arn_suffix          = module.compute.alb_arn_suffix
  target_group_arn_suffix = module.compute.target_group_arn_suffix
  ecs_cluster_name        = module.compute.cluster_name
  ecs_service_name        = module.compute.service_name

  db_instance_id = module.data.db_instance_id

  state_machine_arn      = module.serverless.state_machine_arn
  lambda_function_names  = module.serverless.lambda_function_names
  lambda_log_group_names = module.serverless.lambda_log_group_names
  dlq_names              = module.serverless.dlq_names
  partners_api_name      = module.serverless.partners_api_name
  partners_api_stage     = module.serverless.partners_api_stage

  distribution_id = module.edge.distribution_id
  web_acl_name    = module.edge.web_acl_name
}

module "cost" {
  source = "../../modules/cost"

  name                   = local.name_prefix
  project                = var.project
  environment            = var.environment
  notification_email     = var.notification_email
  notification_topic_arn = module.serverless.notifications_topic_arn
  data_kms_key_arn       = module.security.data_kms_key_arn
  monthly_budget_usd     = var.monthly_budget_usd
}
