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

module "security_group_elasticsearch" {
  source  = "terraform-aws-modules/security-group/aws//modules/elasticsearch"
  version = "5.1.2"

  name   = "elasticsearch"
  vpc_id = module.vpc.vpc_id

  auto_ingress_rules  = ["elasticsearch-rest-tcp"]
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
    module.security_group_elasticsearch.security_group_id,
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

resource "random_password" "elastic" {
  length  = 16
  special = false
}

resource "null_resource" "ansible" {
  depends_on = [
    local_sensitive_file.private_key,
    module.ec2,
    local_file.ca_cert,
    local_file.server_cert,
    local_sensitive_file.server_key
  ]

  provisioner "local-exec" {
    command = <<-EOT
       ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
         -T 300 \
         -i ${module.ec2.public_ip},  \
         --user admin \
         --private-key ${local_sensitive_file.private_key.filename} \
         -e "elastic_user_password=${random_password.elastic.result}" \
         -e "node_name=node1" \
         ../ansible/elasticsearch.yaml
    EOT
  }
}

resource "tls_private_key" "ca" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "ca_cert" {
  private_key_pem = tls_private_key.ca.private_key_pem

  is_ca_certificate = true

  subject {
    country             = "ID"
    province            = "Jawa Barat"
    common_name         = "Test Elasticsearch CA"
  }

  validity_period_hours = 43800 //  1825 days or 5 years

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "ca_cert" {
  content  = tls_self_signed_cert.ca_cert.cert_pem
  filename = "../ansible/files/ca.cert"
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
}

resource "tls_cert_request" "server" {

  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    country             = "ID"
    province            = "Jawa Barat"
    common_name         = "Test Elasticsearch"
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem = tls_cert_request.server.cert_request_pem
  // CA Private key
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  // CA certificate
  ca_cert_pem = tls_self_signed_cert.ca_cert.cert_pem

  validity_period_hours = 43800

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "local_file" "server_cert" {
  content  = tls_locally_signed_cert.server.cert_pem
  filename = "../ansible/files/server.cert"
}

resource "local_sensitive_file" "server_key" {
  content  = tls_private_key.server.private_key_pem
  filename = "../ansible/files/server.key"
}
