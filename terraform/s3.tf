# terraform/s3.tf - Data Lake & Cold Storage Layer

# 1. Provision the primary analytical S3 bucket
resource "aws_s3_bucket" "analytics_data_lake" {
  bucket        = "enterprise-analytics-data-lake-jolaboy" # S3 Buckets must be globally unique
  force_destroy = true
}

# 2. Enforce strict server-side encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "lake_encryption" {
  bucket = aws_s3_bucket.analytics_data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 3. COST OPTIMIZATION: Automated Object Lifecycle Rules
resource "aws_s3_bucket_lifecycle_configuration" "lake_lifecycle" {
  bucket = aws_s3_bucket.analytics_data_lake.id

  rule {
    id     = "archive-legacy-logs-to-glacier"
    status = "Enabled"

    # Explicitly scope the filter to the entire bucket
    filter {}

    # Transition objects to Glacier Flexible Retrieval after 90 days of inactivity
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Permanently delete data after 365 days to respect compliance retention rules
    expiration {
      days = 365
    }
  }
}