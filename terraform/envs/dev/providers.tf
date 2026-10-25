provider "aws" {
  region = var.region

  # Etiquetas en todos los recursos: permiten filtrar el coste por proyecto y entorno.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/alexxmrtin/Infraestructura-Cloud-AWS"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/alexxmrtin/Infraestructura-Cloud-AWS"
    }
  }
}
