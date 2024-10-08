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

# Write SSH private key for instance to a file so it can be used to authenticate ansible-playbook
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

# Allow ssh from provisioning machine
module "security_group_ssh" {
  source  = "terraform-aws-modules/security-group/aws//modules/ssh"
  version = "5.1.2"

  name   = "ssh"
  vpc_id = module.vpc.vpc_id

  ingress_cidr_blocks = [var.provisioning_ip_range]
}

# Allow elasticsearch for public
module "security_group_elasticsearch" {
  source  = "terraform-aws-modules/security-group/aws//modules/elasticsearch"
  version = "5.1.2"

  name   = "elasticsearch"
  vpc_id = module.vpc.vpc_id

  auto_ingress_rules  = ["elasticsearch-rest-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
}

module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.1"

  count = var.node_count

  name              = "es-node-${count.index}"
  ami               = data.aws_ami.debian.id
  instance_type     = var.instance_type
  availability_zone = element(module.vpc.azs, count.index)
  subnet_id         = element(module.vpc.public_subnets, count.index)

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

moved {
  from = module.ec2
  to   = module.ec2[0]
}

resource "aws_eip" "es" {
  count = var.node_count

  domain   = "vpc"
  instance = module.ec2[count.index].id
}

moved {
  from = aws_eip.k3s_server
  to   = aws_eip.es[0]
}

resource "random_password" "elastic" {
  length  = 16
  special = false
}

locals {
  initial_master_nodes = join(",", module.ec2.*.private_ip)
  discovery_seed_hosts = join(",", [for ip in module.ec2.*.private_ip : "${ip}:9300"])
}

resource "null_resource" "ansible" {
  count = var.node_count

  depends_on = [
    local_sensitive_file.private_key,
    module.ec2,
    local_file.ca_cert,
    local_file.server_cert,
    local_sensitive_file.server_key
  ]

  # Wait until instance is reachable before run the ansible-playbook
  provisioner "remote-exec" {
    connection {
      host = module.ec2[count.index].public_ip
      user = "admin"
      private_key = file(local_sensitive_file.private_key.filename)
    }

    inline = ["echo 'connected!'"]
  }

  # Run the ansible-playbook from local
  provisioner "local-exec" {
    command = <<-EOT
       ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
         -T 300 \
         -i ${module.ec2[count.index].public_ip},  \
         --user admin \
         --private-key ${local_sensitive_file.private_key.filename} \
         -e "elastic_user_password=${random_password.elastic.result}" \
         -e "initial_master_nodes=${local.initial_master_nodes}" \
         -e "discovery_seed_hosts=${local.discovery_seed_hosts}" \
         -e "es_node_name=${module.ec2[count.index].private_ip}" \
         -e "bootstrap_es=${var.bootstrap_es}" \
         ../ansible/elasticsearch.yaml
    EOT
  }
}

moved {
  from = null_resource.ansible
  to   = null_resource.ansible[0]
}

# private key for Certificate Authority (CA) that will issue certificate for server
resource "tls_private_key" "ca" {
  algorithm = "RSA"
}

# Issue a self signed certificate for CA
resource "tls_self_signed_cert" "ca_cert" {
  private_key_pem = tls_private_key.ca.private_key_pem

  is_ca_certificate = true

  subject {
    country     = "ID"
    province    = "Jawa Barat"
    common_name = "Test Elasticsearch CA"
  }

  validity_period_hours = 43800 //  1825 days or 5 years

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

# Write CA certificate to a file so it can be uploaded later by ansible playbook
resource "local_file" "ca_cert" {
  content  = tls_self_signed_cert.ca_cert.cert_pem
  filename = "../ansible/files/ca.cert"
}

# private key for elasticsearch server SSL
resource "tls_private_key" "server" {
  algorithm = "RSA"
}

# certificate signing request (CSR) for elasticsearch server SSL
resource "tls_cert_request" "server" {

  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    country     = "ID"
    province    = "Jawa Barat"
    common_name = "Test Elasticsearch"
  }
}

# certificate for elasticsearch server SSL, signed by CA
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

# Write certificate for server SSL to a file so it can be uploaded later by ansible playbook
resource "local_file" "server_cert" {
  content  = tls_locally_signed_cert.server.cert_pem
  filename = "../ansible/files/server.cert"
}

# Write private key for server SSL to a file so it can be uploaded later by ansible playbook
resource "local_sensitive_file" "server_key" {
  content  = tls_private_key.server.private_key_pem
  filename = "../ansible/files/server.key"
}
