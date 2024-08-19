This is an IaC implementation to build an elasticsearch cluster (multi-node) on AWS EC2 using Terraform and Ansible. The cluster is secured with login credentials, and all communication is secured with SSL.

## Requirements

- Terraform 
- Ansible

## How It works

I use terraform to provision and maintain all the cloud resources needed to run an elasticsearch cluster: VPC, EC2 instances, security group, ect. It will also be used it to generate all the security material used in the project: SSH key, elasticsearch credentials, and SSL certificate (for both CA and servers). Later on I use ansible playbook to install, setup, and bootstrap the elasticsearch on each of the EC2 instances that has been provisioned by terraform.

### Why Terraform?

Terraform allow us to manage infrastructure resources (primarily in cloud) in a declarative way. And since it track the latest state of all existing resources, it is smart enough to detect drift between the expected and actual resources so we can be sure of the correctness of our system. It works with most of cloud providers, but it can also be used to manage many software too (database, SaaS, etc). Actually, you can always write a new provider to extend terraform to operate with any services. Terraform also allow us to reuse an existing modules (a collection of related resources and datasource to abstract some specific use-cases), where many is published publicly ready to be used. By using terraform, we don't really need to know anymore the details of how to bring up each of the infrastructure resources so we can focus on the architecture.

### Why Ansible?

While terraform is mainly used to  provision and manage the infrastructure resources, ansible is usually used for configuration management. For this particular project, I use ansible to install, setup, and bootstrap the elasticsearch service in each of the EC2 instances (the actual number is depend on the node_count variable) that has been provisioned by terraform. Unlike the declarative style of terraform, ansible is working procedurally so we need to be aware of the execution order for each steps of the processes. But just like terraform, ansible also offer reusability with something called ansible role, which is collection of related step/tasks and configuration (eq: to install elasticsearch) that can be called in another places. I leverage this fact by using existing ansible role from the elastic team itself to setup and bootstrap the cluster, and save me a lot of time from having to define all the installation steps by hand.

Just to ensure that I have cover all of the options, actually there is another (perhaps better) way of bootstraping elasticsearch that is becoming popular: ECK (Elastic Cloud on Kubernetes). In fact, the official ansible role that i used to install elasticsearch in this project is already deprecated (the git repo has been archived for the last 2 years) and elastic suggest us to move to ECK. But since running kubernetes will add some overhead, and the fact that i have to work with a limited resources (1g of RAM), i decided to go with bare installation with ansible instead.

## PoC

There are some variables that can be set before executing the terraform configuration. For convenience, you can set this in terraform.tfvars file so you don't have to specity it for every apply.

* instance_type = this is the AWS EC2 instance type that will be created to host the elasticsearch node
* node_count = the number of AWS EC2 instance (and elasticsearch node) to be created
* provisioning\_ip\_range = IP address range that will be allowed to SSH and provision elasticsearch on the EC2 instance (fill this with your own public IP).

You will also need to setup credentials to access your AWS project.

To apply the terraform configuration, simply run

```sh
$ terraform apply
```

There is no need to run the ansible playbook manually as it will be called automatically by terraform.

Get the IP address of all the new instances from terraform output

```sh
$ terraform output server\_public\_ip
```

And to get the elastic password
```sh
$ ELASTIC_PASSWORD=$(terraform output --raw elastic_password)
```

Here I put some screenshot for PoC

![PoC1](/images/poc1.png)

![PoC2](/images/poc2.png)

![PoC3](/images/poc3.png)


## Resources

[1] [terraform-aws-modules/ec2-instance module](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws/latest)

[2] [terraform-aws-modules/vpc module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)

[3] [terraform-aws-modules/security-group module](https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws/latest)

[4] [ansible-elasticsearch role](https://github.com/elastic/ansible-elasticsearch)

[5] [Elastic Cloud on the Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-overview.html)
