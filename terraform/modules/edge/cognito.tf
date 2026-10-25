# Amazon Cognito es el servicio de AWS que gestiona los usuarios de la web. registro, login, contraseñas, MFA y login con Google o Facebook. Entrega a cada usuario un token firmado con el que tu API sabe quién es, sin que tengas que programar ni guardar nada de eso

# Esto es basicamente la base de datos de los usuarios donde guardamos los usuarios y contraseñas. Importante entender que AWS gestiona las contraseñas, y usando este servicio, autentica a los usuarios y les da un token que usa para conectarse a la API. Destacar que cognito ya implementa funcionalidades como MFA,recuperacion de contraseñas... Estas cosas se configuran en este bloque.
resource "aws_cognito_user_pool" "this" {
  name                     = "${var.name}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "INACTIVE"
  mfa_configuration        = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 10
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Tu codigo de ShopFlow"
    email_message        = "Tu codigo de verificacion es {####}"
  }

  tags = { Name = "${var.name}-users" }
}

# Esto es el dominio de login que te da cognito. 
resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.auth_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# Esto una interfaz web de login con un dominio diferente al que usamos, lo suyo es hacerlo nosotros en la API pero como este proyecto es para aprender cosas relacionadas con aws, uso cognito. Basicamente esta interfaz o cliente lo usamos para poder usar la user_pool de cognito

# Una vez un usuario se autentica, te redirige a la url de la web que hemos creado reenviando un codigo de un solo uso como query-string. Una vez ahi, el archivo del frontend app.js llama a cognito y cambia ese codigo por un token que almacena en local storage y que vamos a usar para conectarnos a la API. Ese token es un JWT con informacion del usuario para que la API sepa a quien pertenece, y ademas cognito firma el token con una clave privada que solo tiene el servicio para que la API conpruebe que el token es veridico.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["${local.shop_url}/"]
  logout_urls                          = ["${local.shop_url}/"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 7

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
