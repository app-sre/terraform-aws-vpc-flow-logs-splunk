terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.3.0, < 3.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0, < 4.0.0"
    }
  }
}
