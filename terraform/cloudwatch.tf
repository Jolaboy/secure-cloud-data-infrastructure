# terraform/cloudwatch.tf - Observability & Telemetry

# 1. Create a CloudWatch metric alarm tracking high database CPU consumption
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "rds-production-high-cpu-utilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300 # Evaluated in 5-minute intervals
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors severe RDS engine CPU spikes under heavy concurrent workloads."
  
  dimensions = {
    # This targets your database engine cluster identifier
    DBInstanceIdentifier = "production-ledger-db"
  }
}

# 2. Provision a dedicated CloudWatch Log Group for secure audit trails
resource "aws_cloudwatch_log_group" "data_lake_audit_log" {
  name              = "/aws/vendedlogs/data-lake-access-audit"
  retention_in_days = 30 # Keeps storage optimized and cost-efficient
}