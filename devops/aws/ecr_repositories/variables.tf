################################################################################
# General AWS Configuration
################################################################################
variable "aws_region" {
  description = "The AWS region things are created in"
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "The AWS profile name"
  default     = "arconsis"
}

variable "default_tags" {
  description = "Default tags to set to every resource"
  type        = map(string)
  default     = {
    Project   = "ecs-fargate-aws-warmup"
    ManagedBy = "terraform"
  }
}

variable "repositories" {
  description = "Defines the repositories to create"
  type        = set(string)
  default     = [
    "books",
    "users",
    "recommendations",
    "promotions"
  ]
}