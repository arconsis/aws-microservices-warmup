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
# EKS Configuration
################################################################################
variable "cluster_name" {
  description = "Kubernetes Cluster Name"
  default     = "test-eks-cluster"
}

################################################################################
# Project metadata
################################################################################
variable "environment" {
  description = "Indicate the environment"
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
# Database Configuration
################################################################################
# Books DB

variable "books_database_name" {
  description = "The name for the books DB"
  type        = string
  default     = "postgres"
}

variable "books_database_username" {
  description = "The username for the books DB master"
  type        = string
  sensitive   = true
}

variable "books_database_password" {
  description = "The password for the books DB master"
  type        = string
  sensitive   = true
}

# Recommendations DB

variable "recommendations_database_name" {
  description = "The name for the recommendations DB"
  type        = string
  default     = "postgres"
}

variable "recommendations_database_username" {
  description = "The username for the recommendations DB master"
  type        = string
  sensitive   = true
}

variable "recommendations_database_password" {
  description = "The password for the recommendations DB master"
  type        = string
  sensitive   = true
}

# Users DB

variable "users_database_name" {
  description = "The name for the users DB"
  type        = string
  default     = "postgres"
}

variable "users_database_username" {
  description = "The username for the users DB master"
  type        = string
  sensitive   = true
}

variable "users_database_password" {
  description = "The password for the users DB master"
  type        = string
  sensitive   = true
}