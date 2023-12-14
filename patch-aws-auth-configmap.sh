#!/bin/bash

# Retrieve AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check if we got the account ID
if [ -z "$ACCOUNT_ID" ]; then
    echo "Failed to retrieve AWS account ID"
    exit 1
fi

ROLE="    - rolearn: arn:aws:iam::${ACCOUNT_ID}:role/SecurityEventWebhookLambdaRole\n      username: lambda"

kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > /tmp/aws-auth-patch.yml

kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"
