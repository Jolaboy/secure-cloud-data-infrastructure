# 💾 terraform/rds.tf - Relational Database Instance Layer

# 1. Create a second isolated subnet in a different AZ (Required by AWS RDS)
resource "aws_subnet" "database_private_b" {
  vpc_id            = aws_vpc.data_perimeter.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-2b" # Complements eu-west-2a from your system layout

  tags = {
    Name = "database-isolated-subnet-1b"
  }
}

# 2. Bundle both private subnets into an official RDS subnet group
resource "aws_db_subnet_group" "db_storage_group" {
  name       = "production-db-subnet-group"
  subnet_ids = [aws_subnet.database_private_a.id, aws_subnet.database_private_b.id]

  tags = {
    Name = "Production DB Subnet Group"
  }
}

# 3. Provision the isolated PostgreSQL engine targeted by your CloudWatch alarms
resource "aws_db_instance" "postgres_db" {
  identifier             = "production-ledger-db" # Links perfectly to your cloudwatch.tf
  allocated_storage      = 20
  max_allocated_storage  = 100 # Enables auto-scaling storage allocation
  engine                 = "postgres"
  engine_version         = "15.4"
  instance_class         = "db.t4g.micro" # Cost-optimized AWS Graviton processing core
  db_name                = "production_ledger"
  username               = "ledger_admin"
  password               = "SecurePassword123!" # Matches your application tier rules
  db_subnet_group_name   = aws_db_subnet_group.db_storage_group.name
  vpc_security_group_ids = [aws_security_group.db_security_perimeter.id]
  skip_final_snapshot    = true # Prevents retention lock holding when tearing down dev stacks

  tags = {
    Name = "production-isolated-rds"
  }
}