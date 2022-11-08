terraform {
  # Optional attributes and the defaults function are
  # both experimental, so we must opt in to the experiment.
  experiments = [module_variable_optional_attrs]
}

# region
variable "aws_region" {
  description = "The region to use for this module."
}

variable "vpc_id" {
  description = "The VPC id"
  type        = string
}

################################################################################
# Project metadata
################################################################################
variable "cluster_id" {
  description = "The ECS cluster ID where the service should run"
  type        = string
}

variable "cluster_name" {
  description = "The ECS cluster name where the service should run"
  type        = string
}

variable "enable_discovery" {
  description = "Flag to switch on service discovery. If true, a valid DNS namespace must be provided"
  type        = bool
  default     = true
}

variable "dns_namespace_id" {
  description = "The Route53 DNS namespace ID where the ECS task is registered"
  type        = string
}

variable "discovery_ttl" {
  description = "Time to live"
  default     = 10
}

variable "discovery_routing_policy" {
  description = "Defines routing policy"
  default     = "MULTIVALUE"
}

variable "task_compatibilities" {
  type        = list(any)
  description = "Defines ecs task compatibility"
}

################################################################################
# ECS Configuration
################################################################################
variable "fargate_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)"
}

variable "fargate_memory" {
  description = "Fargate instance memory to provision (in MiB)"
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks on newly instantiated tasks to prevent premature shutdown. Only valid for services configured to use load balancers."
  default     = 180
}

################################################################################
# API Books Service Configuration
################################################################################
variable "logs_retention_in_days" {
  description = "Defines service logs retention period"
}

variable "task_definition" {
  description = "ECS task definition"
  type        = object({
    name              = string
    image             = string
    aws_logs_group    = string
    host_port         = number
    container_port    = number
    container_name    = string
    family            = string
    env_vars          = list(any)
    secret_vars       = list(any)
    health_check_path = string
    network_mode      = string
  })
}

variable "service" {
  description = "ECS service"
  type        = object({
    name          = string
    desired_count = number
    max_count     = number
  })
}

variable "service_security_groups_ids" {
  description = "IDs of SG on a ecs task network"
}

variable "launch_type" {
  description = "Defines ecs launch type"
}

variable "subnet_ids" {
  description = "The VPC subnets IDs where the application should run"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Define we attach public ip to task"
}

variable "iam_role_ecs_task_execution_role" {
  description = "ARN of the IAM role that allows Amazon ECS to make calls to your load balancer on your behalf."
}

variable "iam_role_policy_ecs_task_execution_role" {
  description = "Policy of the IAM role that allows Amazon ECS to make calls to your load balancer on your behalf."
}

variable "enable_alb" {
  description = "Whether the service should be registered to an application load balancer"
  type        = bool
}

variable "alb_listener" {
  description = "Defines ALB listener where the service is registered"
}

variable "alb" {
  type = object({
    listener = object({
      tg            = string
      port          = number
      protocol      = string
      target_type   = string
      arn           = string
      rule_priority = string
      rule_type     = string
      tg_paths      = list(string)
    })
  })
}

variable "enable_autoscaling" {
  description = "Flag to define if we need auto scaling."
  type        = bool
}

variable "autoscaling_settings" {
  type = object({
    autoscaling_name    = string
    max_capacity        = number
    min_capacity        = number
    target_cpu_value    = optional(number)
    target_memory_value = optional(number)
    scale_in_cooldown   = number
    scale_out_cooldown  = number
  })
  default     = null
  description = "Settings of based Auto Scaling."
}

variable "has_ordered_placement" {
  description = "Flag to define if ordered placement strategy should be set."
  type        = bool
  default     = false
}
