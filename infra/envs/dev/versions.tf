terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "wiz-exercise-terraform-state-699475911376"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "wiz-exercise-terraform-locks"
    encrypt        = true
  }
}

