variable "availability_zone" {
  description = "OTC Availability Zone (eu-de-01, eu-de-02, eu-de-03)"
  default     = "eu-de-01"
}

variable "obs_ak" {
  description = "AK for OBS access (defaults to OS_ACCESS_KEY)"
  sensitive   = true
  default     = ""
}

variable "obs_sk" {
  description = "SK for OBS access (defaults to OS_SECRET_KEY)"
  sensitive   = true
  default     = ""
}
