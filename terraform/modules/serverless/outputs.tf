output "orders_table_name" {
  description = "Tabla DynamoDB de pedidos."
  value       = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  description = "ARN de la tabla de pedidos (para el permiso de la API)."
  value       = aws_dynamodb_table.orders.arn
}

output "stock_table_name" {
  description = "Tabla DynamoDB de stock."
  value       = aws_dynamodb_table.stock.name
}

output "stock_table_arn" {
  description = "ARN de la tabla de stock (para el permiso de la API)."
  value       = aws_dynamodb_table.stock.arn
}

output "orders_topic_arn" {
  description = "Tema SNS donde la API publica cada pedido nuevo."
  value       = aws_sns_topic.orders.arn
}

output "notifications_topic_arn" {
  description = "Tema SNS de avisos de la tienda (el que manda los emails)."
  value       = aws_sns_topic.notifications.arn
}

output "state_machine_arn" {
  description = "Step Functions del pedido."
  value       = aws_sfn_state_machine.order.arn
}

output "queues" {
  description = "Colas SQS del pedido y sus colas de errores."
  value = {
    for k, q in aws_sqs_queue.orders : k => {
      url = q.url
      dlq = aws_sqs_queue.dlq[k].url
    }
  }
}

output "abandoned_carts_dlq_url" {
  description = "Cola de errores de la Lambda de carritos abandonados."
  value       = aws_sqs_queue.abandoned_carts_dlq.url
}

output "partners_api_url" {
  description = "Dirección de la API de partners (stage v1)."
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "partners_api_key_id" {
  description = "ID de la API key de prueba (el valor se ve en la consola de API Gateway)."
  value       = aws_api_gateway_api_key.partner.id
}

output "partners_api_key" {
  description = "Valor de la API key de prueba."
  value       = aws_api_gateway_api_key.partner.value
  sensitive   = true
}

output "lambda_function_names" {
  description = "Nombres de las Lambdas."
  value       = { for k, f in aws_lambda_function.this : k => f.function_name }
}

output "dlq_names" {
  description = "Nombres de las tres colas de errores (para las alarmas)."
  value = merge(
    { for k, q in aws_sqs_queue.dlq : "orders_${k}" => q.name },
    { abandoned_carts = aws_sqs_queue.abandoned_carts_dlq.name },
  )
}

output "lambda_log_group_names" {
  description = "Log group de cada Lambda."
  value       = { for k, g in aws_cloudwatch_log_group.lambda : k => g.name }
}

output "state_machine_log_group_name" {
  description = "Log group del Step Functions del pedido."
  value       = aws_cloudwatch_log_group.order_workflow.name
}

output "partners_api_name" {
  description = "Nombre de la API de partners (sus métricas van por nombre y stage)."
  value       = aws_api_gateway_rest_api.partners.name
}

output "partners_api_stage" {
  description = "Stage de la API de partners."
  value       = aws_api_gateway_stage.v1.stage_name
}

output "partners_api_log_group_name" {
  description = "Log group con los accesos a la API de partners."
  value       = aws_cloudwatch_log_group.partners_api.name
}
