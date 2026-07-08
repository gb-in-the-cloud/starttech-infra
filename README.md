# StartTech Infrastructure

A production-grade AWS cloud infrastructure provisioned entirely with Terraform modules and deployed automatically via a GitHub Actions CI/CD pipeline. The infrastructure supports a full-stack application with a containerized backend on EKS, static frontend hosting on S3 via CloudFront, and Redis caching via ElastiCache.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [AWS Resources](#3-aws-resources)
4. [Prerequisites](#4-prerequisites)
5. [Project Structure](#5-project-structure)
6. [Terraform Modules](#6-terraform-modules)
7. [Naming Conventions](#7-naming-conventions)
8. [Architectural Solutions](#8-architectural-solutions)
9. [CI/CD Pipeline](#9-cicd-pipeline)
10. [Deploy Script](#10-deploy-script)
11. [Getting Started](#11-getting-started)
12. [GitHub Secrets](#12-github-secrets)
13. [Deployed Resources](#13-deployed-resources)
14. [Cleanup](#14-cleanup)

---

## 1. Project Overview

This project provisions the complete cloud infrastructure for the StartTech platform on AWS `eu-west-3` (Paris) using infrastructure-as-code best practices:

- **Modular Terraform** — five independent modules (networking, EKS, storage, CDN, database)
- **Remote State** — Terraform state stored in S3 (`starttech-tfstate-paris-2026`) for team collaboration
- **GitHub Actions CI/CD** — automated validate, plan, and apply pipeline with production environment protection
- **Security** — private subnets, security groups with least-privilege rules, S3 public access blocked, CloudFront OAC
- **SPA Support** — CloudFront configured to handle React/Vue client-side routing
- **Mixed Content Prevention** — single CloudFront distribution proxying both frontend and backend API

---

## 2. Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│              CloudFront Distribution                        │
│         dc5f1xv5b6hrf.cloudfront.net                       │
│                                                             │
│   /* ──────────────────► S3 Bucket (Frontend)              │
│   Default behavior          starttech-frontend-bucket       │
│   HTTP → HTTPS redirect     OAC secured                    │
│   Cache: 1 hour             index.html (SPA routing)       │
│                                                             │
│   /api/* ──────────────► ALB → EKS (Backend API)           │
│   Ordered behavior          Port 8080                      │
│   Cache: disabled (TTL=0)   All headers forwarded          │
│   All cookies forwarded     All query strings forwarded    │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    AWS VPC (eu-west-3)                      │
│                    vpc-02e7892abaa606a55                    │
│                    10.0.0.0/16                              │
│                                                             │
│  Public Subnets                                             │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ subnet-03f9860414a   │  │ subnet-0bd27145946f  │        │
│  │ 10.0.1.0/24          │  │ 10.0.2.0/24          │        │
│  │ eu-west-3a           │  │ eu-west-3b           │        │
│  │ NAT Gateway          │  │ NAT Gateway          │        │
│  └──────────────────────┘  └──────────────────────┘        │
│                                                             │
│  Private Subnets                                            │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ subnet-04da087a71a   │  │ subnet-00dbe09e549   │        │
│  │ 10.0.11.0/24         │  │ 10.0.12.0/24         │        │
│  │ eu-west-3a           │  │ eu-west-3b           │        │
│  │ EKS Node             │  │ EKS Node             │        │
│  └──────────────────────┘  └──────────────────────┘        │
│                                                             │
│  ElastiCache Redis                                          │
│  starttech-redis (private subnets only)                    │
└─────────────────────────────────────────────────────────────┘
```

### Traffic Flow

```
User Browser
    │ HTTPS
    ▼
CloudFront (dc5f1xv5b6hrf.cloudfront.net)
    │
    ├── /* ──────────► S3 (starttech-frontend-bucket-paris-2026)
    │                  React/Vue SPA assets
    │
    └── /api/* ──────► ALB → EKS Worker Nodes (starttech-cluster)
                       Go/Node.js Backend API (port 8080)
                            │
                            ▼
                       ElastiCache Redis
                       (starttech-redis)
```

---

## 3. AWS Resources

| Module            | Resource                           |             Name/ID                         | Region |
|---|---|---|---|
| Networking        | VPC                                | `starttech-vpc` / `vpc-02e7892abaa606a55`   | eu-west-3  |
| Networking        | Public Subnet 1                    | `10.0.1.0/24`                               | eu-west-3a |
| Networking        | Public Subnet 2                    | `10.0.2.0/24`                               | eu-west-3b |
| Networking        | Private Subnet 1                   | `10.0.11.0/24`                              | eu-west-3a |
| Networking        | Private Subnet 2                   | `10.0.12.0/24`                              | eu-west-3b |
| Networking        | NAT Gateway | 2x (one per AZ)      |                                             | eu-west-3  |
| Networking        |Internet Gateway                    | `igw-055ce955a672c7f22`                     | eu-west-3  | 
| EKS               | Cluster                            | `starttech-cluster`                         | eu-west-3  |
| EKS               | Node Group                         | `starttech-node-group` (2x t3.small)        | eu-west-3  |
| EKS               | IAM Role (Control Plane)           | `starttechcluster`                          | Global     |
| EKS               | IAM Role (Node Group)              | `starttech-node-group`                      | Global     |
| Storage           | S3 Bucket                          | `starttech-frontend-bucket-paris-2026`      | eu-west-3  |
| Storage           | ECR Repository                     | `starttech-backend-api`                     | eu-west-3  |
| CDN               | CloudFront                         | `dc5f1xv5b6hrf.cloudfront.net`              | Global     |
| CDN               | Origin Access Control              | `starttech-oac`                             | Global     |
| Database          | ElastiCache Redis                  | `starttech-redis` (cache.t3.micro)          | eu-west-3  |
| State             | S3 State Bucket                    | `starttech-tfstate-paris-2026`              | eu-west-3  |

---

## 4. Prerequisites

### Local Tools Required

```bash
terraform --version   # >= 1.6.0
aws --version         # >= 2.0
kubectl               # for EKS cluster access
git --version
```

### AWS Configuration

```bash
# Configure credentials
aws configure

# Verify identity
aws sts get-caller-identity

# Set region
aws configure set region eu-west-3
```

---

## 5. Project Structure

```
starttech-infra/
├── .github/
│   └── workflows/
│       └── infrastructure-deploy.yml   # CI/CD pipeline
├── terraform/
│   ├── main.tf                         # Root module — calls all child modules
│   ├── variables.tf                    # Root variable definitions
│   ├── outputs.tf                      # Root output values
│   ├── terraform.tfvars                # Real values (git-ignored)
│   ├── terraform.tfvars.example        # Safe template (committed)
│   └── modules/
│       ├── networking/                 # VPC, subnets, NAT, IGW, route tables
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── eks/                        # EKS cluster, node group, IAM, access entries
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── storage/                    # S3 bucket, ECR repository
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── cdn/                        # CloudFront distribution, OAC, S3 policy
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── database/                   # ElastiCache Redis cluster
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── scripts/
│   └── deploy-infra.sh                 # Local deployment script
├── .gitignore
└── README.md
```

---

## 6. Terraform Modules

### Networking Module

Creates the VPC and all network components. Subnets are tagged for Kubernetes compatibility:

```hcl
# Public subnets — ALB and NAT Gateways
kubernetes.io/role/elb = "1"

# Private subnets — EKS worker nodes
kubernetes.io/role/internal-elb = "1"
```

Key resources: VPC, 2 public subnets, 2 private subnets, Internet Gateway, 2 NAT Gateways (one per AZ for HA), route tables.

---

### EKS Module

Provisions a managed Kubernetes cluster with least-privilege IAM:

| IAM Policy                               | Attached To        |---|---|
| `AmazonEKSClusterPolicy`                 | Control Plane Role |
| `AmazonEKSWorkerNodePolicy`              | Node Group Role    |
| `AmazonEC2ContainerRegistryReadOnly`     | Node Group Role    |
| `AmazonEKS_CNI_Policy`                   | Node Group Role    |

Also configures EKS Access Entries for the CI/CD IAM user so GitHub Actions can run `kubectl` commands post-deploy.

---

### Storage Module

S3 bucket with full security hardening:

- ✅ All public access blocked (`aws_s3_bucket_public_access_block`)
- ✅ Server-side encryption (AES256)
- ✅ Versioning enabled (for deployment rollbacks)
- ✅ Bucket owner enforced (ACLs disabled)

ECR repository:
- ✅ Vulnerability scanning on every push
- ✅ Lifecycle policy — keeps last 10 images

---

### CDN Module

Single CloudFront distribution acting as a unified reverse proxy:

**Origin 1 — S3 Frontend:**
- Origin ID: `S3-Frontend` (exact — required for grading)
- Access: Origin Access Control (OAC) — modern replacement for OAI
- Signing: `sigv4`, always

**Origin 2 — ALB Backend:**
- Origin ID: `ALB-Backend` (exact — required for grading)
- Protocol: HTTP to ALB, HTTPS to users
- Phase 1: `placeholder.example.com` (updated to real ALB in Phase 2)

**Cache Behaviors:**

| Pattern | Target | Cache | Headers |
|---|---|---|---|
| `/*` (default) | S3-Frontend | 1 hour | None |
| `/api/*` (ordered) | ALB-Backend | Disabled (TTL=0) | All forwarded |

**Custom Error Responses:**

| Error | Response | Path |
|---|---|---|
| 403 | 200 OK | `/index.html` |
| 404 | 200 OK | `/index.html` |

---

### Database Module

Single-node ElastiCache Redis cluster:

- Cluster ID: `starttech-redis` (exact — required for grading)
- Node type: `cache.t3.micro`
- Port: `6379`
- Eviction policy: `allkeys-lru`
- Access: restricted to EKS worker node security group only
- Snapshots: 1-day retention, window 03:00-04:00 UTC

---

## 7. Naming Conventions

The following identifiers are required for automated grading validation:

| Resource                  | Required Identifier            |    
| VPC Name Tag              | `starttech-vpc`                |
| EKS Cluster Name          | `starttech-cluster`            |
| EKS Node Group            | `starttech-node-group`         |
| S3 Bucket                 | `starttech-frontend-bucket`    |
| ElastiCache Cluster       | `starttech-redis`              |
| ECR Repository            | `starttech-backend-api`        |
| CloudFront S3 Origin ID   | `S3-Frontend`                  |
| CloudFront ALB Origin ID  | `ALB-Backend`                  |
| Container Port            | `8080`                          |

---

## 8. Architectural Solutions

### Solution 1 — SPA Client-Side Routing

**Problem:** React/Vue SPAs manage routing client-side. When a user refreshes on `/dashboard`, S3 looks for a physical file at that path, finds nothing, and returns `403 Forbidden` or `404 Not Found`.

**Solution:** CloudFront intercepts `403` and `404` errors from S3 and rewrites them to return `/index.html` with HTTP `200 OK`. The React router then parses the URL and renders the correct view.

```hcl
custom_error_response {
  error_code            = 404
  response_code         = 200
  response_page_path    = "/index.html"
  error_caching_min_ttl = 0
}

custom_error_response {
  error_code            = 403
  response_code         = 200
  response_page_path    = "/index.html"
  error_caching_min_ttl = 0
}
```

---

### Solution 2 — Eliminating HTTPS Mixed Content

**Problem:** The ALB operates over HTTP. Modern browsers block HTTP requests made from HTTPS pages (Mixed Content Security Policy). Without a solution, the frontend cannot call the backend API.

**Solution:** Both frontend and API are served through a single CloudFront HTTPS domain. The frontend makes relative API calls (`/api/v1/resource`) which CloudFront routes internally to the ALB over HTTP — the browser never sees the HTTP connection.

```
# Without solution ❌
Frontend: https://d1234.cloudfront.net   (HTTPS)
API call: http://alb-xxx.amazonaws.com   (HTTP — BLOCKED)

# With solution ✅
Frontend: https://d1234.cloudfront.net/          (HTTPS)
API call: https://d1234.cloudfront.net/api/v1/   (HTTPS — same domain)
CloudFront → ALB over HTTP internally            (invisible to browser)
```

---

## 9. CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/infrastructure-deploy.yml`) automates the full deployment lifecycle.

### Triggers

| Event | Jobs Run |
|---|---|
| Push to `main` | Validate → Plan → Apply |
| Pull Request to `main` | Validate → Plan (posts output as PR comment) |
| Manual (`workflow_dispatch`) | Validate → Plan → Apply or Destroy |

### Pipeline Flow

```
Push to main
      │
      ▼
┌─────────────────────┐
│  Job 1: Validate    │  terraform fmt -check
│                     │  terraform validate
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Job 2: Plan        │  terraform plan -out=tfplan
│                     │  posts plan as PR comment
│                     │  uploads tfplan artifact
└──────────┬──────────┘
           │ (main push only)
           ▼
┌─────────────────────┐
│  Job 3: Apply       │  requires production environment approval
│                     │  terraform apply tfplan
│                     │  aws eks update-kubeconfig
│                     │  kubectl get nodes
│                     │  prints deployment summary
└─────────────────────┘

Manual only:
┌─────────────────────┐
│  Job 4: Destroy     │  requires production environment approval
│                     │  terraform destroy
└─────────────────────┘
```

### Production Environment Protection

The `apply` and `destroy` jobs use a GitHub **production environment** with required reviewer approval. No infrastructure changes are applied automatically without human sign-off.

---

## 10. Deploy Script

`scripts/deploy-infra.sh` provides a convenient local deployment interface with preflight checks, colored output, timestamped logs, and confirmation prompts.

```bash
# Make executable
chmod +x scripts/deploy-infra.sh

# Available commands
./scripts/deploy-infra.sh init     # terraform init
./scripts/deploy-infra.sh plan     # fmt check + validate + plan
./scripts/deploy-infra.sh apply    # plan + apply + kubectl verify
./scripts/deploy-infra.sh destroy  # destroy with confirmation
```

### Features

- Preflight checks for Terraform, AWS CLI, credentials, and kubectl
- Auto-formats files if `terraform fmt` fails
- Saves timestamped log to project root
- Confirmation prompt before apply and destroy
- Configures kubectl automatically after successful apply
- Prints deployment summary with CloudFront, EKS, and Redis endpoints

---

## 11. Getting Started

### Step 1 — Clone the Repository

```bash
git clone https://github.com/gb-in-the-cloud/starttech-infra.git
cd starttech-infra
```

### Step 2 — Create Terraform State Bucket

```bash
aws s3api create-bucket \
  --bucket starttech-tfstate-YOUR_UNIQUE_ID \
  --region eu-west-3 \
  --create-bucket-configuration LocationConstraint=eu-west-3

aws s3api put-bucket-versioning \
  --bucket starttech-tfstate-YOUR_UNIQUE_ID \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket starttech-tfstate-YOUR_UNIQUE_ID \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### Step 3 — Configure Variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
nano terraform/terraform.tfvars
```

```hcl
aws_region             = "eu-west-3"
project_name           = "starttech"
environment            = "prod"
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs   = ["10.0.*.0/24", "10.0.*.0/24"]
availability_zones     = ["eu-west-3a", "eu-west-3b"]
eks_cluster_version    = "1.34"
eks_node_instance_type = "t3.small"
eks_node_desired_size  = 2
eks_node_min_size      = 2
eks_node_max_size      = 4
s3_bucket_name         = "starttech-frontend-bucket-YOUR_UNIQUE_ID"
redis_node_type        = "cache.t3.micro"
alb_dns_name           = "placeholder.example.com"
```

### Step 4 — Update Backend Configuration

In `terraform/main.tf` update the backend bucket name:

```hcl
backend "s3" {
  bucket = "starttech-tfstate-YOUR_UNIQUE_ID"
  key    = "starttech/terraform.tfstate"
  region = "eu-west-3"
}
```

### Step 5 — Deploy

```bash
chmod +x scripts/deploy-infra.sh
./scripts/deploy-infra.sh init
./scripts/deploy-infra.sh plan
./scripts/deploy-infra.sh apply
```

---

## 12. GitHub Secrets

Configure these in both **Settings → Secrets → Actions** and **Settings → Environments → production**:

| Secret                      | Description            | Value                                         |
| `AWS_ACCESS_KEY_ID`         | AWS access key         | `AKIA...`                                     |
| `AWS_SECRET_ACCESS_KEY`     | AWS secret key         | `...`                                         |
| `AWS_REGION`                | Deployment region      | `eu-west-3`                                   |
| `TF_STATE_BUCKET`           | Terraform state bucket | `starttech-tfstate-paris-2026`                |
| `S3_BUCKET_NAME`            | Frontend S3 bucket     | `starttech-frontend-bucket-paris-2026`        |
| `ALB_DNS_NAME`              | ALB DNS (placeholder → real after Phase 2) | `placeholder.example.com` |

---

## 13. Deployed Resources

Current deployment outputs (eu-west-3 / Paris):

```
cloudfront_domain    = "dc5f1xv5b6hrf.cloudfront.net"
eks_cluster_name     = "starttech-cluster"
eks_cluster_endpoint = "https://A6796CBFC38705C081E270E9F43276CC.gr7.eu-west-3.eks.amazonaws.com"
redis_endpoint       = "starttech-redis.aq9jps.0001.euw3.cache.amazonaws.com"
s3_bucket_name       = "starttech-frontend-bucket-paris-2026"
vpc_id               = "vpc-02e7892abaa606a55"
```

### EKS Worker Nodes

```
NAME                                           STATUS  VERSION
ip-10-0-11-x.eu-west-3.compute.internal       Ready   v1.34.9-eks-7d6f6ec
ip-10-0-12-x.eu-west-3.compute.internal       Ready   v1.34.9-eks-7d6f6ec
```

---

## 14. Cleanup

### Stop All Running Resources

```bash
./scripts/deploy-infra.sh destroy
```

**Always run `destroy` when not actively using the infrastructure.**

---

## Security Notes

- `terraform.tfvars` is git-ignored — never commit real credentials
- S3 bucket has all public access blocked — only CloudFront OAC can read objects
- EKS worker nodes are in private subnets — no direct internet exposure
- ElastiCache Redis only accepts connections from the EKS worker node security group
- All secrets stored in GitHub Secrets — never hardcoded in workflow or Terraform files
- CloudFront enforces HTTPS for all traffic — HTTP is redirected

---

## Author

**Oluwagbenga Oyewole**
GitHub: [@gb-in-the-cloud](https://github.com/gb-in-the-cloud)

AWS Region: `eu-west-3` (Paris)
EKS Version: `1.34`
Terraform: `>= 1.6.0`