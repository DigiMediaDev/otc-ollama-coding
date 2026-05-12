# 1. VPC
resource "opentelekomcloud_vpc_v1" "ai_vpc" {
  name = "ai-vpc-opencode"
  cidr = "10.0.0.0/16"
}

# 2. Subnet
resource "opentelekomcloud_vpc_subnet_v1" "ai_subnet" {
  name       = "ai-subnet-gpu"
  vpc_id     = opentelekomcloud_vpc_v1.ai_vpc.id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"

  # OTC default DNS + Google fallback for outbound internet access (e.g. model downloads)
  dns_list = ["100.125.4.25", "8.8.8.8"]
}

# 3. Elastic IP (public, static)
resource "opentelekomcloud_vpc_eip_v1" "ai_eip" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "ai-bandwidth"
    size        = 100
    share_type  = "PER"
    charge_mode = "traffic"
  }
}