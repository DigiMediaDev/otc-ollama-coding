# provider.tf
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    opentelekomcloud = {
      source  = "opentelekomcloud/opentelekomcloud"
      version = ">= 1.35.0" # Zieht sich automatisch die neueste, kompatible Version
    }
  }
}

# Konfiguration des Providers
provider "opentelekomcloud" {
  # Zugangsdaten (AK/SK) kommen sicher aus den OS_ Umgebungsvariablen!
  # Wir geben hier nur noch hart die Region vor:
  region   = "eu-de"
  auth_url = "https://iam.eu-de.otc.t-systems.com/v3"
}
