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

variable "environment" {
  description = "Indicates the environment"
  default     = "dev"
}

variable "default_tags" {
  description = "Default tags to set to every resource"
  type        = map(string)
  default     = {
    Project     = "ecs-ec2-aws-warmup"
    ManagedBy   = "terraform"
    Environment = "dev"
  }
}


################################################################################
# Network Configuration
################################################################################
variable "vpc_name" {
  description = "The name of the VPC. Other names will result from this."
  default     = "ms-vpc"
}

variable "public_subnet_count" {
  type        = number
  description = "Public subnet count"
  default     = 2
}

variable "private_subnet_count" {
  type        = number
  description = "Private subnet count"
  default     = 2
}

variable "cidr_block" {
  description = "Network IP range"
  default     = "10.0.0.0/16"
}

################################################################################
# Database Configuration
################################################################################
# https://blog.gruntwork.io/a-comprehensive-guide-to-managing-secrets-in-your-terraform-code-1d586955ace1
# using environment variables
variable "users_database_username" {
  description = "The username for the users DB master"
  type        = string
  sensitive   = true
}

variable "users_database_name" {
  description = "The name for the users DB"
  type        = string
  default     = "postgres"
}

variable "users_database_password" {
  description = "The password for the users DB master"
  type        = string
  sensitive   = true
}

variable "posts_database_name" {
  description = "The name for the posts DB"
  type        = string
  default     = "postgres"
}

variable "posts_database_username" {
  description = "The password for the posts DB master"
  type        = string
  sensitive   = true
}

variable "posts_database_password" {
  description = "The password for the posts DB master"
  type        = string
  sensitive   = true
}

################################################################################
# Auth Configuration
################################################################################
variable "jwt_secret" {
  description = "The jwt secret we use to generate json web token"
  type        = string
  sensitive   = true
}

variable "basic_auth_username" {
  description = "The basic auth username"
  type        = string
  sensitive   = true
}

variable "basic_auth_password" {
  description = "The basic auth password"
  type        = string
  sensitive   = true
}
