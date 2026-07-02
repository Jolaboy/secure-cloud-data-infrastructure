# Secure AWS Cloud Data Infrastructure (IaC)

A production-oriented, security-first, and cost-optimized AWS data perimeter provisioned entirely with **Terraform (Infrastructure as Code)**. This architecture isolates sensitive database assets from public internet exposure while using automated S3 storage tiering to minimize data lake costs, backed by proactive CloudWatch observability.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Security & Optimization Features](#security--optimization-features)
- [Provisioned Resources](#provisioned-resources)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Configuration Reference](#configuration-reference)
- [Cleanup](#cleanup)
- [Roadmap](#roadmap)

---

## Architecture Overview

```text
        [ Public Internet ]
                │
                ✕  (No Internet Gateway — ingress blocked)
                │
   ┌────────────┴──────────────────────────────────────┐
   │  Custom VPC  (10.0.0.0/16)                         │
   │                                                    │
   │   ┌────────────────────────────────────────────┐  │
   │   │  DB Subnet Group (multi-AZ)                 │  │
   │   │   • Private Subnet A (10.0.1.0/24, AZ 2a)   │  │
   │   │   • Private Subnet B (10.0.2.0/24, AZ 2b)   │  │
   │   │                                             │  │
   │   │   [ RDS PostgreSQL 15.4 ]  ← SG: 5432 from  │  │
   │   │     production-ledger-db     VPC CIDR only   │  │
   │   └────────┼────────────────────────────────────┘  │
   └────────────┼───────────────────────────────────────┘
                │ (audit / access logs)
                ▼
   [ S3 Data Lake ]  ──(90 days)──►  [ Glacier ]  ──(365 days)──►  [ Expiration ]
        AES256 SSE          cold archival tier         compliance purge

   [ CloudWatch ]  → RDS CPU alarm (≥ 80%)  +  Audit log group (30-day retention)
```

> **Security note:** The RDS credentials are supplied through Terraform variables (`db_username`, `db_password`) rather than hard-coded. The `db_password` variable is marked `sensitive` and must be provided at apply time — see [Getting Started](#getting-started).

---

## Repository Structure

```text
secure-cloud-data-infrastructure/
├── terraform/
│   ├── provider.tf      # AWS provider and Terraform version constraints
│   ├── variables.tf     # Input variables (DB username / password)
│   ├── vpc.tf           # VPC, isolated private subnet, and security group
│   ├── rds.tf           # Second AZ subnet, DB subnet group, PostgreSQL instance
│   ├── s3.tf            # Encrypted data lake and Glacier lifecycle rules
│   ├── cloudwatch.tf    # CloudWatch metric alarm and audit log group
│   └── terraform.tfvars.example  # Template for local secret values (copy to terraform.tfvars)
└── README.md
```

---

## Security & Optimization Features

### 1. Zero-Ingress Network Isolation
The database tier lives inside a private subnet (`10.0.1.0/24`) within a custom VPC that has **no Internet Gateway attached**. The security group applies a strict ingress rule that permits inbound traffic on port `5432` (PostgreSQL) **only** from within the VPC's internal CIDR range (`10.0.0.0/16`), eliminating direct public exposure.

### 2. Automated Storage Lifecycle Tiering
Objects written to the S3 data lake are automatically moved across storage tiers to balance access speed against cost:

| Age            | Storage Class                 | Purpose                                   |
| -------------- | ----------------------------- | ----------------------------------------- |
| Day 0 – 90     | S3 Standard                   | High-availability, low-latency querying   |
| Day 90 – 365   | S3 Glacier Flexible Retrieval | Cold archival at significantly lower cost |
| Day 365+       | Expired (deleted)             | Automated compliance retention purge      |

All objects are encrypted at rest by default using **server-side encryption (AES256)**.

### 3. Proactive Telemetry & Alarms
A CloudWatch metric alarm watches RDS `CPUUtilization`. If average CPU stays at or above **80%** for **two consecutive 5-minute periods**, the alarm enters the `ALARM` state so engineers can triage before downstream services degrade. A dedicated CloudWatch **log group** captures data lake access audit trails with a 30-day retention window.

---

## Provisioned Resources

| File            | Resource                                             | Description                                    |
| --------------- | ---------------------------------------------------- | ---------------------------------------------- |
| `provider.tf`   | `aws` provider (`~> 5.0`)                            | Targets region `eu-west-2` (London)            |
| `vpc.tf`        | `aws_vpc.data_perimeter`                             | Isolated VPC, `10.0.0.0/16`, DNS enabled       |
| `vpc.tf`        | `aws_subnet.database_private_a`                      | Private subnet `10.0.1.0/24` in `eu-west-2a`   |
| `vpc.tf`        | `aws_security_group.db_security_perimeter`           | Ingress `5432` from VPC CIDR only; open egress |
| `rds.tf`        | `aws_subnet.database_private_b`                      | Second private subnet `10.0.2.0/24` in `eu-west-2b` |
| `rds.tf`        | `aws_db_subnet_group.db_storage_group`               | Groups both private subnets for RDS            |
| `rds.tf`        | `aws_db_instance.postgres_db`                         | PostgreSQL 15.4, `db.t4g.micro`, `production-ledger-db` |
| `s3.tf`         | `aws_s3_bucket.analytics_data_lake`                  | Global data lake bucket (`force_destroy = true`) |
| `s3.tf`         | `aws_s3_bucket_server_side_encryption_configuration` | Enforces AES256 encryption at rest             |
| `s3.tf`         | `aws_s3_bucket_lifecycle_configuration`              | Glacier transition (90d) + expiration (365d)   |
| `cloudwatch.tf` | `aws_cloudwatch_metric_alarm.rds_high_cpu`           | RDS CPU ≥ 80% for 2 periods                     |
| `cloudwatch.tf` | `aws_cloudwatch_log_group.data_lake_audit_log`       | Audit log group, 30-day retention              |

---

## Prerequisites

- [Terraform CLI](https://developer.hashicorp.com/terraform/install) `>= 1.5.0`
- An AWS account with permissions to create VPC, S3, and CloudWatch resources
- AWS credentials configured locally (e.g. via `aws configure`, environment variables, or an SSO profile)

---

## Getting Started

From the repository root:

```bash
cd terraform

# Download provider plugins and initialize the working directory
terraform init

# Check syntax and internal consistency
terraform validate

# Preview the execution plan without applying changes
terraform plan
```

To provision the infrastructure:

```bash
terraform apply
```

### Supplying the database password

The `db_password` variable is `sensitive` and has no default. Provide it using **one** of these approaches (never commit a real value):

```bash
# Option A — environment variable (recommended for CI)
export TF_VAR_db_password='your-strong-secret'   # PowerShell: $env:TF_VAR_db_password='your-strong-secret'
terraform apply

# Option B — local tfvars file (git-ignored)
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars, then:
terraform apply
```

> `*.tfvars` files are git-ignored so secrets stay out of version control.

> ⚠️ The S3 bucket name in `s3.tf` must be **globally unique**. Update `bucket` in `aws_s3_bucket.analytics_data_lake` before applying if the default name is already taken.

---

## Configuration Reference

Key values are currently hard-coded in the Terraform files. Common adjustments:

| Setting              | File            | Current Value                            |
| -------------------- | --------------- | ---------------------------------------- |
| AWS region           | `provider.tf`   | `eu-west-2`                              |
| DB username          | `variables.tf`  | `ledger_admin`                           |
| DB password          | `variables.tf`  | _required, `sensitive` (no default)_     |
| VPC CIDR             | `vpc.tf`        | `10.0.0.0/16`                            |
| Private subnet A CIDR| `vpc.tf`        | `10.0.1.0/24` (`eu-west-2a`)             |
| Private subnet B CIDR| `rds.tf`        | `10.0.2.0/24` (`eu-west-2b`)             |
| RDS engine / version | `rds.tf`        | `postgres` `15.4`                        |
| RDS instance class   | `rds.tf`        | `db.t4g.micro`                           |
| RDS storage          | `rds.tf`        | `20` GB (autoscaling to `100` GB)        |
| S3 bucket name       | `s3.tf`         | `enterprise-analytics-data-lake-jolaboy` |
| Glacier transition   | `s3.tf`         | `90` days                                |
| Object expiration    | `s3.tf`         | `365` days                               |
| CPU alarm threshold  | `cloudwatch.tf` | `80`%                                    |
| Log retention        | `cloudwatch.tf` | `30` days                                |

For repeatable environments, consider promoting these to Terraform **input variables** (`variables.tf`) — see the [Roadmap](#roadmap).

---

## Cleanup

To tear down all provisioned resources and avoid ongoing charges:

```bash
cd terraform
terraform destroy
```

---

## Roadmap

- [x] Add the `aws_db_instance` (RDS PostgreSQL) resource with a multi-AZ subnet group.
- [x] Move the RDS password out of plaintext into a `sensitive` variable.
- [ ] Store the password in AWS Secrets Manager and reference it at runtime.
- [ ] Extract remaining hard-coded values into `variables.tf` with sensible defaults.
- [ ] Enable RDS Multi-AZ standby and automated backups (currently `skip_final_snapshot = true`).
- [ ] Wire the CloudWatch alarm to an SNS topic for notifications.
- [ ] Enable S3 access logging and bucket public-access blocking.
- [ ] Add a remote Terraform backend (e.g. S3 + DynamoDB state locking).

