# Security group (firewall rules)
resource "opentelekomcloud_networking_secgroup_v2" "ai_secgroup" {
  name        = "ai-security-group"
  description = "Rules for Ollama API and SSH"
}

# Rule 1: SSH access (port 22)
resource "opentelekomcloud_networking_secgroup_rule_v2" "ssh_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0" # Replace with your IP for stricter access control
  security_group_id = opentelekomcloud_networking_secgroup_v2.ai_secgroup.id
}

# Rule 2: Ollama API (port 11434)
resource "opentelekomcloud_networking_secgroup_rule_v2" "ollama_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 11434
  port_range_max    = 11434
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = opentelekomcloud_networking_secgroup_v2.ai_secgroup.id
}