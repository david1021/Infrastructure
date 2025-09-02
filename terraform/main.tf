provider "aws" {
  profile = "staging"
  region  = "us-east-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

# Key Pair
resource "aws_key_pair" "my_key_pair" {
  key_name   = "my-ec2-key"
  public_key = file("~/.ssh/id_rsa.pub") # Path to your public SSH key
}

# Dedicated security group for EC2 instance
resource "aws_security_group" "staging_sg_open_access" {
  name        = "staging-sg-open-access"
  description = "Security group for staging open access"
  vpc_id      = module.vpc.vpc_attributes.id

  ingress {
    description = "All inbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "open-server-access"
  }
}

resource "aws_instance" "frontend_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.my_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.staging_sg_open_access.id]
  subnet_id              = module.vpc.public_subnet_attributes_by_az["us-east-1a"].id

  tags = {
    Name = "frontend-server"
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i '${self.public_ip},' --private-key '~/.ssh/id_rsa' setup.yaml"
  }

  user_data = <<-EOF
              #!/bin/bash
              
              # 1. Install Ansible
              sudo apt-get update
              sudo apt-get install -y ansible
              
              # 3. Run the Ansible Playbook
              sudo ansible-playbook playbook.yaml
              EOF
}

module "vpc" {
  source   = "aws-ia/vpc/aws"
  version = ">= 4.2.0"

  name                                 = "staging-vpc"
  cidr_block                           = "10.0.0.0/16"
  vpc_assign_generated_ipv6_cidr_block = true
  vpc_egress_only_internet_gateway     = true
  az_count                             = 1

  subnets = {
    # Dual-stack subnet
    public = {
      netmask                   = 24
      assign_ipv6_cidr          = true
      nat_gateway_configuration = "all_azs" # options: "single_az", "none"
    }
    # IPv4 only subnet
    private = {
      # omitting name_prefix defaults value to "private"
      name_prefix  = "private_with_egress"
      netmask      = 24
      connect_to_public_natgw = true
    }
    # IPv6-only subnet
    private_ipv6 = {
      ipv6_native      = true
      assign_ipv6_cidr = true
      connect_to_eigw  = true
    }
  }
}