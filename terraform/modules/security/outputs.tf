output "logs_kms_key_arn" {
  description = "ARN de la clave KMS de registros (CloudTrail, Flow Logs, CloudWatch Logs)."
  value       = aws_kms_key.logs.arn
}

output "logs_kms_key_alias" {
  description = "Alias de la clave de registros."
  value       = aws_kms_alias.logs.name
}

output "data_kms_key_arn" {
  description = "ARN de la clave KMS de datos de la aplicación."
  value       = aws_kms_key.data.arn
}

output "data_kms_key_alias" {
  description = "Alias de la clave de datos."
  value       = aws_kms_alias.data.name
}

output "cloudtrail_arn" {
  description = "ARN del trail."
  value       = aws_cloudtrail.this.arn
}

output "cloudtrail_bucket" {
  description = "Bucket donde CloudTrail guarda los registros."
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "guardduty_detector_id" {
  description = "ID del detector de GuardDuty (null si está desactivado)."
  value       = try(aws_guardduty_detector.this[0].id, null)
}
