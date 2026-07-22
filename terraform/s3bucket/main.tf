resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "demo" {
  bucket = "vault-demo-bucket-${random_id.bucket_suffix.hex}"
}
