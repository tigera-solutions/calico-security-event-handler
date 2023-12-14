variable "region" {
  description = "AWS Region of deployment"
  type        = string
  default     = "us-east-1"
}

variable "zipfile" {
  description = "Lambda Function Zip File"
  type        = string
  default     = "LambdaFunction.zip"
}
