variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Base name for resources"
  type        = string
  default     = "sandbox"
}

variable "mongo_key_name" {
  description = "EC2 key pair name for SSH access to the Mongo instance"
  type        = string
  default     = "sandbox-exercise-w"
}