provider "aws" {
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.aws_profile
  region                   = var.aws_region
#  default_tags {
#    tags = var.default_tags
#  }
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

module "networking" {
  source                        = "../common/modules/network"
  region                        = var.aws_region
  vpc_name                      = var.vpc_name
  vpc_cidr                      = var.cidr_block
  private_subnet_count          = var.private_subnet_count
  public_subnet_count           = var.public_subnet_count
  public_subnet_additional_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_additional_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

################################################################################
# Security Groups
################################################################################
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
      #     We should create separate SGs for every db as they could have different ports. In this case all have PGs 5432
      to_port          = module.books_database.db_instance_port
      cidr_blocks      = [module.networking.vpc_cidr_block]
      ipv6_cidr_blocks = [module.networking.vpc_ipv6_cidr_block]
    }
  }
}

module "eks_worker_sg" {
  source                  = "../common/modules/security"
  sg_name                 = "eks-worker-group-mgmt"
  description             = "worker group mgmt"
  vpc_id                  = module.networking.vpc_id
  egress_cidr_rules       = {}
  egress_source_sg_rules  = {}
  ingress_source_sg_rules = {}
  ingress_cidr_rules      = {
    1 = {
      description      = "allow inbound access only from resources in VPC"
      protocol         = "tcp"
      from_port        = 22
      to_port          = 22
      cidr_blocks      = [module.networking.vpc_cidr_block]
      ipv6_cidr_blocks = [module.networking.vpc_ipv6_cidr_block]
    }
  }
}

################################################################################
# Database Configuration
################################################################################
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

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "18.10.1"
  cluster_name    = var.cluster_name
  cluster_version = "1.21"

  subnet_ids = module.networking.private_subnet_ids
  vpc_id     = module.networking.vpc_id

  self_managed_node_group_defaults = {
    instance_type                = "t2.small"
  }

  self_managed_node_groups = {
    worker-group-1 = {
      instance_type                 = "t2.small"
      additional_security_group_ids = [module.eks_worker_sg.security_group_id]
      min_size                      = 1
      max_size                      = 5
      desired_size                  = 2
    }
  }

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = module.eks.eks_managed_node_groups

  #            This policy does not have to exist at the time of cluster creation. Terraform can
  #            deduce the proper order of its creation to avoid errors during creation
  policy_arn = aws_iam_policy.worker_policy.arn
  role       = each.value.iam_role_name
}

################################################################################
# aws-auth configmap
# Only EKS managed node groups automatically add roles to aws-auth configmap
# so we need to ensure fargate profiles and self-managed node roles are added
################################################################################

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_id
}

locals {
  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.eks.cluster_id
      cluster = {
        certificate-authority-data = module.eks.cluster_certificate_authority_data
        server                     = module.eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.eks.cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })
}

resource "null_resource" "apply" {
  triggers = {
    kubeconfig = base64encode(local.kubeconfig)
    cmd_patch  = <<-EOT
      kubectl create configmap aws-auth -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)
      kubectl patch configmap/aws-auth --patch "${module.eks.aws_auth_configmap_yaml}" -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
    command = self.triggers.cmd_patch
  }
}

resource "aws_iam_policy" "worker_policy" {
  name        = "worker-policy"
  description = "Worker policy for the ALB Ingress"

  policy = file("../common/templates/eks/iam-policy.json")
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

resource "helm_release" "ingress" {
  name       = "ingress"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress-controller"

  create_namespace = true
  namespace        = "ingress-nginx"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "service.annotations"
    value = "service.beta.kubernetes.io/aws-load-balancer-type: nlb"
  }
}
