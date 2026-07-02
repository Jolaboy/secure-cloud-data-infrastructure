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
   ┌────────────┴─────────────────────────────────┐
   │  Custom VPC  (10.0.0.0/16)                    │
   │                                               │
   │   ┌───────────────────────────────────────┐  │
   │   │  Private Subnet  (10.0.1.0/24, AZ 2a)  │  │
   │   │                                        │  │
   │   │   [ RDS Postgres ]  ← SG: 5432 from    │  │
   │   │        │              VPC CIDR only     │  │
   │   └────────┼───────────────────────────────┘  │
   └────────────┼──────────────────────────────────┘
                │ (audit / access logs)
                ▼
   [ S3 Data Lake ]  ──(90 days)──►  [ Glacier ]  ──(365 days)──►  [ Expiration ]
        AES256 SSE          cold archival tier         compliance purge

   [ CloudWatch ]  → RDS CPU alarm (≥ 80%)  +  Audit log group (30-day retention)
```

> **Note:** The network and monitoring layers are provisioned to host and observe an Amazon RDS PostgreSQL instance (security group on port `5432`, CPU alarm on `DBInstanceIdentifier = production-ledger-db`). The RDS instance itself is **not** created by this configuration yet — see the [Roadmap](#roadmap).

---

## Repository Structure

```text
secure-cloud-data-infrastructure/
├── terraform/
│   ├── provider.tf      # AWS provider and Terraform version constraints
│   ├── vpc.tf           # VPC, isolated private subnet, and security group
│   ├── s3.tf            # Encrypted data lake and Glacier lifecycle rules
│   └── cloudwatch.tf    # CloudWatch metric alarm and audit log group
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

> ⚠️ The S3 bucket name in `s3.tf` must be **globally unique**. Update `bucket` in `aws_s3_bucket.analytics_data_lake` before applying if the default name is already taken.

---

## Configuration Reference

Key values are currently hard-coded in the Terraform files. Common adjustments:

| Setting              | File            | Current Value                            |
| -------------------- | --------------- | ---------------------------------------- |
| AWS region           | `provider.tf`   | `eu-west-2`                              |
| VPC CIDR             | `vpc.tf`        | `10.0.0.0/16`                            |
| Private subnet CIDR  | `vpc.tf`        | `10.0.1.0/24`                            |
| Availability zone    | `vpc.tf`        | `eu-west-2a`                             |
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

- [ ] Add the `aws_db_instance` (RDS PostgreSQL) resource the network and alarm layers are designed for.
- [ ] Extract hard-coded values into `variables.tf` with sensible defaults.
- [ ] Add a second availability zone / subnet for high availability.
- [ ] Wire the CloudWatch alarm to an SNS topic for notifications.
- [ ] Enable S3 access logging and bucket public-access blocking.
- [ ] Add a remote Terraform backend (e.g. S3 + DynamoDB state locking).

