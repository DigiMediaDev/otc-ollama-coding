#!/bin/bash
SSH_OPTS="-i ~/.ssh/ai-ssh-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR"
MAX_WAIT_MIN=60

_elapsed() {
  local secs=$(( $(date +%s) - START_TIME ))
  printf "%02d:%02d" $(( secs / 60 )) $(( secs % 60 ))
}

_kill_tunnel() {
  pkill -f "ssh.*-L 11434" 2>/dev/null
  for i in $(seq 1 10); do
    ss -tlnp | grep -q ":11434" || return 0
    sleep 1
  done
  echo "Port 11434 still in use after 10s – check manually: ss -tlnp | grep 11434"
  return 1
}

_wait_for_ssh() {
  local ip=$1
  echo "[+] Waiting for SSH connection to $ip..."
  until ssh $SSH_OPTS ubuntu@$ip "exit" 2>/dev/null; do
    printf "\r[+] SSH not reachable... [%s elapsed]" "$(_elapsed)"
    sleep 5
  done
  echo -e "\r[+] SSH available after $(_elapsed)                    "
}

_wait_for_ollama() {
  local ip=$1
  local max_rounds=$(( MAX_WAIT_MIN * 6 ))
  echo "[+] Waiting for Ollama (install + model download, max. ${MAX_WAIT_MIN} min)..."
  for i in $(seq 1 $max_rounds); do
    if ssh $SSH_OPTS ubuntu@$ip "curl -sf http://localhost:11434/ > /dev/null 2>&1"; then
      echo -e "\r[+] Ollama ready after $(_elapsed)!                         "
      return 0
    fi
    local secs_left=$(( (max_rounds - i) * 10 ))
    printf "\r[+] Not ready yet – %s elapsed, up to %02d:%02d remaining..." \
      "$(_elapsed)" $(( secs_left / 60 )) $(( secs_left % 60 ))
    sleep 10
  done
  echo ""
  echo ""
  echo "[!] Ollama did not respond after ${MAX_WAIT_MIN} minutes."
  echo ""
  echo "    Debug on the server:"
  echo "    ssh $SSH_OPTS ubuntu@$ip"
  echo ""
  echo "    Then:"
  echo "      sudo tail -50 /var/log/cloud-init-output.log  # cloud-init progress"
  echo "      systemctl status ollama                        # service status"
  echo "      journalctl -u ollama -n 30 --no-pager         # Ollama logs"
  return 1
}

START_TIME=$(date +%s)

# Pass OTC credentials to Terraform for OBS access
export TF_VAR_obs_ak="$OS_ACCESS_KEY"
export TF_VAR_obs_sk="$OS_SECRET_KEY"

# Optional AZ override: ./ki-start.sh eu-de-02
if [ -n "$1" ]; then
  export TF_VAR_availability_zone="$1"
  echo "[+] Availability zone: $1"
fi

echo "=== OTC AI Infrastructure ==="
echo ""

# Kill any existing tunnel and wait for port to be released
_kill_tunnel || exit 1

echo "[+] Running terraform apply..."
if ! terraform apply -auto-approve; then
  echo ""
  echo "[!] Terraform failed – server was not created. Aborting."
  exit 1
fi

SERVER_IP=$(terraform output -raw gpu_server_ip)
echo "[+] Server IP: $SERVER_IP"

# Host-Key für neue IP löschen, falls Server neu erstellt wurde
ssh-keygen -R "$SERVER_IP" 2>/dev/null

_wait_for_ssh "$SERVER_IP"
_wait_for_ollama "$SERVER_IP" || exit 1

_kill_tunnel || exit 1
ssh $SSH_OPTS -L 11434:localhost:11434 -N ubuntu@$SERVER_IP &

echo ""
echo "[+] Tunnel active after $(_elapsed) total!"
echo "[+] VS Code Continue URL: http://localhost:11434"
