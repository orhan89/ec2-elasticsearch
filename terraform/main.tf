provider "aws" {
  region = "ap-southeast-1"
}

data "aws_availability_zones" "available" {}

locals {
  name     = "es"
  vpc_cidr = "192.168.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs            = local.azs
  public_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
}

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name           = "es"
  create_private_key = true
}

resource "local_sensitive_file" "private_key" {
  content  = module.key_pair.private_key_pem
  filename = ".ssh/id_rsa"
}

data "aws_ami" "debian" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"

    values = [
      "debian-12-amd64-*",
    ]
  }
}

module "security_group_ssh" {
  source  = "terraform-aws-modules/security-group/aws//modules/ssh"
  version = "5.1.2"

  name   = "ssh"
  vpc_id = module.vpc.vpc_id

  ingress_cidr_blocks = [var.provisioning_ip_range]
}

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.1"

  name              = "es-node"
  ami               = data.aws_ami.debian.id
  instance_type     = var.instance_type
  availability_zone = element(module.vpc.azs, 0)
  subnet_id         = element(module.vpc.public_subnets, 0)

  key_name = module.key_pair.key_pair_name

  vpc_security_group_ids = [
    module.security_group_ssh.security_group_id,
  ]

  root_block_device = [
    {
      volume_type = "gp3"
      volume_size = 10
    },
  ]
}

resource "aws_eip" "k3s_server" {
  vpc      = true
  instance = module.ec2.id
}
