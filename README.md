# DevSecOps2k26 – GitHub OIDC → HashiCorp Vault → AWS STS → Terraform

This project demonstrates a modern DevSecOps authentication pattern where GitHub Actions authenticates to HashiCorp Vault using GitHub OIDC (OpenID Connect), and Vault dynamically generates temporary AWS credentials using AWS STS for Terraform deployments.

This approach eliminates:

- Long-lived AWS Access Keys
- AWS credentials stored in GitHub Secrets
- Static IAM user credentials
- Hardcoded cloud credentials in source code

Instead, authentication is performed through short-lived, dynamically generated credentials following **Zero Trust** and **Least Privilege** principles.

---

## Architecture

```text
GitHub Actions
      │
      │ OIDC JWT Token
      ▼
HashiCorp Vault
(JWT Authentication)
      │
      │ AWS Secrets Engine
      ▼
AWS STS AssumeRole
      │
      ▼
Temporary AWS Credentials
      │
      ▼
Terraform Deployment
      │
      ▼
AWS Infrastructure
```

---

## Repository Structure

```text
DevSecOps2k26/
│
├── .github/
│   └── workflows/
│       └── terraform.yml
│
├── terraform/
│   └── s3bucket/
│       ├── main.tf
│       ├── provider.tf
│       ├── versions.tf
│       └── outputs.tf
│
└── README.md
```

---

## Prerequisites

Before starting, ensure the following resources are available:

- AWS Account
- GitHub Repository
- Ubuntu EC2 Instance
- Terraform
- HashiCorp Vault
- IAM Roles
- Security Groups
- Domain Name (Recommended)
- TLS Certificates

---

## Step 1 – Launch Vault EC2 Server

Launch an Ubuntu EC2 instance with the following recommended specifications:

| Setting | Value |
|---|---|
| AMI | Ubuntu 22.04 LTS |
| Instance Type | t3.small or larger |
| Storage | 20 GB GP3 |
| Network | Private Subnet Preferred |
| IAM Role | VaultEC2Role |

### Security Group Rules

**Inbound**

| Port | Protocol | Source |
|---|---|---|
| 22 | TCP | Admin IP Only |
| 8200 | TCP | GitHub Actions / ALB |
| 8201 | TCP | Vault Cluster Nodes |

**Outbound:** Allow all outbound traffic.

---

## Step 2 – Install HashiCorp Vault

Update the server:

```bash
sudo apt update -y
sudo apt upgrade -y
```

Install dependencies:

```bash
sudo apt install unzip wget curl jq -y
```

Download and install Vault:

```bash
wget https://releases.hashicorp.com/vault/1.15.5/vault_1.15.5_linux_amd64.zip
unzip vault_1.15.5_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault version
```

---

## Step 3 – Create Vault Directories

```bash
sudo mkdir -p /opt/vault/data
sudo mkdir -p /etc/vault.d

sudo chown -R ubuntu:ubuntu /opt/vault
sudo chown -R ubuntu:ubuntu /etc/vault.d
```

---

## Step 4 – Configure Vault Storage

Create the Vault configuration file:

```bash
sudo nano /etc/vault.d/vault.hcl
```

```hcl
ui = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault.d/fullchain.pem"
  tls_key_file  = "/etc/vault.d/privkey.pem"
}

storage "raft" {
  path = "/opt/vault/data"
}

api_addr     = "https://vault.example.com:8200"
cluster_addr = "https://vault.example.com:8201"
```

---

## Step 5 – Create Vault Systemd Service

```bash
sudo nano /etc/systemd/system/vault.service
```

```ini
[Unit]
Description=HashiCorp Vault
After=network.target

[Service]
User=ubuntu
Group=ubuntu

ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl

Restart=on-failure
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault
```

---

## Step 6 – Initialize Vault

```bash
export VAULT_ADDR=https://vault.example.com:8200
vault operator init
```

Example output:

```text
Unseal Key 1: xxxxxxxxx
Unseal Key 2: xxxxxxxxx
Unseal Key 3: xxxxxxxxx

Initial Root Token: hvs.xxxxxxxxx
```

> Store these securely — loss of unseal keys means permanent data loss.

---

## Step 7 – Unseal Vault

```bash
vault operator unseal   # run three times with three different keys
vault login             # provide root token
```

---

## Step 8 – Create AWS IAM Role for Vault (VaultEC2Role)

Create an IAM role named `VaultEC2Role` and attach it to the EC2 instance.

Attach the following inline policy to allow Vault to assume the Terraform deployment role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/VaultTerraformRole"
    }
  ]
}
```

---

## Step 9 – Create Terraform Deployment Role (VaultTerraformRole)

Create an IAM role named `VaultTerraformRole`.

**Trust relationship** — allow `VaultEC2Role` to assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<ACCOUNT_ID>:role/VaultEC2Role"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Permissions policy** — attach the required Terraform permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": "*"
    }
  ]
}
```

---

## Step 10 – Enable AWS Secrets Engine

```bash
vault secrets enable aws

# Vault automatically uses the EC2 IAM Role (VaultEC2Role) — no keys required
vault write aws/config/root \
    region=us-east-1

vault read aws/config/root
```

---

## Step 11 – Create AWS STS Role in Vault

```bash
vault write aws/roles/terraform-role \
    credential_type=assumed_role \
    role_arn="arn:aws:iam::<ACCOUNT_ID>:role/VaultTerraformRole"

vault read aws/roles/terraform-role
```

---

## Step 12 – Enable JWT Authentication

```bash
vault auth enable jwt

vault write auth/jwt/config \
    oidc_discovery_url="https://token.actions.githubusercontent.com" \
    bound_issuer="https://token.actions.githubusercontent.com"

vault read auth/jwt/config
```

---

## Step 13 – Create Vault Policy

```bash
vault policy write terraform-policy - <<EOF
path "aws/sts/terraform-role" {
  capabilities = ["read"]
}
EOF

vault policy list
```

---

## Step 14 – Create GitHub JWT Role

```bash
vault write auth/jwt/role/github-actions - <<EOF
{
  "role_type": "jwt",
  "bound_audiences": ["https://github.com/AyazRahim"],
  "user_claim": "sub",
  "bound_claims_type": "glob",
  "bound_claims": {
    "sub": "repo:AyazRahim/DevSecOps2k26:*"
  },
  "token_policies": ["terraform-policy"],
  "token_ttl": "15m"
}
EOF
```

> For tighter security, restrict to `main` only:
> `"sub": "repo:AyazRahim/DevSecOps2k26:ref:refs/heads/main"`

---

## Step 15 – Terraform Configuration

Files are located in `terraform/s3bucket/`.

**`versions.tf`**
```hcl
terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

**`provider.tf`**
```hcl
provider "aws" {
  region = "us-east-1"
  # Credentials injected at runtime via AWS_ACCESS_KEY_ID,
  # AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN env vars
}
```

**`main.tf`**
```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "demo" {
  bucket = "vault-demo-bucket-${random_id.bucket_suffix.hex}"
}
```

**`outputs.tf`**
```hcl
output "bucket_name" {
  description = "Name of the S3 bucket created"
  value       = aws_s3_bucket.demo.bucket
}
```

---

## Step 16 – GitHub Actions Workflow

File: `.github/workflows/terraform.yml`

```yaml
name: Terraform Deployment

on:
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    defaults:
      run:
        working-directory: terraform/s3bucket

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to Vault
        uses: hashicorp/vault-action@v3
        with:
          url: https://vault.example.com:8200
          method: jwt
          role: github-actions
          secrets: |
            aws/sts/terraform-role access_key       | AWS_ACCESS_KEY_ID ;
            aws/sts/terraform-role secret_key       | AWS_SECRET_ACCESS_KEY ;
            aws/sts/terraform-role security_token   | AWS_SESSION_TOKEN

      - uses: hashicorp/setup-terraform@v3

      - run: terraform init
      - run: terraform validate
      - run: terraform plan
      - run: terraform apply -auto-approve
```

---

## Verification

```bash
# Verify JWT role
vault read auth/jwt/role/github-actions

# Verify policy
vault policy read terraform-policy

# Verify AWS Vault role
vault read aws/roles/terraform-role
```

Then trigger a push to `main` and check **Actions → Terraform Deployment**.

---

## Security Best Practices Implemented

- ✅ GitHub OIDC Authentication
- ✅ No AWS Access Keys
- ✅ No GitHub Secrets
- ✅ Dynamic AWS Credentials
- ✅ AWS STS Temporary Credentials
- ✅ Vault JWT Authentication
- ✅ Least Privilege IAM
- ✅ Terraform Automation
- ✅ Short-Lived Vault Tokens (15m)
- ✅ Secure Role-Based Access Control

---

## Future Enhancements

- AWS KMS Auto Unseal
- Vault HA Cluster
- Integrated Storage Raft Cluster
- Private ALB Access
- WAF Protection
- Terraform Remote Backend
- Checkov Scanning
- Trivy Scanning
- Gitleaks Secret Detection
- GitHub Branch Protection Rules
- CloudTrail Monitoring
- AWS Security Hub Integration
- Centralized Audit Logging

---

## Author

**Ayaz Rahim**

DevOps Engineer | DevSecOps Practices | Kubernetes | Terraform | AWS | Azure | CI/CD Automation | DevSecOps
