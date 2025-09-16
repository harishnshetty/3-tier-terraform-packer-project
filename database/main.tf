# main.tf (simplified version)
# Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-subnet-group"
  subnet_ids = [
    data.terraform_remote_state.network.outputs.database_private_subnet_1a_id,
    data.terraform_remote_state.network.outputs.database_private_subnet_1b_id,
    data.terraform_remote_state.network.outputs.database_private_subnet_1c_id
  ]

  tags = {
    Name        = "${var.project_name}-subnet-group"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier             = "${var.project_name}-db"
  engine                = var.db_engine
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  storage_type          = var.db_storage_type
  db_name               = var.db_name
  username              = var.db_username
  password              = var.db_password
  skip_final_snapshot   = true
  multi_az              = false
  publicly_accessible   = false

  vpc_security_group_ids = [data.terraform_remote_state.network.outputs.rds_sg_id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Enable storage autoscaling
  max_allocated_storage = 100

  # Disable Performance Insights for micro instances
  performance_insights_enabled = false

  # Add these parameters to avoid upgrade requirements
  apply_immediately       = true
  deletion_protection     = false

  tags = {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  }
}