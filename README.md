# calico security event handler

Work in progess...

## About

Calico Security Event Handler is a serverless pattern for processing Calico Security Events.

This project implements a pattern that integrates an Amazon API Gateway HTTP API endpoint with Amazon EventBridge using service integrations. The primary function of this setup is to monitor and route Calico Security Events, based on predefined event patterns, to an AWS Lambda Function for processing. It builds upon the foundational API Gateway HTTP API to Amazon EventBridge pattern from [Serverless Land](https://serverlessland.com/patterns/apigateway-http-eventbridge-terraform), enhancing it for specific use with Calico Security Events.

## Architecture

![eventfun](/img/events.png)

## How it works

![eventfun](/img/webhooks.png)

## Build

Package Lambda function and python dependencies.

```sh
export DOCKER_SCAN_SUGGEST=false
docker build -t lambda-packager . && \
  docker run --rm lambda-packager cat /LambdaFunction.zip > LambdaFunction.zip
```

## Deploy

Deploy the Security Event handler reference architecture. 

Terraform will detect updates to the Lambda function and automatically redeploy the updated zip files. This makes it easy to iterate on enhancements to the python Lambda function.

```sh
terraform init
terraform apply --auto-approve
```

## Enabling AWS IAM principal access to your cluster

Add the Lambda IAM role to the `aws-auth` configmap.

```sh
sh patch-aws-auth-configmap.sh
```

Add role-based access control (RBAC) access for the Lambda IAM role

```
kubectl apply -f rbac.yaml
```

## Validate the Deployment and Review the Results

## Reference

AWS Open Source Blog - [A Container-Free Way to Configure Kubernetes Using AWS Lambda](https://aws.amazon.com/blogs/opensource/a-container-free-way-to-configure-kubernetes-using-aws-lambda/)

