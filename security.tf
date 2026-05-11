# Die Sicherheitsgruppe (Firewall-Regeln)
resource "opentelekomcloud_networking_secgroup_v2" "ai_secgroup" {
  name        = "ai-security-group"
  description = "Regeln fuer OpenCode und SSH"
}

# Regel 1: SSH Zugriff (Port 22) fuer dich
resource "opentelekomcloud_networking_secgroup_rule_v2" "ssh_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0" # Hier koenntest du spaeter deine eigene IP fuer mehr Sicherheit eintragen
  security_group_id = opentelekomcloud_networking_secgroup_v2.ai_secgroup.id
}

# Regel 2: Ollama API (Port 11434) fuer OpenCode
resource "opentelekomcloud_networking_secgroup_rule_v2" "ollama_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 11434
  port_range_max    = 11434
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = opentelekomcloud_networking_secgroup_v2.ai_secgroup.id
}