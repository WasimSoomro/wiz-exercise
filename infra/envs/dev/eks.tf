locals {
  cluster_name = "${var.name}-eks"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # subnet_ids = private_subnets =  “cluster in private subnet”


  cluster_endpoint_public_access = true # endpoint public access = true = lets your laptop run kubectl easily


  
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      subnet_ids = module.vpc.private_subnets # node group in private subnets = pods can still reach internet via NAT that's already built

    }
  }

  tags = {
    Project = var.name
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
