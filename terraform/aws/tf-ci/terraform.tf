terraform {

  backend "s3" {
    bucket         = "tf-backend-ci-test-us-east-1"
    dynamodb_table = "tf-backend"
    key            = "state/tf.state"
    encrypt        = true
    kms_key_id     = "alias/tf-backend"
    region         = "us-east-1"
  }

  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  ignore_tags {
    key_prefixes = ["map-migrated"]
  }
}
