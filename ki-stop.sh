#!/bin/bash
echo "🛑 Beende KI-Session..."

# 1. SSH-Tunnel killen
pkill -f "ssh -L 11434:localhost:11434"

# 2. NUR den Server löschen (EIP, Netzwerk und Modell-Volume bleiben bestehen)
terraform destroy \
  -target=opentelekomcloud_compute_volume_attach_v2.models_attach \
  -target=opentelekomcloud_compute_instance_v2.ai_server \
  -auto-approve

SERVER_IP=$(terraform output -raw gpu_server_ip 2>/dev/null)
[ -n "$SERVER_IP" ] && ssh-keygen -R "$SERVER_IP" 2>/dev/null

echo "Server gelöscht. EVS Volume, EIP und Netzwerk bleiben erhalten."