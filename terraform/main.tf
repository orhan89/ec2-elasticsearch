provider "aws" {
  region = "ap-southeast-1"
}

data "aws_availability_zones" "available" {}
