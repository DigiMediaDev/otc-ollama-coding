# provider.tf
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    opentelekomcloud = {
      source  = "opentelekomcloud/opentelekomcloud"
      version = ">= 1.35.0"
    }
  }
}

# Provider configuration
provider "opentelekomcloud" {
  # Credentials (AK/SK) are read from OS_ACCESS_KEY / OS_SECRET_KEY environment variables
  region   = "eu-de"
  auth_url = "https://iam.eu-de.otc.t-systems.com/v3"
}
