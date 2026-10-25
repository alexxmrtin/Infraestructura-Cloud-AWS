#Este archivo es el centro del modulo, se crea el cluster,lo une con ASG y se define lo que se ejecuta y como se ejecuta.

#Tiene 6 bloques


# 1.Bloque, el cluster. Este cluster actua como agrupacion logica de ECS donde se registran las instancias y se ejecutan las tareas en dichas instancias.
resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = local.cluster_name }
}

# 2.Bloque , la conexion con el ASG. Basicamente le decimos a ECS como son las instancias (con su AMI, launch template...) y como esta configurado autoescaling para que sepa el maximo y minimo de instancias que se pueden pedir.
resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.name}-ec2"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"
    managed_draining               = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
    }
  }

  tags = { Name = "${var.name}-ec2" }
}

# 3.Bloque , el capacity provider que creamos en el bloque anterior se conecta aqui al cluster creado en el bloque 1. Basicamente le dice al cluster que puede usar el capacity provider.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 0
  }
}


# 4.Bloque, donde van los logs de las instancias y tareas
resource "aws_cloudwatch_log_group" "api" {
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.log_retention_days días (7), no un año, por coste.
  name              = "/ecs/${local.api_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = { Name = "${local.api_name}-logs" }
}


# 5.Bloque, Le decimos a ECS como arrancar una tarea 
resource "aws_ecs_task_definition" "api" {
  family                   = local.api_name
  requires_compatibilities = ["EC2"]                    #Va en instancias EC2, no en Fargate
  network_mode             = "awsvpc"                   #Cada tarea tiene su propia IP y sus security groups
  cpu                      = var.api_cpu                #256 = un cuarto de vCPU
  memory                   = var.api_memory             #512 MB
  execution_role_arn       = aws_iam_role.execution.arn #Rol de ECS para preparar la tarea: imagen, logs y contraseña
  task_role_arn            = aws_iam_role.task.arn      #Rol de la API mientras funciona: DynamoDB

  runtime_platform { #Linux en ARM, igual que la imagen y las instancias
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name                   = "api"
      image                  = "${aws_ecr_repository.api.repository_url}:${var.api_image_tag}" #Imagen de ECR con la etiqueta latest
      essential              = true
      readonlyRootFilesystem = true    #Disco del contenedor de solo lectura
      user                   = "10001" #Usuario sin permisos del Dockerfile

      portMappings = [ #Escucha en el 8000
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [ #Donde esta cada cosa. Si no hay cache, CACHE_HOST va vacio
        { name = "AWS_REGION", value = local.region },
        { name = "AWS_DEFAULT_REGION", value = local.region },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "CACHE_HOST", value = var.cache_host == null ? "" : var.cache_host },
        { name = "CARTS_TABLE", value = var.carts_table_name },
        { name = "COGNITO_USER_POOL_ID", value = var.cognito_user_pool_id },
        { name = "COGNITO_CLIENT_ID", value = var.cognito_client_id },
        { name = "ORDERS_TABLE", value = var.orders_table_name },
        { name = "STOCK_TABLE", value = var.stock_table_name },
        { name = "ORDERS_TOPIC_ARN", value = var.orders_topic_arn },
        { name = "INVOICES_BUCKET", value = var.invoices_bucket_name },
      ]

      secrets = [ #Usuario y contraseña de RDS desde Secrets Manager al arrancar
        { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      ]

      logConfiguration = { #Envia la salida al log group del bloque 4
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = local.region
          awslogs-stream-prefix = "api"
        }
      }
    }
  ])

  tags = { Name = local.api_name }
}


#6.Bloque, este ultimo bloque ejecuta el servicio usando el task definition del bloque 5. Esto ejecuta un servicio que a su vez, ejecuta tantas tareas hasta llegar al numero de tareas deseado, las vigila, las conecta al ALB y les da conexion a la red de la VPC.
resource "aws_ecs_service" "api" {
  name                              = local.api_name
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.api_desired_count
  health_check_grace_period_seconds = 60
  propagate_tags                    = "SERVICE"
  enable_ecs_managed_tags           = true
  force_delete                      = var.force_destroy

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.api.id, var.data_clients_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = { Name = local.api_name }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this, aws_lb_listener_rule.from_cloudfront]
}
