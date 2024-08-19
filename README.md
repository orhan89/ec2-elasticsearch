This is an IaC implementation to build an elasticsearch cluster on AWS EC2 using Terraform and Ansible.

## Requirements

- Terraform 
- Ansible

## How It works

I use terraform to provision and maintain all the cloud resources needed to run an elasticsearch cluster: VPC, EC2 instances, security group, ect. I also use it to generate all the security artifact used in the project: SSH key, certificate. 

Terraform allow us to manage infrastructure resources (primarily in cloud) in a declarative way. And since it track the latest state of all existing resources, it is also smart enough to detect drift between the expected and actual resources so we can be sure of the correctness of our system. It works with most of cloud providers, but it also work to manage many software too (database, SaaS, etc). It is an extensible through a plugin mechanism called terraform providers to interract with the target system, where someone can always write a provider for any services. With terraform we can also reuse existing component (called modules), where many is published publicly ready to be used. By using terraform, we don't really need to know anymore the details of how to bring up each of the infrastructure resources so we can focus on the architecture.

While terraform is mainly used to  provision and manage the infrastructure resources, ansible is usually used for configuration management. For this particular project, I use ansible to install, setup, and bootstrap the elasticsearch service in each of the EC2 instances (the actual number is depend on the node_count variable) that has been provisioned by terraform. Unlike the declarative style of terraform, ansible is working procedurally so we need to be aware of the execution order for each steps of the processes. But just like terraform, ansible offer reusability with something called ansible role, where several related step/tasks and configuration is abstracted as a unit of execution that can be recall later in another places. I leverage this fact by using existing ansible role from the elastic team itself to setup and bootstrap the cluster, and save me a lot of time from having to define all the installation steps by hand.

Just so i cover all the options, actually there is another (perhaps better) way of bootstraping elasticsearch that is becoming popular: ECK (Elastic Cloud on Kubernetes). In fact, the official ansible role that i used to install elasticsearch in this project is already deprecated (the git repo has been archived for the last 2 years). But since running kubernetes will add some overhead, and the fact that i have to work with a limited resources (1g of RAM), i decided to go with ansible instead.

## PoC

There are some variables that can be set before executing the terraform configuration. For convenience, set this in terraform.tfvars file.

* instance_type = this is the AWS EC2 instance type that will be created to host the elasticsearch node
* node_count = the number of AWS EC2 instance (and elasticsearch node) to be created
* provisioning\_ip\_range = IP address range that will be allowed to SSH and provision elasticsearch on the EC2 instance (fill this with your own public IP).

You will also need to setup credentials to access your AWS project.

To apply the terraform configuration, simply run

```
terraform apply
```

There is no need to run the ansible playbook manually as it will be called automatically by terraform.
