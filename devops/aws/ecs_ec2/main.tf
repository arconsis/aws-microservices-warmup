provider "aws" {
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.aws_profile
  region                   = var.aws_region
#  default_tags {
#    tags = var.default_tags
#  }
}

module "networking" {
  source               = "../common/modules/network"
  region               = var.aws_region
  vpc_name             = var.vpc_name
  vpc_cidr             = var.cidr_block
  private_subnet_count = var.private_subnet_count
  public_subnet_count  = var.public_subnet_count
}

################################################################################
# IAM
################################################################################
# ECS task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = var.ecs_task_execution_role_name
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json
}

# ECS task execution role policy attachment
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################################################################
# VPC Flow Logs IAM
################################################################################
resource "aws_iam_role" "vpc_flow_cloudwatch_logs_role" {
  name               = "vpc-flow-cloudwatch-logs-role"
  assume_role_policy = file("../common/templates/policies/vpc_flow_cloudwatch_logs_role.json.tpl")
}

resource "aws_iam_role_policy" "vpc_flow_cloudwatch_logs_policy" {
  name   = "vpc-flow-cloudwatch-logs-policy"
  role   = aws_iam_role.vpc_flow_cloudwatch_logs_role.id
  policy = file("../common/templates/policies/vpc_flow_cloudwatch_logs_policy.json.tpl")
}

################################################################################
# ECS
################################################################################
resource "aws_iam_role" "ecs_instance_role" {
  name               = "ecs-instance-role-service"
  path               = "/"
  assume_role_policy = file("../common/templates/policies/ecs_instance_role.json.tpl")
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_service_role" {
  role = aws_iam_role.ecs_instance_role.name
}

module "alb_sg" {
  source            = "../common/modules/security"
  sg_name           = "load-balancer-security-group"
  description       = "controls access to the ALB"
  vpc_id            = module.networking.vpc_id
  egress_cidr_rules = {
    1 = {
      description      = "allow all outbound"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  egress_source_sg_rules = {}
  ingress_cidr_rules     = {
    1 = {
      description      = "controls access to the ALB"
      protocol         = "tcp"
      from_port        = 80
      to_port          = 80
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  ingress_source_sg_rules = {}
}

module "ecs_tasks_sg" {
  source            = "../common/modules/security"
  sg_name           = "ecs-tasks-security-group"
  description       = "controls access to the ECS tasks"
  vpc_id            = module.networking.vpc_id
  egress_cidr_rules = {
    1 = {
      description      = "allow all outbound"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  egress_source_sg_rules  = {}
  ingress_source_sg_rules = {
    1 = {
      description              = "allow inbound access from the ALB only"
      protocol                 = "-1"
      from_port                = 0
      to_port                  = 0
      source_security_group_id = module.alb_sg.security_group_id
    }
  }
  ingress_cidr_rules = {}
}

module "private_ecs_tasks_sg" {
  source            = "../common/modules/security"
  sg_name           = "ecs-private-tasks-security-group"
  description       = "controls access to the private ECS tasks (not internet facing)"
  vpc_id            = module.networking.vpc_id
  egress_cidr_rules = {
    1 = {
      description      = "allow all outbound"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  egress_source_sg_rules = {}
  ingress_cidr_rules     = {
    1 = {
      description      = "allow inbound access only from resources in VPC"
      protocol         = "tcp"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = [module.networking.vpc_cidr_block]
      ipv6_cidr_blocks = [module.networking.vpc_ipv6_cidr_block]
    }
  }
  ingress_source_sg_rules = {}
}

module "private_database_sg" {
  source            = "../common/modules/security"
  sg_name           = "private-database-security-group"
  description       = "Controls access to the private database (not internet facing)"
  vpc_id            = module.networking.vpc_id
  egress_cidr_rules = {
    1 = {
      description      = "allow all outbound"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }
  egress_source_sg_rules  = {}
  ingress_source_sg_rules = {
    1 = {
      description              = "allow inbound access only from task SG"
      protocol                 = "tcp"
      from_port                = 0
      #     We should create separate SGs for every db as they could have different ports. In this case all have PGs 5432
      to_port                  = module.books_database.db_instance_port
      source_security_group_id = module.ecs_tasks_sg.security_group_id
    }
    2 = {
      description              = "allow inbound access only from private task SG"
      protocol                 = "tcp"
      from_port                = 0
      #     We should create separate SGs for every db as they could have different ports. In this case all have PGs 5432
      to_port                  = module.books_database.db_instance_port
      source_security_group_id = module.private_ecs_tasks_sg.security_group_id
    }
  }
  ingress_cidr_rules = {}
}

module "public_alb" {
  source             = "../common/modules/alb"
  load_balancer_type = "application"
  alb_name           = "main-ecs-lb"
  internal           = false
  vpc_id             = module.networking.vpc_id
  security_groups    = [module.alb_sg.security_group_id]
  subnet_ids         = module.networking.public_subnet_ids
  http_tcp_listeners = [
    {
      port           = 80
      protocol       = "HTTP"
      action_type    = "fixed-response"
      fixed_response = {
        content_type = "text/plain"
        message_body = "Resource not found"
        status_code  = "404"
      }
    }
  ]
}

################################################################################
# Database Configuration
################################################################################
# Databases Secrets
# https://www.sufle.io/blog/keeping-secrets-as-secret-on-amazon-ecs-using-terraform
resource "aws_secretsmanager_secret" "books_database_password_secret" {
  name = "books_database_master_password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "books_database_password_secret_version" {
  secret_id               = aws_secretsmanager_secret.books_database_password_secret.id
  secret_string           = var.books_database_password
}

resource "aws_secretsmanager_secret" "books_database_username_secret" {
  name = "books_database_master_username"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "books_database_username_secret_version" {
  secret_id               = aws_secretsmanager_secret.books_database_username_secret.id
  secret_string           = var.books_database_username
}

resource "aws_secretsmanager_secret" "users_database_password_secret" {
  name = "users_database_master_password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "users_database_password_secret_version" {
  secret_id               = aws_secretsmanager_secret.users_database_password_secret.id
  secret_string           = var.users_database_password
}

resource "aws_secretsmanager_secret" "users_database_username_secret" {
  name = "users_database_master_username"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "users_database_username_secret_version" {
  secret_id               = aws_secretsmanager_secret.users_database_username_secret.id
  secret_string           = var.users_database_username
}

resource "aws_secretsmanager_secret" "recommendations_database_password_secret" {
  name = "recommendations_database_master_password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "recommendations_database_password_secret_version" {
  secret_id               = aws_secretsmanager_secret.recommendations_database_password_secret.id
  secret_string           = var.recommendations_database_password
}

resource "aws_secretsmanager_secret" "recommendations_database_username_secret" {
  name = "recommendations_database_master_username"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "recommendations_database_username_secret_version" {
  secret_id               = aws_secretsmanager_secret.recommendations_database_username_secret.id
  secret_string           = var.recommendations_database_username
}

resource "aws_iam_role_policy" "password_policy_secretsmanager" {
  name = "password-policy-secretsmanager"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "secretsmanager:GetSecretValue"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_secretsmanager_secret.books_database_username_secret.arn}",
          "${aws_secretsmanager_secret.books_database_password_secret.arn}",
          "${aws_secretsmanager_secret.users_database_username_secret.arn}",
          "${aws_secretsmanager_secret.users_database_password_secret.arn}",
          "${aws_secretsmanager_secret.recommendations_database_username_secret.arn}",
          "${aws_secretsmanager_secret.recommendations_database_password_secret.arn}"
        ]
      }
    ]
  }
  EOF
}

# Books Database
module "books_database" {
  source               = "../common/modules/database"
  database_identifier  = "books-database"
  database_name        = var.books_database_name
  database_username    = var.books_database_username
  database_password    = var.books_database_password
  subnet_ids           = module.networking.private_subnet_ids
  security_group_ids   = [module.private_database_sg.security_group_id]
  monitoring_role_name = "BooksDatabaseMonitoringRole"
}
# Recommendations Database
module "recommendations_database" {
  source               = "../common/modules/database"
  database_identifier  = "recommendations-database"
  database_name        = var.recommendations_database_name
  database_username    = var.recommendations_database_username
  database_password    = var.recommendations_database_password
  subnet_ids           = module.networking.private_subnet_ids
  security_group_ids   = [module.private_database_sg.security_group_id]
  monitoring_role_name = "RecommendationsDatabaseMonitoringRole"
}
# Users Database
module "users_database" {
  source               = "../common/modules/database"
  database_identifier  = "users-database"
  database_name        = var.users_database_name
  database_username    = var.users_database_username
  database_password    = var.users_database_password
  subnet_ids           = module.networking.private_subnet_ids
  security_group_ids   = [module.private_database_sg.security_group_id]
  monitoring_role_name = "UsersDatabaseMonitoringRole"
}

################################################################################
# ECS Tasks Execution IAM
################################################################################
# ECS task execution role data
data "aws_iam_policy_document" "ecs_task_execution_role" {
  version = "2012-10-17"
  statement {
    sid     = ""
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

module "ec2_autoscaling_group" {
  source                     = "../common/modules/ec2"
  lauch_template_name        = "ec2_ecs_launch_template"
  iam_ecs_service_role_name  = aws_iam_instance_profile.ecs_service_role.name
  security_groups_ids        = [module.ecs_tasks_sg.security_group_id]
  subnet_ids                 = module.networking.private_subnet_ids
  assign_public_ip           = false
  ecs_cluster_name           = module.ecs_cluster.cluster_name
  aws_autoscaling_group_name = "ec2-ecs-asg"
}

module "ecs_cluster" {
  source                    = "../common/modules/ecs_cluster"
  project                   = var.project
  create_capacity_provider  = true
  capacity_provider_name    = "capacity-provider-ecs-ec2"
  aws_autoscaling_group_arn = module.ec2_autoscaling_group.autoscaling_group_arn
}

resource "aws_service_discovery_private_dns_namespace" "segment" {
  name        = "discovery.com"
  description = "Service discovery for backends"
  vpc         = module.networking.vpc_id
}

################################################################################
# BOOKS API ECS Service
################################################################################
module "ecs_books_api_fargate" {
  source                                  = "../common/modules/ecs"
  aws_region                              = var.aws_region
  vpc_id                                  = module.networking.vpc_id
  cluster_id                              = module.ecs_cluster.cluster_id
  cluster_name                            = module.ecs_cluster.cluster_name
  enable_discovery                        = true
  dns_namespace_id                        = aws_service_discovery_private_dns_namespace.segment.id
  service_security_groups_ids             = [module.ecs_tasks_sg.security_group_id]
  subnet_ids                              = module.networking.private_subnet_ids
  assign_public_ip                        = false
  iam_role_ecs_task_execution_role        = aws_iam_role.ecs_task_execution_role
  iam_role_policy_ecs_task_execution_role = aws_iam_role_policy_attachment.ecs_task_execution_role
  logs_retention_in_days                  = 30
  fargate_cpu                             = var.ec2_cpu
  fargate_memory                          = var.ec2_memory
  health_check_grace_period_seconds       = var.health_check_grace_period_seconds

  task_compatibilities = ["EC2"]
  launch_type          = "EC2"
  enable_autoscaling   = false
  autoscaling_settings = null
  enable_alb           = true

  alb_listener = module.public_alb.alb_listener
  alb          = {
    listener = {
      tg_paths      = var.books_api_tg_paths
      tg            = var.books_api_tg
      port          = 80
      protocol      = "HTTP"
      target_type   = "ip"
      arn           = module.public_alb.alb_listener_http_tcp_arn
      rule_priority = 1
      rule_type     = "forward"
    }
  }
  service = {
    name          = var.books_api_name
    desired_count = var.books_api_desired_count
    max_count     = var.books_api_max_count
  }
  task_definition = {
    name              = var.books_api_name
    image             = var.books_api_image
    aws_logs_group    = var.books_api_aws_logs_group
    host_port         = var.books_api_port
    container_port    = var.books_api_port
    container_name    = var.books_api_name
    health_check_path = var.books_api_health_check_path
    family            = var.books_api_task_family
    network_mode      = var.books_api_network_mode
    env_vars          = [
      {
        "name" : "POSTGRES_HOST",
        "value" : tostring(module.books_database.db_instance_address),
      },
      {
        "name" : "POSTGRES_DB",
        "value" : tostring(module.books_database.db_instance_name),
      },
      {
        "name" : "POSTGRES_PORT",
        "value" : tostring(module.books_database.db_instance_port),
      }
    ]
    secret_vars = [
      {
        "name" : "POSTGRES_USER",
        "valueFrom" : aws_secretsmanager_secret.books_database_username_secret.arn,
      },
      {
        "name" : "POSTGRES_PASSWORD",
        "valueFrom" : aws_secretsmanager_secret.books_database_password_secret.arn,
      }
    ]
  }
}

################################################################################
# RECOMMENDATION API ECS Service
################################################################################
module "ecs_recommendations_api_fargate" {
  source                                  = "../common/modules/ecs"
  aws_region                              = var.aws_region
  vpc_id                                  = module.networking.vpc_id
  cluster_id                              = module.ecs_cluster.cluster_id
  cluster_name                            = module.ecs_cluster.cluster_name
  enable_discovery                        = true
  dns_namespace_id                        = aws_service_discovery_private_dns_namespace.segment.id
  service_security_groups_ids             = [module.ecs_tasks_sg.security_group_id]
  subnet_ids                              = module.networking.private_subnet_ids
  assign_public_ip                        = false
  iam_role_ecs_task_execution_role        = aws_iam_role.ecs_task_execution_role
  iam_role_policy_ecs_task_execution_role = aws_iam_role_policy_attachment.ecs_task_execution_role
  logs_retention_in_days                  = 30
  fargate_cpu                             = var.ec2_cpu
  fargate_memory                          = var.ec2_memory
  health_check_grace_period_seconds       = var.health_check_grace_period_seconds

  task_compatibilities = ["EC2"]
  launch_type          = "EC2"
  enable_autoscaling   = false
  autoscaling_settings = null
  enable_alb           = false

  alb_listener = null
  alb          = null
  service      = {
    name          = var.recommendations_api_name
    desired_count = var.recommendations_api_desired_count
    max_count     = var.recommendations_api_max_count
  }
  task_definition = {
    name              = var.recommendations_api_name
    image             = var.recommendations_api_image
    aws_logs_group    = var.recommendations_api_aws_logs_group
    host_port         = var.recommendations_api_port
    container_port    = var.recommendations_api_port
    container_name    = var.recommendations_api_name
    health_check_path = var.recommendations_api_health_check_path
    family            = var.recommendations_api_task_family
    network_mode      = "awsvpc"
    env_vars          = [
      {
        "name" : "POSTGRES_HOST",
        "value" : tostring(module.recommendations_database.db_instance_address),
      },
      {
        "name" : "POSTGRES_DB",
        "value" : tostring(module.recommendations_database.db_instance_name),
      },
      {
        "name" : "POSTGRES_PORT",
        "value" : tostring(module.recommendations_database.db_instance_port),
      }
    ]
    secret_vars = [
      {
        "name" : "POSTGRES_USER",
        "valueFrom" : aws_secretsmanager_secret.recommendations_database_username_secret.arn,
      },
      {
        "name" : "POSTGRES_PASSWORD",
        "valueFrom" : aws_secretsmanager_secret.recommendations_database_password_secret.arn,
      }
    ]
  }
}

################################################################################
# USERS API ECS Service
################################################################################
module "ecs_users_api_fargate" {
  source                                  = "../common/modules/ecs"
  aws_region                              = var.aws_region
  vpc_id                                  = module.networking.vpc_id
  cluster_id                              = module.ecs_cluster.cluster_id
  cluster_name                            = module.ecs_cluster.cluster_name
  enable_discovery                        = true
  dns_namespace_id                        = aws_service_discovery_private_dns_namespace.segment.id
  service_security_groups_ids             = [module.ecs_tasks_sg.security_group_id]
  subnet_ids                              = module.networking.private_subnet_ids
  assign_public_ip                        = false
  iam_role_ecs_task_execution_role        = aws_iam_role.ecs_task_execution_role
  iam_role_policy_ecs_task_execution_role = aws_iam_role_policy_attachment.ecs_task_execution_role
  logs_retention_in_days                  = 30
  fargate_cpu                             = var.ec2_cpu
  fargate_memory                          = var.ec2_memory
  health_check_grace_period_seconds       = var.health_check_grace_period_seconds

  task_compatibilities = ["EC2"]
  launch_type          = "EC2"
  enable_autoscaling   = false
  autoscaling_settings = null
  enable_alb           = true

  alb_listener = module.public_alb.alb_listener
  alb          = {
    listener = {
      tg_paths      = var.users_api_tg_paths
      tg            = var.users_api_tg
      port          = 80
      protocol      = "HTTP"
      target_type   = "ip"
      arn           = module.public_alb.alb_listener_http_tcp_arn
      rule_priority = 3
      rule_type     = "forward"
    }
  }
  service = {
    name          = var.users_api_name
    desired_count = var.users_api_desired_count
    max_count     = var.users_api_max_count
  }
  task_definition = {
    name              = var.users_api_name
    image             = var.users_api_image
    aws_logs_group    = var.users_api_aws_logs_group
    host_port         = var.users_api_port
    container_port    = var.users_api_port
    container_name    = var.users_api_name
    health_check_path = var.users_api_health_check_path
    family            = var.users_api_task_family
    network_mode      = "awsvpc"
    env_vars          = [
      {
        "name" : "POSTGRES_HOST",
        "value" : tostring(module.users_database.db_instance_address),
      },
      {
        "name" : "POSTGRES_DB",
        "value" : tostring(module.users_database.db_instance_name),
      },
      {
        "name" : "POSTGRES_PORT",
        "value" : tostring(module.users_database.db_instance_port),
      }
    ]
    secret_vars = [
      {
        "name" : "POSTGRES_USER",
        "valueFrom" : aws_secretsmanager_secret.users_database_username_secret.arn,
      },
      {
        "name" : "POSTGRES_PASSWORD",
        "valueFrom" : aws_secretsmanager_secret.users_database_password_secret.arn,
      }
    ]
  }
}
