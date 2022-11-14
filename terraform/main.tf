terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}


#Variable Declarations
variable "ami-amazon-linux-2" {
  type = string
  default = "ami-09d3b3274b6c5d4aa" # Amazon Linux 2 - us-east-1
}

variable "prefix-name" {
    type = string
    description = "Type your name"
  
}

#EC2 instance using UserData
resource "aws_instance" "docker-instance" {
	ami = var.ami-amazon-linux-2
	instance_type = "t2.micro"
	key_name = aws_key_pair.generated_key.key_name
	vpc_security_group_ids = [aws_security_group.allow_port80.id]
	user_data = <<EOF
		#!/bin/bash
		#######################
    #Update repositories
    yum update -y
		#######################
    #install docker
    yum install -y docker
		systemctl start docker
		systemctl enable docker
    usermod -aG docker ec2-user
    newgrp docker
    #######################
    #install docker-compose
    curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    #######################
    docker run -d -p 80:80 dockersamples/static-site
	EOF
    tags = {
        Name = "${var.prefix-name}-instance"
    }
}

# Get my public ip
data "http" "ip" {
  url = "https://ifconfig.me/ip"
}

#Security Group Resource 
resource "aws_security_group" "allow_port80" {
  name        = "${var.prefix-name}-sg"
  description = "Allow Inbound Traffic"

  ingress {
    description      = "Port 80 from MyIP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["${data.http.ip.response_body}/32"]
  }

  ingress {
    description      = "Port 22 from MyIP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["${data.http.ip.response_body}/32"]
  }
  
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
#Generate private key
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
#Create key pair in AWS
resource "aws_key_pair" "generated_key" {
  key_name   = "${var.prefix-name}-key"
  public_key = tls_private_key.key.public_key_openssh

  provisioner "local-exec" {    # Generate "terraform-key-pair.pem" in current directory
    command = <<-EOT
      echo '${tls_private_key.key.private_key_pem}' > ./'${var.prefix-name}'-key.pem
      chmod 400 ./'${var.prefix-name}'-key.pem
    EOT
  }

}

output "ssh_connect" {
  value = "ssh -i ${var.prefix-name}-key.pem ec2-user@${aws_instance.docker-instance.public_ip}"
}
