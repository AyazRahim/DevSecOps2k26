provider "aws" {
  region = "us-east-1"

  # Credentials are injected via environment variables by the CI pipeline:
  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
  # Skip the STS GetCallerIdentity call that fails with dynamic Vault credentials
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "test_bucket" {
  bucket = "vault-demo-bucket-${random_id.bucket_suffix.hex}"
}
