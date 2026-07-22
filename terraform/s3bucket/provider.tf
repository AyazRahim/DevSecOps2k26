provider "aws" {
  region = "us-east-1"
  # Credentials injected at runtime via environment variables:
  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
}
