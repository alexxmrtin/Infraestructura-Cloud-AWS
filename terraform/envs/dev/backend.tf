# El bucket se pasa al hacer init (lo crea el stack de bootstrap):
#   local: terraform init -backend-config=backend.hcl
#   CI:    terraform init -backend-config="bucket=$TF_STATE_BUCKET"
terraform {
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
