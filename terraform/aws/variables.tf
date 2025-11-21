variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}


variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "test-eks-cluster"
}