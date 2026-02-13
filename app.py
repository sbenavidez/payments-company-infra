#!/usr/bin/env python3
"""AWS CDK application entry point for Payments Company Infrastructure."""
import aws_cdk as cdk

from payments_company_infra.payments_company_infra_stack import PaymentsCompanyInfraStack


app = cdk.App()
PaymentsCompanyInfraStack(
    app,
    "PaymentsCompanyInfraStack",
    description="Payments Company Infrastructure - VPC, EKS Cluster, and Aurora MySQL"
)

app.synth()
