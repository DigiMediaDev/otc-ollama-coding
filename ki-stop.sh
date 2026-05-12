#!/bin/bash
echo "Stopping AI session..."

# Kill SSH tunnel
pkill -f "ssh.*-L 11434" 2>/dev/null

# Destroy all resources — models are safe in OBS
terraform destroy -auto-approve

echo "Done. OBS model storage and elastic IP are preserved."
