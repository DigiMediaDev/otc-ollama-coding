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
  echo "Port 11434 noch belegt nach 10 Sek – bitte manuell prüfen (ss -tlnp | grep 11434)"
  return 1
}

_wait_for_ssh() {
  local ip=$1
  echo "[+] Warte auf SSH-Verbindung zu $ip..."
  until ssh $SSH_OPTS ubuntu@$ip "exit" 2>/dev/null; do
    printf "\r[+] SSH nicht erreichbar... [%s vergangen]" "$(_elapsed)"
    sleep 5
  done
  echo -e "\r[+] SSH verfügbar nach $(_elapsed)                    "
}

_wait_for_ollama() {
  local ip=$1
  local max_rounds=$(( MAX_WAIT_MIN * 6 ))
  echo "[+] Warte auf Ollama (Installation + Modell-Download, max. ${MAX_WAIT_MIN} Min.)..."
  for i in $(seq 1 $max_rounds); do
    if ssh $SSH_OPTS ubuntu@$ip "curl -sf http://localhost:11434/ > /dev/null 2>&1"; then
      echo -e "\r[+] Ollama bereit nach $(_elapsed)!                         "
      return 0
    fi
    local secs_left=$(( (max_rounds - i) * 10 ))
    printf "\r[+] Noch nicht bereit – %s vergangen, noch ca. %02d:%02d möglich..." \
      "$(_elapsed)" $(( secs_left / 60 )) $(( secs_left % 60 ))
    sleep 10
  done
  echo ""
  echo ""
  echo "[!] Ollama hat nach ${MAX_WAIT_MIN} Minuten nicht geantwortet."
  echo ""
  echo "    Zum Debuggen auf dem Server:"
  echo "    ssh $SSH_OPTS ubuntu@$ip"
  echo ""
  echo "    Dann:"
  echo "      sudo tail -50 /var/log/cloud-init-output.log  # Was macht cloud-init?"
  echo "      systemctl status ollama                        # Läuft der Dienst?"
  echo "      journalctl -u ollama -n 30 --no-pager         # Ollama-Logs"
  return 1
}

START_TIME=$(date +%s)

echo "=== OTC AI-Infrastruktur ==="
echo ""

# Alten Tunnel beenden und auf Port-Freigabe warten
_kill_tunnel || exit 1

echo "[+] Starte Terraform..."
if ! terraform apply -auto-approve; then
  echo ""
  echo "[!] Terraform fehlgeschlagen – Server wurde nicht erstellt. Abbruch."
  exit 1
fi

SERVER_IP=$(terraform output -raw gpu_server_ip)
echo "[+] Server-IP: $SERVER_IP"

# Host-Key für neue IP löschen, falls Server neu erstellt wurde
ssh-keygen -R "$SERVER_IP" 2>/dev/null

_wait_for_ssh "$SERVER_IP"
_wait_for_ollama "$SERVER_IP" || exit 1

_kill_tunnel || exit 1
ssh $SSH_OPTS -L 11434:localhost:11434 -N ubuntu@$SERVER_IP &

echo ""
echo "[+] Tunnel aktiv nach $(_elapsed) Gesamtzeit!"
echo "[+] VS Code Continue URL: http://localhost:11434"
