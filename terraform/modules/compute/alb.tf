# Este archivo configura el load balancer del proyecto.Tiene tres partes ,

# "aws_lb" es el balanceador en si (el servicio en aws), 

# "aws_lb_target_group" configura el conjunto de destinos en los que va a repartir y reenviar las peticiones

# "aws_lb_listener" es la configuracion que le dice a aws por donde escucha este servicio, que es el puerto 80


resource "aws_lb" "api" {
  # checkov:skip=CKV_AWS_91:Sin logs de acceso en dev (otro bucket y más coste); llegan con la observabilidad en la fase 7.
  # checkov:skip=CKV_AWS_150:Sin protección contra borrado en dev: el entorno se destruye en cada sesión.
  # checkov:skip=CKV2_AWS_28:El WAF está delante de CloudFront y el ALB solo admite a CloudFront con la cabecera secreta.
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "api" {
  # checkov:skip=CKV_AWS_378:Del ALB a las tareas va por HTTP dentro de la VPC; hasta el ALB todo va por HTTPS.
  name                 = "${var.name}-api"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name}-api" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Acceso denegado"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = var.origin_verify_header
      values           = [var.origin_verify_value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
