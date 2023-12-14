# Stage 1: Build the package
FROM python:3.9 as builder

# Install zip
RUN apt-get update && apt-get install -y zip

# Set the working directory
WORKDIR /build

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the lambda function
COPY LambdaFunction.py .

# Zip the dependencies
RUN cd /usr/local/lib/python3.9/site-packages/ \
    && zip -r9 /build/LambdaFunction.zip . 

# Add the Lambda function code to the ZIP
RUN cd /build \
    && zip -g LambdaFunction.zip LambdaFunction.py

# Stage 2: Lightweight final image with basic utilities
FROM alpine:latest AS export-stage
COPY --from=builder /build/LambdaFunction.zip /

