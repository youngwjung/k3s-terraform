data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64*"]
  }
}

data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

module "node_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1"

  name        = "k3s-node-sg"
  description = "k3s node security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "all-all"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

module "node_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role"

  name = "k3s-node"

  create_instance_profile = true

  trust_policy_permissions = {
    ec2 = {
      effect = "Allow"
      actions = [
        "sts:AssumeRole"
      ]
      principals = [{
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }]
    }
  }

  policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k3s" {
  key_name   = "k3s"
  public_key = tls_private_key.this.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.this.private_key_pem
  filename        = "k3s.pem"
  file_permission = "0400"
}


module "node" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "6.4.0"

  count = var.num_node

  name = "k3s-${count.index}"

  create_security_group = false
  create_eip            = true

  ami                    = data.aws_ami.rhel.id
  instance_type          = "m7i-flex.xlarge"
  key_name               = aws_key_pair.k3s.key_name
  subnet_id              = module.vpc.public_subnets[0]
  private_ip             = cidrhost(var.vpc_cidr, 10 + count.index)
  vpc_security_group_ids = [module.node_sg.security_group_id]
  iam_instance_profile   = module.node_role.instance_profile_name

  root_block_device = {
    type = "gp3"
    size = 50
  }

  ebs_volumes = {
    "/dev/sdf" = {
      size = 20
    }
  }

  ignore_ami_changes = true
}

module "lb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.0"

  name               = "${local.project}-lb"
  load_balancer_type = "network"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  security_group_ingress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  listeners = {
    k3s-api = {
      port     = 6443
      protocol = "TCP"
      forward = {
        target_group_key = "k3s-api"
      }
    }
  }

  target_groups = {
    k3s-api = {
      name                 = "k3s-api"
      protocol             = "TCP"
      port                 = 6443
      target_type          = "ip"
      deregistration_delay = 10
      create_attachment    = false
      health_check = {
        protocol = "TCP"
        interval = 10
        timeout  = 5
      }
    }
  }

  additional_target_group_attachments = {
    for idx, node in module.node : "k3s-${idx}" => {
      target_group_key = "k3s-api"
      target_type      = "ip"
      target_id        = node.private_ip
      port             = 6443
    }
  }
}