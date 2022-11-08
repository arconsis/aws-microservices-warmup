provider "aws" {
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.aws_profile
  region                   = var.aws_region
  default_tags {
    tags = var.default_tags
  }
}

module "ecr" {
  for_each = var.repositories
  source = "../common/modules/ecr"
  ecr_name = each.key
}