output "cluster_id" {
  description = "EKS cluster ID."
  value = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value = module.eks.cluster_security_group_id
}

output "cluster_ca_certificate" {
  description = "kubectl certificate_authority."
  value = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
}

output "config_map_aws_auth" {
  description = "A kubernetes configuration to authenticate to this EKS cluster."
  value = module.eks.aws_auth_configmap_yaml
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value = var.cluster_name
}
