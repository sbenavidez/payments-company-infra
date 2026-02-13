# Payments Company Infrastructure

AWS CDK infrastructure code for deploying a production-ready environment with VPC, EKS cluster, and Aurora MySQL database.

## Architecture

This infrastructure includes:

- **VPC**: Multi-AZ VPC spanning 3 Availability Zones with 6 subnets (1 public and 1 private per AZ)
- **EKS Cluster**: Amazon EKS cluster (Kubernetes v1.32) with:
  - Amazon CloudWatch Observability add-on enabled
  - 2 worker nodes running on m6a.large instances
  - Private subnets for worker nodes
  - Cluster logging enabled for all components
- **Aurora MySQL**: Multi-AZ Aurora MySQL cluster (v3.08.0) with:
  - 1 Writer instance and 1 Reader instance
  - Encrypted storage
  - Automated credentials management via AWS Secrets Manager

## Prerequisites

Before deploying this infrastructure, ensure you have the following installed and configured:

### 1. AWS CLI

Install the AWS CLI v2:

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Windows (download installer)
# https://awscli.amazonaws.com/AWSCLIV2.msi
```

Configure AWS credentials:

```bash
aws configure
```

### 2. Node.js

AWS CDK requires Node.js 18.x or later:

```bash
# macOS
brew install node

# Linux (using nvm)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 20
nvm use 20
```

Verify installation:

```bash
node --version  # Should be v18.x or later
```

### 3. AWS CDK CLI

Install the AWS CDK CLI globally:

```bash
npm install -g aws-cdk
```

Verify installation:

```bash
cdk --version
```

### 4. Python

Python 3.8 or later is required:

```bash
python3 --version  # Should be 3.8 or later
```

### 5. kubectl (optional, for EKS management)

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

## Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd payments-company-infra
```

### 2. Create Python Virtual Environment

```bash
python3 -m venv .venv
```

### 3. Activate Virtual Environment

```bash
# macOS/Linux
source .venv/bin/activate

# Windows
.venv\Scripts\activate
```

### 4. Install Dependencies

```bash
pip install -r requirements.txt
```

## Deployment

### 1. Bootstrap CDK (First-time only)

If this is your first time deploying CDK in this AWS account/region, bootstrap CDK:

```bash
cdk bootstrap aws://ACCOUNT_ID/REGION
```

Replace `ACCOUNT_ID` with your AWS account ID and `REGION` with your target region (e.g., `us-east-1`).

You can find your account ID with:

```bash
aws sts get-caller-identity --query Account --output text
```

### 2. Review Changes (Optional)

Synthesize the CloudFormation template to review what will be deployed:

```bash
cdk synth
```

View the difference between the deployed stack and the local changes:

```bash
cdk diff
```

### 3. Deploy the Stack

Deploy the infrastructure:

```bash
cdk deploy
```

You will be prompted to approve the IAM policy changes. Type `y` to confirm.

**Note**: The deployment typically takes 20-30 minutes due to EKS cluster and Aurora database creation.

### 4. Configure kubectl (Post-deployment)

After deployment, configure kubectl to access the EKS cluster:

```bash
aws eks update-kubeconfig --name payments-eks-cluster --region <REGION>
```

Verify the connection:

```bash
kubectl get nodes
```

## Stack Outputs

After deployment, the following outputs will be available:

| Output | Description |
|--------|-------------|
| `VpcId` | VPC identifier |
| `EksClusterName` | EKS cluster name |
| `EksClusterEndpoint` | EKS API server endpoint |
| `EksClusterArn` | EKS cluster ARN |
| `EksKubectlCommand` | Command to configure kubectl |
| `AuroraClusterEndpoint` | Aurora MySQL writer endpoint |
| `AuroraClusterReaderEndpoint` | Aurora MySQL reader endpoint |
| `AuroraSecretArn` | ARN of the Secrets Manager secret containing database credentials |

## Accessing Aurora MySQL Credentials

The Aurora MySQL credentials are stored in AWS Secrets Manager. To retrieve them:

```bash
aws secretsmanager get-secret-value \
  --secret-id payments/aurora/credentials \
  --query SecretString \
  --output text | jq '.'
```

## Cleanup

To destroy all resources created by this stack:

```bash
cdk destroy
```

**Warning**: This will permanently delete all resources including the Aurora database. Make sure to backup any important data before destroying.

## Cost Considerations

This infrastructure will incur AWS costs for:

- **VPC**: NAT Gateways (3x for high availability)
- **EKS**: Control plane charges + EC2 instances (2x m6a.large)
- **Aurora MySQL**: Database instances (1 writer + 1 reader, r6g.large)
- **CloudWatch**: Logs and metrics storage

For cost estimation, use the [AWS Pricing Calculator](https://calculator.aws/).

## Security Notes

- EKS cluster uses both public and private endpoint access
- Aurora MySQL is deployed in private subnets and is not publicly accessible
- Database credentials are automatically rotated and stored in Secrets Manager
- All Aurora storage is encrypted at rest
- EKS cluster logging is enabled for audit and troubleshooting

## Troubleshooting

### CDK Bootstrap Errors

If you encounter bootstrap errors, ensure your AWS credentials have sufficient permissions:

```bash
aws sts get-caller-identity
```

### EKS Connection Issues

If kubectl cannot connect to the cluster:

1. Ensure your AWS credentials are valid
2. Verify the cluster endpoint is accessible from your network
3. Check that your IAM user/role has the necessary EKS permissions

### Aurora Connection Issues

Aurora is only accessible from within the VPC. To connect:

1. Use an EC2 bastion host in the VPC
2. Use AWS Systems Manager Session Manager
3. Connect from an EKS pod running in the cluster
