# No confundir con lo que se hace en asg.tf , aqui se usa un servicio de aws llamado application auto scaling que se usa para escalar tareas dentro de instancias o servicios de aws.

# Hay tres bloques 

# 1. bloque, se configura que tareas se escalan y se configura los limites de dicho escalado (min y max capacity)
resource "aws_appautoscaling_target" "api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.api_min_count
  max_capacity       = var.api_max_count
}

# 2. 2 bloque , es una regla que escala segun la capacidad de cpu que se fije. Se fija un cpu target, y este añade o quita tareas para acercarse a ese objetivo
resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${local.api_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.api_cpu_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 120

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# 3. 3 bloque, otra regla como la anterior, en vez de cpu medimos las peticiones que recibe cada tarea. HE configurado esto para que cada tarea tenga 120 peticiones por minuto como maximo
resource "aws_appautoscaling_policy" "api_requests" {
  name               = "${local.api_name}-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api.service_namespace
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.api_requests_per_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 120

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.api.arn_suffix}/${aws_lb_target_group.api.arn_suffix}"
    }
  }
}
