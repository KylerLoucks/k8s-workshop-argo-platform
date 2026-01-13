

module "s3-bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.10.0"

  bucket = "ex-${basename(path.cwd)}-tf-ci"

  tags = {
    ManagedBy = "terraform"
  }
}
