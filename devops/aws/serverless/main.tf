// TODO: Rework this when https://github.com/terraform-aws-modules/terraform-aws-s3-bucket/pull/139 is merged

################################################################################
################################################################################
################################################################################
# PROVIDER CONFIGURATION
################################################################################
################################################################################
################################################################################
provider "aws" {
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.aws_profile
  region                   = var.aws_region
#    default_tags {
#      tags = var.default_tags
#    }
}

################################################################################
################################################################################
################################################################################
# VPC CONFIGURATION
################################################################################
################################################################################
################################################################################
module "networking" {
  source               = "../common/modules/network"
  region               = var.aws_region
  vpc_name             = var.vpc_name
  vpc_cidr             = var.cidr_block
  private_subnet_count = var.private_subnet_count
  public_subnet_count  = var.public_subnet_count
}

################################################################################
################################################################################
################################################################################
# SG CONFIGURATION
################################################################################
################################################################################
################################################################################

module "private_vpc_sg" {
  source            = "../common/modules/security"
  sg_name           = "private-lambda-security-group"
  description       = "Controls access to the private lambdas (not internet facing)"
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
  ingress_source_sg_rules = {}
  ingress_cidr_rules      = {
    1 = {
      description      = "allow inbound access only from resources in VPC"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = [module.networking.vpc_cidr_block]
      ipv6_cidr_blocks = [module.networking.vpc_ipv6_cidr_block]
    }
  }
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
  ingress_source_sg_rules = {}
  ingress_cidr_rules      = {
    1 = {
      description      = "allow inbound access only from resources in VPC"
      protocol         = "tcp"
      from_port        = 0
      to_port          = module.users_database.db_instance_port
      cidr_blocks      = [module.networking.vpc_cidr_block]
      ipv6_cidr_blocks = [module.networking.vpc_ipv6_cidr_block]
    }
  }
}

################################################################################
################################################################################
################################################################################
# S3 BUCKETS CONFIGURATION
################################################################################
################################################################################
################################################################################
module "users_profile_images_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "2.15.0"
  bucket        = "users-profile-images-tf"
  acl           = "private"
  force_destroy = true
}

module "users_thumbnails_images_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "2.15.0"
  bucket        = "users-thumbnails-images-tf"
  acl           = "private"
  force_destroy = true
}

################################################################################
################################################################################
################################################################################
# SNS CONFIGURATION
################################################################################
################################################################################
################################################################################
resource "aws_sns_topic" "new_user_added_topic" {
  name = "new-user-added-topic"
}

################################################################################
################################################################################
################################################################################
# SQS QUEUE CONFIGURATION
################################################################################
################################################################################
################################################################################

# Users Profile Image Queue
resource "aws_sqs_queue" "users_profile_images_queue" {
  name           = "users-profile-images"
  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.users_profile_images_dlq.arn}\",\"maxReceiveCount\":5}"
}

resource "aws_sqs_queue_policy" "users_profile_images_queue_policy" {
  queue_url = aws_sqs_queue.users_profile_images_queue.id
  # SQS Policy to specify which service can send messages to this queue
  policy    = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:*:*:users-profile-images",
      "Condition": {
        "ArnEquals": { "aws:SourceArn": "${module.users_profile_images_bucket.s3_bucket_arn}" }
      }
    }
  ]
}
POLICY
}

# users-demo-posts DLQ
resource "aws_sqs_queue" "users_profile_images_dlq" {
  name = "users-profile-images-dlq"
}

# User Demo Posts Queue
resource "aws_sqs_queue" "users_demo_post_queue" {
  name           = "users-demo-posts"
  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.users_demo_post_dlq.arn}\",\"maxReceiveCount\":5}"
}

resource "aws_sqs_queue_policy" "users_demo_post_queue_policy" {
  queue_url = aws_sqs_queue.users_demo_post_queue.id
  # SQS Policy that is needed for our SQS to actually receive events from the SNS topic
  policy    = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.users_demo_post_queue.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.new_user_added_topic.arn}"
        }
      }
    }
  ]
}
POLICY
}

# User Demo Posts DLQ
resource "aws_sqs_queue" "users_demo_post_dlq" {
  name = "users-demo-posts-dlq"
}

################################################################################
################################################################################
# SNS - SQS SUBSCRIPTION
################################################################################
################################################################################
################################################################################
# subscription, which will allow our SQS queue to receive notifications from the SNS topic we created above
resource "aws_sns_topic_subscription" "users_demo_post_queue_target" {
  topic_arn = aws_sns_topic.new_user_added_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.users_demo_post_queue.arn
}

################################################################################
################################################################################
################################################################################
# S3 - SQS NOTIFICATIONS
################################################################################
################################################################################
################################################################################
resource "aws_s3_bucket_notification" "users_profile_images_notification" {
  bucket = module.users_profile_images_bucket.s3_bucket_id

  queue {
    queue_arn = aws_sqs_queue.users_profile_images_queue.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue.users_profile_images_queue]
}

################################################################################
################################################################################
################################################################################
# DATABASES CONFIGURATION
################################################################################
################################################################################
################################################################################
# Users Database
module "users_database" {
  source               = "../common/modules/database"
  database_identifier  = "users-database"
  database_username    = var.users_database_username
  database_password    = var.users_database_password
  subnet_ids           = module.networking.private_subnet_ids
  security_group_ids   = [module.private_database_sg.security_group_id]
  monitoring_role_name = "UsersDatabaseMonitoringRole"
  database_name        = ""
}
# Posts Database
module "posts_database" {
  source               = "../common/modules/database"
  database_identifier  = "posts-database"
  database_username    = var.posts_database_username
  database_password    = var.posts_database_password
  subnet_ids           = module.networking.private_subnet_ids
  security_group_ids   = [module.private_database_sg.security_group_id]
  monitoring_role_name = "PostsDatabaseMonitoringRole"
  database_name        = ""
}

################################################################################
################################################################################
################################################################################
# LAMBDAS LAYERS CONFIGURATION
################################################################################
################################################################################
################################################################################
module "lambda_layer_logging" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"
  create_layer = true

  layer_name          = "lambda-layer-logging"
  description         = "Help on lambda logging"
  compatible_runtimes = ["nodejs14.x"]

  source_path = "../../../backend/serverless/layers/logging"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"
}

module "lambda_layer_users_database" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  create_layer = true

  layer_name          = "lambda-layer-users-database"
  description         = "Handle lambdas database integration"
  compatible_runtimes = ["nodejs14.x"]

  source_path = "../../../backend/serverless/layers/usersDatabase"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"
}

module "lambda_layer_posts_database" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  create_layer = true

  layer_name          = "lambda-layer-post-database"
  description         = "Handle lambdas post database integration"
  compatible_runtimes = ["nodejs14.x"]

  source_path = "../../../backend/serverless/layers/postsDatabase"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"
}

################################################################################
################################################################################
################################################################################
# LAMBDAS CONFIGURATION
################################################################################
################################################################################
################################################################################
################################################################################
# AUTH
################################################################################
module "jwt_auth" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "jwt_auth"
  description   = "Verifies JWT"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true

  source_path = "../../../backend/serverless/lambdas/auth/verifyToken"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn
  ]

  environment_variables = {
    JWT_SECRET = var.jwt_secret
  }
}

module "basic_auth" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "basic_auth"
  description   = "Verifies basic authentication"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true

  source_path = "../../../backend/serverless/lambdas/auth/verifyBasicAuth"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn
  ]

  environment_variables = {
    BASIC_AUTH_USERNAME = var.basic_auth_username
    BASIC_AUTH_PASSWORD = var.basic_auth_password
  }
}

module "login" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "login"
  description   = "Handles token generation"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/auth/login"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  environment_variables = {
    DB_HOST    = module.users_database.db_instance_address,
    DB_PORT    = module.users_database.db_instance_port,
    DB_NAME    = var.users_database_name,
    DB_USER    = module.users_database.db_instance_username,
    DB_PASS    = module.users_database.db_instance_password,
    JWT_SECRET = var.jwt_secret
  }
}
################################################################################
# HELPER Lambdas
################################################################################
module "run_db_migrations" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "run-db-migrations"
  description   = "Run database migrations"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/helper/database/runMigrations"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn,
    module.lambda_layer_posts_database.lambda_layer_arn
  ]

  depends_on = [module.users_database]

  environment_variables = {
    USERS_DB_HOST = module.users_database.db_instance_address,
    USERS_DB_PORT = module.users_database.db_instance_port,
    USERS_DB_NAME = var.users_database_name,
    USERS_DB_USER = module.users_database.db_instance_username,
    USERS_DB_PASS = module.users_database.db_instance_password,
    POSTS_DB_HOST = module.posts_database.db_instance_address,
    POSTS_DB_PORT = module.posts_database.db_instance_port,
    POSTS_DB_NAME = var.posts_database_name,
    POSTS_DB_USER = module.posts_database.db_instance_username,
    POSTS_DB_PASS = module.posts_database.db_instance_password
  }
}

################################################################################
# ADMINS Lambdas
################################################################################
module "create_admin_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "create-admin"
  description   = "Create new admin"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/admins/createAdmin"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  depends_on = [module.users_database]

  environment_variables = {
    DB_HOST = module.users_database.db_instance_address,
    DB_PORT = module.users_database.db_instance_port,
    DB_NAME = var.users_database_name,
    DB_USER = module.users_database.db_instance_username,
    DB_PASS = module.users_database.db_instance_password,
  }
}

################################################################################
# USERS Lambdas
################################################################################
module "create_user_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "create-user"
  description   = "Create new user"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/users/createUser"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false
  attach_policy_statements  = true
  policy_statements         = {
    sqs = {
      effect    = "Allow",
      actions   = ["sqs:*"],
      resources = [aws_sqs_queue.users_demo_post_queue.arn]
    },
    sns_new_user = {
      effect    = "Allow",
      actions   = ["sns:*"],
      resources = [aws_sns_topic.new_user_added_topic.arn]
    },
    sqs_failure = {
      effect    = "Allow",
      actions   = ["sqs:SendMessage"],
      resources = [aws_sqs_queue.users_demo_post_dlq.arn]
    },
  }

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  depends_on = [module.users_database]

  environment_variables = {
    DB_HOST           = module.users_database.db_instance_address,
    DB_PORT           = module.users_database.db_instance_port,
    DB_NAME           = var.users_database_name,
    DB_USER           = module.users_database.db_instance_username,
    DB_PASS           = module.users_database.db_instance_password,
    AWS_SNS_REGION    = var.aws_region
    AWS_SNS_TOPIC_ARN = aws_sns_topic.new_user_added_topic.arn
    AWS_SQS_REGION    = var.aws_region
    AWS_SQS_QUEUE_URL = aws_sqs_queue.users_demo_post_queue.url
  }
}

module "get_user_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "get-user"
  description   = "Get specific user"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/users/getUser"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  environment_variables = {
    DB_HOST = module.users_database.db_instance_address,
    DB_PORT = module.users_database.db_instance_port,
    DB_NAME = var.users_database_name,
    DB_USER = module.users_database.db_instance_username,
    DB_PASS = module.users_database.db_instance_password,
  }
}

module "list_users_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "list-users"
  description   = "List users"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/users/listUsers"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  environment_variables = {
    DB_HOST = module.users_database.db_instance_address,
    DB_PORT = module.users_database.db_instance_port,
    DB_NAME = var.users_database_name,
    DB_USER = module.users_database.db_instance_username,
    DB_PASS = module.users_database.db_instance_password,
  }
}

module "update_user_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "update-user"
  description   = "Update specific user"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/users/updateUser"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false
  attach_policies           = true
  number_of_policies        = 1
  policies                  = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  ]

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  environment_variables = {
    DB_HOST       = module.users_database.db_instance_address,
    DB_PORT       = module.users_database.db_instance_port,
    DB_NAME       = var.users_database_name,
    DB_USER       = module.users_database.db_instance_username,
    DB_PASS       = module.users_database.db_instance_password,
    AWS_S3_REGION = var.aws_region
    AWS_S3_BUCKET = module.users_profile_images_bucket.s3_bucket_id
  }
}

module "modify_user_profile_image_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "modify-user-profile-image"
  description   = "Modify specific user profile image"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  # Queue visibility timeout: 30 seconds is less than Function timeout: 60 seconds
  timeout       = 30

  source_path = "../../../backend/serverless/lambdas/users/updateThumbnails"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  attach_dead_letter_policy = false
  attach_policies           = true
  number_of_policies        = 2
  policies                  = [
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole",
  ]

  event_source_mapping = {
    sqs = {
      event_source_arn = aws_sqs_queue.users_profile_images_queue.arn
    }
  }

  allowed_triggers = {
    sqs = {
      principal  = "sqs.amazonaws.com"
      source_arn = aws_sqs_queue.users_profile_images_queue.arn
    }
  }

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_users_database.lambda_layer_arn
  ]

  environment_variables = {
    DB_HOST           = module.users_database.db_instance_address,
    DB_PORT           = module.users_database.db_instance_port,
    DB_NAME           = var.users_database_name,
    DB_USER           = module.users_database.db_instance_username,
    DB_PASS           = module.users_database.db_instance_password,
    AWS_S3_REGION     = var.aws_region
    AWS_S3_BUCKET     = module.users_thumbnails_images_bucket.s3_bucket_id
    AWS_SQS_REGION    = var.aws_region
    AWS_SQS_QUEUE_URL = aws_sqs_queue.users_profile_images_queue.url
  }
}

################################################################################
# POSTS Lambdas
################################################################################
module "create_post_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "create-post"
  description   = "Create new post for user"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 30

  source_path = "../../../backend/serverless/lambdas/posts/createPost"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  attach_policies    = true
  number_of_policies = 1
  policies           = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole",
  ]

  event_source_mapping = {
    sqs = {
      event_source_arn = aws_sqs_queue.users_demo_post_queue.arn
    }
  }

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    },
    sqs = {
      principal  = "sqs.amazonaws.com"
      source_arn = aws_sqs_queue.users_demo_post_queue.arn
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_posts_database.lambda_layer_arn
  ]

  depends_on = [module.posts_database]

  environment_variables = {
    DB_HOST = module.posts_database.db_instance_address,
    DB_PORT = module.posts_database.db_instance_port,
    DB_NAME = var.posts_database_name,
    DB_USER = module.posts_database.db_instance_username,
    DB_PASS = module.posts_database.db_instance_password,
  }
}

module "list_user_posts_lambda" {
  source = "terraform-aws-modules/lambda/aws"
  version = "2.35.0"

  function_name = "list-users-post"
  description   = "List user posts"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  publish       = true
  timeout       = 60

  source_path = "../../../backend/serverless/lambdas/posts/listPosts"

  store_on_s3 = true
  s3_bucket   = "my-bucket-id-with-lambda-builds"

  vpc_subnet_ids         = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.private_vpc_sg.security_group_id]
  attach_network_policy  = true

  allowed_triggers = {
    AllowExecutionFromAPIGateway = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
    }
  }

  attach_dead_letter_policy = false

  layers = [
    module.lambda_layer_logging.lambda_layer_arn,
    module.lambda_layer_posts_database.lambda_layer_arn
  ]

  depends_on = [module.posts_database]

  environment_variables = {
    DB_HOST = module.posts_database.db_instance_address,
    DB_PORT = module.posts_database.db_instance_port,
    DB_NAME = var.posts_database_name,
    DB_USER = module.posts_database.db_instance_username,
    DB_PASS = module.posts_database.db_instance_password,
  }
}

################################################################################
################################################################################
################################################################################
# API GW CONFIGURATION
################################################################################
################################################################################
################################################################################
module "api_gateway" {
  source = "terraform-aws-modules/apigateway-v2/aws"
  version = "1.5.1"

  name          = "main-GW-${var.environment}"
  description   = "HTTP API Gateway"
  protocol_type = "HTTP"

  cors_configuration = {
    allow_headers = [
      "content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token", "x-amz-user-agent"
    ]
    allow_methods = ["*"]
    allow_origins = ["*"]
  }

  create_api_domain_name = false
  # Routes and integrations
  integrations           = {
    # Auth
    "POST /login" = {
      lambda_arn             = module.login.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
    }
    # Admins
    "POST /databases/migrations" = {
      lambda_arn             = module.run_db_migrations.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.basic_auth.id
    }
    # Admins
    "POST /admins" = {
      lambda_arn             = module.create_admin_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.basic_auth.id
    }
    # Users
    "POST /users" = {
      lambda_arn             = module.create_user_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.jwt_auth.id
    }
    "GET /users" = {
      lambda_arn             = module.list_users_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.jwt_auth.id
    }
    "GET /users/{userId}" = {
      lambda_arn             = module.get_user_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.jwt_auth.id
    }
    "PUT /users/{userId}" = {
      lambda_arn             = module.update_user_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.jwt_auth.id
    }
    # Posts
    "POST /users/{userId}/posts" = {
      lambda_arn             = module.create_post_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.jwt_auth.id
    }
    "GET /users/{userId}/posts" = {
      lambda_arn             = module.list_user_posts_lambda.lambda_function_invoke_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 12000
      authorization_type     = "CUSTOM"
      authorizer_id          = aws_apigatewayv2_authorizer.jwt_auth.id
    }
  }

  tags = {
    Name = "http-apigateway"
  }
}

resource "aws_iam_role" "invocation_role" {
  name = "api_gateway_auth_invocation"
  path = "/"

  assume_role_policy = file("../common/templates/policies/api_gateway_auth_invocation.json.tpl")
}

################################################################################
################################################################################
################################################################################
# API GW AUTHORIZER CONFIGURATION
################################################################################
################################################################################
################################################################################
resource "aws_iam_role_policy" "invocation_policy" {
  name = "default"
  role = aws_iam_role.invocation_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "lambda:InvokeFunction",
      "Effect": "Allow",
      "Resource": "${module.jwt_auth.lambda_function_arn}"
    }
  ]
}
EOF
}

resource "aws_apigatewayv2_authorizer" "jwt_auth" {
  api_id                            = module.api_gateway.apigatewayv2_api_id
  authorizer_type                   = "REQUEST"
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "LambdaAuthorizer"
  authorizer_uri                    = module.jwt_auth.lambda_function_invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_credentials_arn        = aws_iam_role.invocation_role.arn
}

resource "aws_iam_role_policy" "basic_auth_invocation_policy" {
  name = "basic_auth_invocation_policy"
  role = aws_iam_role.invocation_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "lambda:InvokeFunction",
      "Effect": "Allow",
      "Resource": "${module.basic_auth.lambda_function_arn}"
    }
  ]
}
EOF
}

resource "aws_apigatewayv2_authorizer" "basic_auth" {
  api_id                            = module.api_gateway.apigatewayv2_api_id
  authorizer_type                   = "REQUEST"
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "LambdaBasicAuthorizer"
  authorizer_uri                    = module.basic_auth.lambda_function_invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_credentials_arn        = aws_iam_role.invocation_role.arn
}
