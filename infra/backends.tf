terraform {
  backend "s3" {
    bucket         = "bucket123ultra"
    key            = "terraform/state.tfstate"  # Adjust the key to your desired state file path
    region         = "us-east-1"                # Replace with your S3 bucket's region
    encrypt        = true                       # Enable state file encryption
     dynamodb_table = "terraform-lock-table"     # Enable the state locking
  }
}
