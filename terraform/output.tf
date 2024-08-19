output "server_public_ip" {
  value = module.ec2.*.public_ip
}

output "elastic_password" {
  value     = random_password.elastic.result
  sensitive = true
}
