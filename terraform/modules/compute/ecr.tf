# ECR es el almacen privado de imagenes docker en AWS. Github actions sube ahi la imagen de la API y las instancias EC2 descargan de ahi siempre que se quiera arrancar los contenedores

#El repositorio donde se guardan las imagenes de las tareas (en este caso la API)
resource "aws_ecr_repository" "api" {
  # checkov:skip=CKV_AWS_51:La etiqueta latest se vuelve a subir en cada apply; cada imagen lleva además la etiqueta del commit.
  # checkov:skip=CKV_AWS_136:La imagen no guarda datos ni secretos; cifrado AES-256 de AWS para no dar permisos KMS a quien la descarga.
  name                 = local.api_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_destroy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = local.api_name }
}

# UN lifycicle para limpieza automatica
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Guardar solo las ultimas ${var.ecr_keep_images} imagenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_keep_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
