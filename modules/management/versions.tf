terraform {
  // Latest version at the time of initial development
  required_version = ">=1.11.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.97"
    }
  }
}
