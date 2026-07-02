# terraform/variables.tf - Input Variables

variable "db_username" {
  description = "Master username for the RDS PostgreSQL instance."
  type        = string
  default     = "ledger_admin"
}

variable "db_password" {
  description = "Master password for the RDS PostgreSQL instance. Supply via a TF_VAR_db_password environment variable, a secrets manager, or a git-ignored *.tfvars file. Never commit a real value."
  type        = string
  sensitive   = true
}
