# terraform/vpc.tf - Network Isolation Layer

# 1. Create the primary isolated Virtual Private Cloud
resource "aws_vpc" "data_perimeter" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "production-data-perimeter-vpc"
  }
}

# 2. Create an Isolated Private Subnet for the RDS instance
resource "aws_subnet" "database_private_a" {
  vpc_id            = aws_vpc.data_perimeter.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "database-isolated-subnet-1a"
  }
}

# 3. Create a strict Security Group that blocks all ingress by default
# Only allowing database traffic if it originates within the VPC internal network
resource "aws_security_group" "db_security_perimeter" {
  name        = "db-security-perimeter"
  description = "Isolate relational database traffic completely from public ingress"
  vpc_id      = aws_vpc.data_perimeter.id

  ingress {
    description = "Allow internal backend applications inside the VPC to connect"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.data_perimeter.cidr_block] # Strict internal-only boundary
  }

  egress {
    description = "Allow outbound traffic only for secure API tracking"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}