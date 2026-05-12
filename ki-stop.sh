#!/bin/bash
echo "Stopping AI session..."

# 1. Kill SSH tunnel
pkill -f "ssh -L 11434:localhost:11434"

# 2. Destroy server only — EIP, network and model volume are preserved
terraform destroy \
  -target=opentelekomcloud_compute_volume_attach_v2.models_attach \
  -target=opentelekomcloud_compute_instance_v2.ai_server \
  -auto-approve

SERVER_IP=$(terraform output -raw gpu_server_ip 2>/dev/null)
[ -n "$SERVER_IP" ] && ssh-keygen -R "$SERVER_IP" 2>/dev/null

echo "Server destroyed. EVS volume, EIP and network are preserved."