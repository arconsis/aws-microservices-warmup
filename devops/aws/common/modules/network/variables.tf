# region
variable "region" {
  description = "The region to use for this module."
  default     = "us-west-2"
}

################################################################################
# Project metadata
################################################################################

variable "vpc_name" {
  description = "The name of the VPC. Other names will result from this."
  default     = "ms-vpc"
}

# network resources
variable "enable_dns_support" {
  default     = true
  description = " (Optional) A boolean flag to enable/disable DNS support in the VPC"
}

variable "enable_dns_hostnames" {
  default     = true
  description = " (Optional) A boolean flag to enable/disable DNS hostnames in the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "Cidr block for vpc"
}

variable "public_subnet_count" {
  type        = number
  description = "Public subnet count"
}

variable "private_subnet_count" {
  type        = number
  description = "Private subnet count"
}

variable "public_subnet_additional_tags" {
  default     = {}
  description = "Additional resource tags"
  type        = map(string)
}

variable "private_subnet_additional_tags" {
  default     = {}
  description = "Additional resource tags"
  type        = map(string)
}