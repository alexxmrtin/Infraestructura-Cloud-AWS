output "budget_name" {
  description = "Presupuesto del entorno (null si no hay email)."
  value       = one(aws_budgets_budget.environment[*].name)
}

output "anomaly_monitor_arn" {
  description = "Monitor de Cost Anomaly Detection del entorno (null si no hay email)."
  value       = one(aws_ce_anomaly_monitor.environment[*].arn)
}

output "reminder_schedule_name" {
  description = "Recordatorio nocturno de apagado (null si está desactivado)."
  value       = one(aws_scheduler_schedule.still_on[*].name)
}
