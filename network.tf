# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = local.project
  cidr = var.vpc_cidr

  azs            = data.aws_availability_zones.azs.names
  public_subnets = [var.vpc_cidr]

  map_public_ip_on_launch = true
}