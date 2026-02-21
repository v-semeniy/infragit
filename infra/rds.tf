# # RDS Subnet Group
# resource "aws_db_subnet_group" "main" {
#   name       = "main-db-subnet-group"
#   subnet_ids = aws_subnet.private[*].id

#   tags = {
#     Name = "main-db-subnet-group"
#   }
# }

# # RDS Instance (MySQL example - can be modified for other engines)
# resource "aws_db_instance" "main" {
#   identifier     = "main-database"
#   engine         = "mysql"
#   engine_version = "8.0"
#   instance_class = "db.t3.micro"
  
#   allocated_storage     = 20
#   max_allocated_storage = 100
#   storage_type          = "gp2"
#   storage_encrypted     = true

#   db_name  = var.db_name
#   username = var.db_username
#   password = var.db_password

#   vpc_security_group_ids = [aws_security_group.rds.id]
#   db_subnet_group_name   = aws_db_subnet_group.main.name

#   backup_retention_period = 7
#   backup_window          = "03:00-04:00"
#   maintenance_window     = "sun:04:00-sun:05:00"

#   skip_final_snapshot = true
#   deletion_protection = false

#   tags = {
#     Name = "main-database"
#   }
# }
