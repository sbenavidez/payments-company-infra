"""Main infrastructure stack for Payments Company.

This module defines the AWS CDK stack containing:
- VPC with 3 AZs and 6 subnets (public and private)
- EKS cluster with CloudWatch Observability add-on
- Aurora MySQL database cluster
"""
from constructs import Construct
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_rds as rds,
    aws_iam as iam,
    CfnOutput,
    RemovalPolicy,
)
from aws_cdk.lambda_layer_kubectl_v32 import KubectlV32Layer


class PaymentsCompanyInfraStack(Stack):
    """CDK Stack for Payments Company Infrastructure."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC
        vpc = self._create_vpc()

        # Create EKS cluster
        eks_cluster = self._create_eks_cluster(vpc)

        # Create Aurora MySQL cluster
        aurora_cluster = self._create_aurora_cluster(vpc, eks_cluster)

        # Outputs
        self._create_outputs(vpc, eks_cluster, aurora_cluster)

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC spanning 3 Availability Zones with public and private subnets.

        Returns:
            ec2.Vpc: The created VPC with 6 subnets (1 public and 1 private per AZ)
        """
        vpc = ec2.Vpc(
            self,
            "PaymentsVpc",
            vpc_name="payments-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags for identification
        cdk.Tags.of(vpc).add("Name", "payments-vpc")
        cdk.Tags.of(vpc).add("Environment", "production")

        return vpc

    def _create_eks_cluster(self, vpc: ec2.Vpc) -> eks.Cluster:
        """Create EKS cluster with CloudWatch Observability add-on.

        Args:
            vpc: The VPC where the EKS cluster will be deployed

        Returns:
            eks.Cluster: The created EKS cluster with worker nodes
        """
        # Create IAM role for CloudWatch Observability add-on
        cloudwatch_observability_role = iam.Role(
            self,
            "CloudWatchObservabilityRole",
            role_name="PaymentsEKSCloudWatchObservabilityRole",
            assumed_by=iam.ServicePrincipal("pods.eks.amazonaws.com"),
        )

        # Attach CloudWatch Agent policy for observability
        cloudwatch_observability_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )
        cloudwatch_observability_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSXrayWriteOnlyAccess")
        )

        # Create EKS cluster
        eks_cluster = eks.Cluster(
            self,
            "PaymentsEksCluster",
            cluster_name="payments-eks-cluster",
            version=eks.KubernetesVersion.V1_32,
            vpc=vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            default_capacity=0,
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
            kubectl_layer=KubectlV32Layer(self, "KubectlLayer"),
        )

        # Add managed node group with 2 worker nodes on m6a.large instances
        eks_cluster.add_nodegroup_capacity(
            "PaymentsNodeGroup",
            nodegroup_name="payments-worker-nodes",
            instance_types=[ec2.InstanceType("m6a.large")],
            min_size=2,
            max_size=2,
            desired_size=2,
            disk_size=50,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            capacity_type=eks.CapacityType.ON_DEMAND,
            ami_type=eks.NodegroupAmiType.AL2023_X86_64_STANDARD,
        )

        # Create pod identity association for CloudWatch Observability add-on
        eks.CfnPodIdentityAssociation(
            self,
            "CloudWatchObservabilityPodIdentity",
            cluster_name=eks_cluster.cluster_name,
            namespace="amazon-cloudwatch",
            service_account="cloudwatch-agent",
            role_arn=cloudwatch_observability_role.role_arn,
        )

        # Add Amazon CloudWatch Observability EKS add-on
        eks.CfnAddon(
            self,
            "CloudWatchObservabilityAddon",
            addon_name="amazon-cloudwatch-observability",
            cluster_name=eks_cluster.cluster_name,
            resolve_conflicts="OVERWRITE",
        )

        # Add tags for identification
        cdk.Tags.of(eks_cluster).add("Name", "payments-eks-cluster")
        cdk.Tags.of(eks_cluster).add("Environment", "production")

        return eks_cluster

    def _create_aurora_cluster(
        self, vpc: ec2.Vpc, eks_cluster: eks.Cluster
    ) -> rds.DatabaseCluster:
        """Create Aurora MySQL database cluster.

        Args:
            vpc: The VPC where the Aurora cluster will be deployed
            eks_cluster: The EKS cluster (for security group access)

        Returns:
            rds.DatabaseCluster: The created Aurora MySQL cluster
        """
        # Create security group for Aurora
        aurora_security_group = ec2.SecurityGroup(
            self,
            "AuroraSecurityGroup",
            vpc=vpc,
            security_group_name="payments-aurora-sg",
            description="Security group for Aurora MySQL cluster",
            allow_all_outbound=True,
        )

        # Allow access from EKS worker nodes
        aurora_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from VPC",
        )

        # Create Aurora MySQL cluster
        aurora_cluster = rds.DatabaseCluster(
            self,
            "PaymentsAuroraCluster",
            cluster_identifier="payments-aurora-cluster",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_3_08_0
            ),
            credentials=rds.Credentials.from_generated_secret(
                "payments_admin",
                secret_name="payments/aurora/credentials",
            ),
            default_database_name="payments",
            writer=rds.ClusterInstance.provisioned(
                "Writer",
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
                ),
            ),
            readers=[
                rds.ClusterInstance.provisioned(
                    "Reader",
                    instance_type=ec2.InstanceType.of(
                        ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
                    ),
                ),
            ],
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            security_groups=[aurora_security_group],
            storage_encrypted=True,
            backup=rds.BackupProps(
                retention=cdk.Duration.days(7),
            ),
            deletion_protection=False,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Add tags for identification
        cdk.Tags.of(aurora_cluster).add("Name", "payments-aurora-cluster")
        cdk.Tags.of(aurora_cluster).add("Environment", "production")

        return aurora_cluster

    def _create_outputs(
        self,
        vpc: ec2.Vpc,
        eks_cluster: eks.Cluster,
        aurora_cluster: rds.DatabaseCluster,
    ) -> None:
        """Create CloudFormation outputs for the stack resources.

        Args:
            vpc: The created VPC
            eks_cluster: The created EKS cluster
            aurora_cluster: The created Aurora MySQL cluster
        """
        CfnOutput(
            self,
            "VpcId",
            value=vpc.vpc_id,
            description="VPC ID",
            export_name="PaymentsVpcId",
        )

        CfnOutput(
            self,
            "EksClusterName",
            value=eks_cluster.cluster_name,
            description="EKS Cluster Name",
            export_name="PaymentsEksClusterName",
        )

        CfnOutput(
            self,
            "EksClusterEndpoint",
            value=eks_cluster.cluster_endpoint,
            description="EKS Cluster API Endpoint",
            export_name="PaymentsEksClusterEndpoint",
        )

        CfnOutput(
            self,
            "EksClusterArn",
            value=eks_cluster.cluster_arn,
            description="EKS Cluster ARN",
            export_name="PaymentsEksClusterArn",
        )

        CfnOutput(
            self,
            "EksKubectlCommand",
            value=f"aws eks update-kubeconfig --name {eks_cluster.cluster_name} --region ${{AWS_REGION}}",
            description="Command to configure kubectl",
        )

        CfnOutput(
            self,
            "AuroraClusterEndpoint",
            value=aurora_cluster.cluster_endpoint.hostname,
            description="Aurora MySQL Cluster Writer Endpoint",
            export_name="PaymentsAuroraClusterEndpoint",
        )

        CfnOutput(
            self,
            "AuroraClusterReaderEndpoint",
            value=aurora_cluster.cluster_read_endpoint.hostname,
            description="Aurora MySQL Cluster Reader Endpoint",
            export_name="PaymentsAuroraClusterReaderEndpoint",
        )

        CfnOutput(
            self,
            "AuroraSecretArn",
            value=aurora_cluster.secret.secret_arn if aurora_cluster.secret else "N/A",
            description="ARN of the secret containing Aurora credentials",
            export_name="PaymentsAuroraSecretArn",
        )
