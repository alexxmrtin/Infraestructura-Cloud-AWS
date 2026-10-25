output "account_id" {
  description = "Cuenta de AWS donde se despliega."
  value       = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  description = "Identidad que ejecuta Terraform (en CI, el rol asumido por OIDC)."
  value       = data.aws_caller_identity.current.arn
}

output "region" {
  description = "Región efectiva del provider."
  value       = data.aws_region.current.region
}

output "name_prefix" {
  description = "Prefijo de nombres de este entorno."
  value       = local.name_prefix
}

# --- Network ---

output "vpc_id" {
  description = "ID de la VPC."
  value       = module.network.vpc_id
}

output "subnets" {
  description = "IDs de subredes por capa."
  value = {
    public = module.network.public_subnet_ids
    app    = module.network.app_subnet_ids
    data   = module.network.data_subnet_ids
  }
}

output "nat_instance_id" {
  description = "Instancia NAT (si nat_mode = instance)."
  value       = module.network.nat_instance_id
}


#Security

output "flow_logs_bucket" {
  description = "Bucket de los VPC Flow Logs."
  value       = module.network.flow_logs_bucket
}

output "kms_keys" {
  description = "Alias de las claves KMS propias."
  value = {
    logs = module.security.logs_kms_key_alias
    data = module.security.data_kms_key_alias
  }
}

output "cloudtrail_bucket" {
  description = "Bucket donde CloudTrail guarda los registros."
  value       = module.security.cloudtrail_bucket
}

output "guardduty_detector_id" {
  description = "Detector de GuardDuty (null si está desactivado)."
  value       = module.security.guardduty_detector_id
}

output "database" {
  description = "Cómo llegar a RDS PostgreSQL."
  value = {
    endpoint   = module.data.db_endpoint
    port       = module.data.db_port
    name       = module.data.db_name
    secret_arn = module.data.db_master_secret_arn
  }
}

output "cache_endpoint" {
  description = "Dirección de Valkey (con TLS)."
  value       = module.data.cache_endpoint
}

output "carts_table" {
  description = "Tabla DynamoDB de carritos."
  value       = module.data.carts_table_name
}

output "buckets" {
  description = "Buckets de la tienda."
  value       = module.data.bucket_names
}

output "test_client_instance_id" {
  description = "Instancia de pruebas. Para entrar: aws ssm start-session --target <id>."
  value       = module.data.test_client_instance_id
}

output "shop_url" {
  description = "Dirección de la tienda. La API está en <shop_url>/api/products."
  value       = module.edge.shop_url
}

output "login_url" {
  description = "Página de login de Cognito."
  value       = module.edge.login_url
}

output "cognito" {
  description = "User pool y cliente de la web en Cognito."
  value = {
    user_pool_id = module.edge.user_pool_id
    client_id    = module.edge.user_pool_client_id
  }
}

output "cloudfront_distribution_id" {
  description = "Distribución de CloudFront."
  value       = module.edge.distribution_id
}

output "frontend_bucket" {
  description = "Bucket con la web estática."
  value       = module.edge.frontend_bucket
}

output "ecr_repository_url" {
  description = "Repositorio ECR donde el workflow sube la imagen de la API."
  value       = module.compute.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "Cluster de ECS."
  value       = module.compute.cluster_name
}

output "ecs_service_name" {
  description = "Servicio de ECS de la API."
  value       = module.compute.service_name
}

output "api_log_group" {
  description = "Logs de la API en CloudWatch."
  value       = module.compute.api_log_group
}

output "order_workflow" {
  description = "Step Functions del pedido (consola: Step Functions > State machines)."
  value       = module.serverless.state_machine_arn
}

output "orders_table" {
  description = "Tabla DynamoDB de pedidos."
  value       = module.serverless.orders_table_name
}

output "order_queues" {
  description = "Colas SQS del pedido y sus colas de errores."
  value       = module.serverless.queues
}

output "partners_api_url" {
  description = "API de partners. Ejemplo: curl -H 'x-api-key: <key>' <url>/stock"
  value       = module.serverless.partners_api_url
}

output "partners_api_key_id" {
  description = "ID de la API key de prueba (el valor: API Gateway > API keys > Show, o terraform output -raw partners_api_key)."
  value       = module.serverless.partners_api_key_id
}

output "partners_api_key" {
  description = "Valor de la API key de prueba."
  value       = module.serverless.partners_api_key
  sensitive   = true
}

output "lambda_functions" {
  description = "Nombres de las Lambdas."
  value       = module.serverless.lambda_function_names
}

output "dashboard_url" {
  description = "Dashboard de CloudWatch con el flujo de pedidos, la web, la API y las alarmas."
  value       = module.observability.dashboard_url
}

output "alarms" {
  description = "Alarmas que avisan por email al tema de avisos."
  value       = module.observability.alarm_names
}

output "edge_log_groups" {
  description = "Logs de CloudFront y del WAF (están en us-east-1)."
  value = {
    cloudfront = module.edge.cloudfront_log_group_name
    waf        = module.edge.waf_log_group_name
  }
}

output "cost_alerts" {
  description = "Presupuesto, monitor de anomalías y recordatorio de apagado del entorno."
  value = {
    budget          = module.cost.budget_name
    anomaly_monitor = module.cost.anomaly_monitor_arn
    reminder        = module.cost.reminder_schedule_name
  }
}
