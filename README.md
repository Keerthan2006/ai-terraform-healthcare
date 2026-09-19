# AWS Infrastructure with Terraform

## Overview

This repository contains the Infrastructure as Code (IaC) implementation for the **AI Healthcare Platform**.

Terraform is used to provision and manage the AWS infrastructure required to run the platform in a reproducible, version-controlled, and environment-aware manner.

The infrastructure is designed around the following principles:

- Infrastructure as Code
- Reproducibility
- Least-privilege access
- Network isolation
- Secure container image management
- Temporary GitHub Actions AWS credentials
- Kubernetes workload isolation
- Infrastructure recovery
- Modular Terraform design
- Cost awareness

---

# Architecture

```text
                         Internet
                            |
                            v
                    +----------------+
                    |   AWS VPC      |
                    |                |
                    | Public Subnets |
                    +-------+--------+
                            |
                            v
                    +----------------+
                    | Load Balancer  |
                    +-------+--------+
                            |
                            v
                 +----------------------+
                 |   Amazon EKS Cluster |
                 |                      |
                 |  Kubernetes Workloads|
                 +----------+-----------+
                            |
          +-----------------+------------------+
          |                 |                  |
          v                 v                  v
      API Pods         AI Service Pods     Worker Pods
          |                 |                  |
          +-----------------+------------------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
       Redis / Queue                 PostgreSQL
             |
             v
        Background Jobs
             |
             v
          Mock EHR


        GitHub Actions
              |
              | OIDC
              v
      AWS IAM Role
              |
              v
             ECR
              |
              v
      Container Images
```

Terraform provisions the AWS infrastructure layer, while Kubernetes manages the application workloads.

---

# Repository Structure

```text
ai-healthcare-terraform/
│
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── backend.tf
├── terraform.tfvars
│
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── iam/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── ecr/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── eks/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

The infrastructure is divided into reusable modules so individual components can be modified without placing the entire infrastructure configuration in one large Terraform file.

---

# Terraform Module Architecture

```text
                    Terraform Root
                         |
        +----------------+----------------+
        |                |                |
        v                v                v
      VPC              IAM              ECR
        |                |                |
        +----------------+----------------+
                         |
                         v
                        EKS
                         |
                         v
                  Kubernetes Cluster
```

The main modules are:

- VPC
- IAM
- ECR
- EKS

---

# 1. VPC

The VPC provides the network boundary for the infrastructure.

The VPC architecture separates public-facing infrastructure from private infrastructure.

```text
                    VPC
                     |
          +----------+----------+
          |                     |
          v                     v
   Public Subnets        Private Subnets
          |                     |
    Load Balancer          EKS Nodes
                                |
                                v
                         Application Pods
```

## Public Subnets

Public subnets are intended for components that require controlled internet-facing connectivity, such as a load balancer.

## Private Subnets

Private subnets are used for internal infrastructure and workloads.

The objective is to avoid directly exposing internal services such as:

- AI service
- Worker
- Redis
- PostgreSQL
- Kubernetes internal services

to the public internet.

---

# 2. IAM

IAM controls which AWS resources and APIs can be accessed by users, workloads, and automation.

The infrastructure follows the principle of:

> Least privilege

IAM is used for:

- EKS cluster access
- EKS node permissions
- ECR access
- GitHub Actions authentication
- AWS service integration

---

# 3. GitHub Actions OIDC

The CI/CD pipeline uses OpenID Connect (OIDC) to authenticate GitHub Actions with AWS.

```text
GitHub Actions
      |
      | OIDC Token
      v
AWS IAM OIDC Provider
      |
      v
GitHub Actions IAM Role
      |
      v
AWS Services
```

This avoids storing permanent AWS access keys in GitHub repository secrets.

The IAM trust relationship can restrict which GitHub repository and branch can assume the role.

---

# 4. Amazon ECR

Amazon Elastic Container Registry is used as the private container image registry.

The project uses separate repositories for the application services:

```text
ai-healthcare-dev-api
ai-healthcare-dev-ai-service
ai-healthcare-dev-worker
ai-healthcare-dev-mock-ehr
```

Architecture:

```text
GitHub Actions
      |
      v
Docker Build
      |
      v
Security Scans
      |
      v
Amazon ECR
      |
      v
EKS
```

ECR provides private image storage for the application containers.

Image scanning is enabled to help identify vulnerabilities in container images.

---

# 5. Amazon EKS

Amazon EKS provides the managed Kubernetes control plane used for running the application workloads.

The application architecture consists of multiple independent services:

```text
EKS
 |
 +-- API
 |
 +-- AI Service
 |
 +-- Worker
 |
 +-- Mock EHR
 |
 +-- Redis
 |
 +-- PostgreSQL
```

Kubernetes provides:

- Service discovery
- Pod scheduling
- Health checks
- Automatic pod replacement
- Rolling deployments
- Resource management
- Workload isolation

---

# Application Architecture on Kubernetes

The application follows an asynchronous processing model.

```text
                         Client
                           |
                           v
                         API
                           |
                 +---------+---------+
                 |                   |
                 v                   v
             AI Service          Redis Queue
                                     |
                                     v
                                   Worker
                                     |
                                     v
                                  Mock EHR
                                     |
                                     v
                                 PostgreSQL
```

## API

The API is the primary application entry point.

Responsibilities include:

- Accepting requests
- Creating jobs
- Placing jobs into Redis
- Reading job state
- Providing health endpoints
- Exposing application metrics

## AI Service

The AI service represents an internal AI/agent component.

It provides a lightweight simulation of AI processing rather than a production healthcare AI system.

## Redis

Redis acts as the background job queue.

The API places jobs into Redis and the worker consumes them asynchronously.

## Worker

The worker processes queued jobs.

Responsibilities include:

- Reading jobs from Redis
- Processing jobs
- Calling the Mock EHR
- Updating PostgreSQL
- Retrying failed jobs
- Exposing worker metrics

## PostgreSQL

PostgreSQL stores persistent application and job state.

A persistent volume is used so database state is not tied to the lifetime of a container.

## Mock EHR

The Mock EHR represents an external healthcare dependency.

It allows the project to simulate successful communication and EHR failures without connecting to a real healthcare system.

---

# Security Architecture

Security is implemented at multiple layers.

```text
                 Security Layers
                       |
       +---------------+---------------+
       |               |               |
       v               v               v
   Network          Identity       Containers
   Security          Security        Security
       |               |               |
       v               v               v
     VPC              IAM          Non-root
   Subnets           OIDC         containers
  Isolation       Least Privilege
                       |
                       v
                 CI/CD Security
                       |
          +------------+------------+
          |            |            |
          v            v            v
       Gitleaks     SonarCloud     Trivy
```

---

# Network Security

The intended traffic flow is:

```text
Internet
   |
   v
Controlled Entry Point
   |
   v
API
   |
   +--> Internal AI Service
   |
   +--> Redis Queue
          |
          v
        Worker
          |
          v
       Mock EHR
          |
          v
      PostgreSQL
```

Internal services should not be exposed directly to the public internet.

Examples include:

- Redis
- PostgreSQL
- Worker
- AI service
- Internal service endpoints

---

# Container Security

Application containers use non-root execution where compatible with the image.

Example Kubernetes security controls:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

Application containers can use dedicated application users rather than running application processes as root.

Example:

```dockerfile
RUN useradd --create-home --uid 10001 appuser
USER 10001
```

Security hardening should remain compatible with the base image. Third-party images should not be given incompatible settings that prevent the service from starting.

---

# Secret Management

Secrets should not be committed to Git.

Local environment files such as:

```text
.env
```

are excluded from version control.

Application configuration is injected at runtime.

Examples include:

```text
POSTGRES_PASSWORD
POSTGRES_USER
POSTGRES_DB
```

Sensitive configuration should be provided through appropriate runtime secret mechanisms rather than hardcoded in source code or container images.

---

# CI/CD Security

The CI/CD pipeline performs multiple validation and security checks.

```text
Git Push
   |
   v
Gitleaks
   |
   v
Python Tests
   |
   v
Ruff
   |
   v
SonarCloud
   |
   v
Docker Build
   |
   v
Trivy
   |
   v
ECR Push
   |
   v
Helm Image Update
```

---

# Gitleaks

Gitleaks searches the repository for accidentally committed secrets.

Examples include:

- API keys
- Tokens
- Passwords
- Cloud credentials

A detected secret should cause the security stage to fail.

---

# SonarCloud

SonarCloud is used for static analysis.

It helps identify:

- Code quality issues
- Potential bugs
- Maintainability issues
- Security-related code findings

Each service can have its own SonarCloud project.

---

# Trivy

Trivy scans container images for vulnerabilities.

The pipeline is configured to fail when high or critical vulnerabilities are detected according to the configured scan policy.

This creates a deployment safety gate before images are pushed to the registry.

---

# Terraform State

Terraform state records the resources managed by Terraform.

A remote backend can provide:

- Centralized state
- State locking
- Collaboration support
- Reduced risk of local state loss

The exact backend configuration should be treated as authoritative in `backend.tf`.

---

# Terraform Workflow

The normal Terraform workflow is:

```text
Write Terraform
      |
      v
terraform fmt
      |
      v
terraform init
      |
      v
terraform validate
      |
      v
terraform plan
      |
      v
Review Changes
      |
      v
terraform apply
      |
      v
AWS Infrastructure
```

For infrastructure removal:

```bash
terraform destroy
```

---

# Reproducibility

Terraform makes infrastructure reproducible.

Instead of manually creating:

- VPCs
- Subnets
- IAM roles
- ECR repositories
- EKS clusters

the infrastructure is defined as code.

A new environment can therefore be created using the Terraform configuration and appropriate variables.

---

# Environment Awareness

Environment-specific values should be provided through variables.

Examples include:

```text
environment
region
cluster name
subnet configuration
instance configuration
repository configuration
```

The same module structure can therefore be reused for different environments.

```text
dev
 |
 +-- VPC
 +-- ECR
 +-- IAM
 +-- EKS


production-like
 |
 +-- VPC
 +-- ECR
 +-- IAM
 +-- EKS
```

---

# Infrastructure Recovery

Terraform supports infrastructure recovery.

If infrastructure is accidentally removed or needs to be recreated, Terraform can reconstruct the declared infrastructure.

```text
Terraform Configuration
          |
          v
       terraform plan
          |
          v
     Missing Resources
          |
          v
     terraform apply
          |
          v
 Recreated Infrastructure
```

Infrastructure recreation and persistent data recovery are separate concerns.

Terraform can recreate infrastructure, while database data requires an appropriate backup and recovery mechanism.

---

# Reliability

The infrastructure supports reliability through multiple mechanisms.

## Kubernetes Health Checks

The API uses:

```text
/health
/ready
```

These allow Kubernetes to determine whether the application is running and ready to receive traffic.

## Pod Replacement

If a worker pod fails, Kubernetes can replace it through the Deployment controller.

```text
Worker Pod
    |
    X
Failure
    |
    v
Deployment Controller
    |
    v
New Worker Pod
```

## Queue-Based Processing

Redis provides buffering between the API and worker.

```text
API
 |
 v
Redis Queue
 |
 +---- Job 1
 +---- Job 2
 +---- Job 3
 |
 v
Worker
```

This allows queue depth to be monitored during increased workload.

---

# Failure Simulation

The project supports controlled failure simulations.

## Worker Failure

The worker pod can be deleted intentionally.

Kubernetes detects the missing replica and creates a replacement.

```text
Failure
   ↓
Detection
   ↓
Replacement
   ↓
Recovery
   ↓
Verification
```

## EHR Failure

The Mock EHR can be switched into failure mode.

The worker then experiences an external dependency failure and demonstrates retry behavior using the configured maximum attempt count.

```text
Worker
   |
   v
Mock EHR
   |
   X
Failure
   |
   v
Retry
   |
   v
Retry
   |
   v
Final Failure
```

This demonstrates that an external dependency failure can be isolated from the API layer.

---

# Observability

The application exposes metrics for monitoring.

Prometheus collects metrics from:

```text
API --------\
             \
Worker -------> Prometheus
                    |
                    v
                 Grafana
```

The project monitors operational signals such as:

- API availability
- API latency
- API errors
- Queue depth
- Worker failures
- Worker retries
- Worker processing time
- CPU utilization
- Memory utilization
- Deployment state

---

# Alerting

The project includes alerts for important operational conditions.

## APIDown

Triggers when the API is unavailable.

```text
API unavailable
      |
      v
Prometheus detects condition
      |
      v
Alert
```

## HighAPILatency

Detects unusually high API response latency.

This can indicate:

- Application slowdown
- Resource pressure
- Dependency problems
- Increased workload

## QueueBacklog

Detects an increasing Redis queue depth.

This can indicate that jobs are arriving faster than workers can process them.

## WorkerJobFailures

Detects failed background jobs.

This helps identify failures in job processing or dependencies.

## WorkerRetries

Detects repeated retry activity.

A high retry rate can indicate an unstable external dependency.

## SlowWorkerProcessing

Detects unusually slow worker processing.

This can indicate:

- Increased workload
- Slow dependencies
- Resource pressure
- Application processing issues

---

# Deployment Safety

The CI/CD pipeline validates an application before deployment.

The intended flow is:

```text
Code
 |
 v
Tests
 |
 v
Security Checks
 |
 v
Docker Build
 |
 v
Image Scan
 |
 v
Container Registry
 |
 v
Deployment
 |
 v
Health Verification
```

A security failure should prevent an unsafe artifact from progressing through the deployment pipeline.

---

# Rolling Deployment

Kubernetes Deployments provide controlled application updates.

Conceptually:

```text
Old Version
     |
     v
New Version
     |
     v
Health Checks
     |
 +---+---+
 |       |
 v       v
Healthy Unhealthy
 |       |
 v       v
Continue Stop/Rollback
```

The objective is to prevent an unhealthy version from replacing a known healthy application version without validation.

---

# Cost Awareness

Potential AWS cost areas include:

- EKS
- EC2/node infrastructure
- Load balancers
- ECR storage
- NAT gateways
- S3
- CloudWatch
- Data transfer

Development environments should avoid unnecessarily large infrastructure.

Resources should be destroyed when they are no longer required:

```bash
terraform destroy
```

---

# Terraform Commands

## Initialize

```bash
terraform init
```

## Format

```bash
terraform fmt -recursive
```

## Validate

```bash
terraform validate
```

## Plan

```bash
terraform plan
```

## Apply

```bash
terraform apply
```

## Destroy

```bash
terraform destroy
```

## Show State

```bash
terraform show
```

## List Resources

```bash
terraform state list
```

---

# Security Checklist

Before deploying infrastructure:

- [ ] No secrets committed to Git
- [ ] `.env` files ignored
- [ ] IAM follows least privilege
- [ ] GitHub Actions uses OIDC
- [ ] ECR repositories are private
- [ ] Container images are scanned
- [ ] Source code is statically analyzed
- [ ] Secret scanning is enabled
- [ ] Internal services are not publicly exposed
- [ ] Kubernetes workloads use appropriate security contexts
- [ ] Health checks are configured
- [ ] Resource requests and limits are configured
- [ ] Infrastructure changes are reviewed using Terraform plan
- [ ] Backup/recovery strategy is documented
- [ ] Infrastructure can be recreated

---

# What Terraform Owns

Terraform is responsible for infrastructure such as:

```text
AWS
 |
 +-- VPC
 |    +-- Subnets
 |    +-- Networking
 |
 +-- IAM
 |    +-- Roles
 |    +-- Policies
 |    +-- GitHub OIDC
 |
 +-- ECR
 |    +-- Container repositories
 |
 +-- EKS
      +-- Kubernetes cluster infrastructure
```

Application workloads are managed separately using Kubernetes and Helm.

---

# Relationship Between Terraform, Kubernetes and CI/CD

The layers have different responsibilities.

```text
              Terraform
                  |
                  v
          AWS Infrastructure
                  |
                  v
               EKS
                  |
                  v
             Kubernetes
                  |
                  v
          Application Workloads
                  ^
                  |
             Helm / Argo CD
                  ^
                  |
             GitHub Actions
                  ^
                  |
                Git
```

### Terraform

Creates infrastructure.

### Kubernetes

Runs and manages application workloads.

### Helm

Packages and configures Kubernetes resources.

### Argo CD

Provides GitOps-based synchronization of Kubernetes configuration.

### GitHub Actions

Automates testing, security validation, container builds, image publishing, and deployment configuration updates.

---

# Security and Reliability Trade-offs

Security and reliability controls must be balanced with compatibility and operational simplicity.

Examples:

- Non-root containers reduce process privileges.
- Dropping Linux capabilities reduces unnecessary privileges.
- Private networking reduces exposure.
- Least-privilege IAM limits the blast radius of compromised credentials.
- Queue-based processing improves resilience.
- Health checks improve failure detection.
- Retries help with transient external failures.
- Excessive hardening can break third-party container images.
- Excessive retries can increase load on an unhealthy dependency.

The project therefore applies controls while preserving application functionality and operational simplicity.

---

# Project Outcome

The Terraform infrastructure provides the foundation for the AI Healthcare Platform simulation.

The resulting architecture demonstrates:

- Infrastructure as Code
- Modular Terraform
- AWS networking
- IAM and least privilege
- GitHub Actions OIDC
- Private ECR
- Kubernetes infrastructure
- Secure container deployment
- CI/CD security validation
- Application reliability
- Failure recovery
- Observability
- Infrastructure recreation
- Cost awareness

The objective is not simply to provision AWS resources, but to demonstrate how infrastructure, application delivery, security, reliability, and observability work together as one operational system.

---

# Scope

This project is an infrastructure and reliability simulation.

It does **not** represent a production healthcare platform and does not use real patient data or a real healthcare/EHR system.

The Mock EHR is used only to simulate an external dependency so that failure, retry, recovery, and observability behavior can be demonstrated safely.
