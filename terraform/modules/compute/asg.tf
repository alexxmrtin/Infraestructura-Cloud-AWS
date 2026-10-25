# Este archivo crea las instancias EC2 en las cuales van a ejecutarse las tareas, como la api de la web. Tiene tres bloques, la AMI para las instancias EC2, el launch template y el grupo de autoescaling.

# La AMI es basicamente las configuraciones basicas de una EC2. La launch template es la configuracion completa de una instancia EC2 (el tipo de instancia, security group,rol IAM,tamaño en disco...) y por ultimo el grupo de Auto Scaling que sirve simplemente para escalar  el uso de las instancias EC2 segun la demanda de potencia computacional que haya en un momento dado.


# Cogemos de aws la ami concreta que queremos para las instancias
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# Aqui ya tenemos la configuracion completa para las instancias
resource "aws_launch_template" "ecs" {
  name                   = "${var.name}-ecs"
  image_id               = data.aws_ssm_parameter.ecs_ami.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.instances.id]
  ebs_optimized          = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<CONFIG
    ECS_CLUSTER=${aws_ecs_cluster.this.name}
    ECS_AWSVPC_BLOCK_IMDS=true
    ECS_ENABLE_CONTAINER_METADATA=true
    CONFIG
  EOF
  )

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = false
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      kms_key_id            = var.data_kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-ecs" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name}-ecs", Backup = local.backup_tag_value }
  }

  tags = { Name = "${var.name}-ecs" }

  lifecycle {
    ignore_changes = [image_id]
  }
}

# Grupo de Autoscaling, minimo 1 maximo 3 ahora mismo segun las tareas que se ejecuten dentro de la/las instancias
resource "aws_autoscaling_group" "ecs" {
  name                  = "${var.name}-ecs"
  vpc_zone_identifier   = var.app_subnet_ids
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  health_check_type     = "EC2"
  protect_from_scale_in = false
  force_delete          = var.force_destroy

  launch_template {
    id      = aws_launch_template.ecs.id
    version = aws_launch_template.ecs.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-ecs"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
