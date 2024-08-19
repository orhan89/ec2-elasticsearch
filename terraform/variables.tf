variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "provisioning_ip_range" {
  type    = string
  default = "127.0.0.1/32"
}
