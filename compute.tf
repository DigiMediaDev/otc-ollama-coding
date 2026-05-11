# --- 1. DAS SCHLOSS (Public Key) REGISTRIEREN ---
resource "opentelekomcloud_compute_keypair_v2" "ai_key" {
  name       = "ai-ssh-key"
  public_key = file("${path.module}/ai-ssh-key.pub")
}

# --- 2. PERSISTENTES MODELL-VOLUME (bleibt beim ki-stop erhalten) ---
resource "opentelekomcloud_blockstorage_volume_v2" "ollama_models" {
  name              = "ollama-models-volume"
  size              = 100
  volume_type       = "SSD"
  availability_zone = "eu-de-01"
}

# --- 3. DER GPU SERVER ---
resource "opentelekomcloud_compute_instance_v2" "ai_server" {
  name              = "gpu-ollama-node"
  image_name        = "Standard_Ubuntu_22.04_GPU_NV_latest"
  flavor_id         = "p2s.2xlarge.8"
  availability_zone = "eu-de-01"
  key_pair          = opentelekomcloud_compute_keypair_v2.ai_key.name
  security_groups   = [opentelekomcloud_networking_secgroup_v2.ai_secgroup.name]

  network {
    uuid = opentelekomcloud_vpc_subnet_v1.ai_subnet.id
  }

  user_data = <<-EOF
#!/bin/bash
exec > /var/log/ki-setup.log 2>&1
export HOME=/root

# 1. SSH-Forwarding erlauben
mkdir -p /etc/ssh/sshd_config.d
echo "AllowTcpForwarding yes" > /etc/ssh/sshd_config.d/99-allow-port-forwarding.conf
systemctl restart ssh

# 2. Ollama installieren
curl -fsSL https://ollama.com/install.sh | sh

# 3. EVS Volume mounten (persistente Modell-Ablage)
VOLUME=/dev/vdb
MOUNT=/usr/share/ollama/.ollama/models

echo "Warte auf EVS Volume ($VOLUME)..."
until [ -b "$VOLUME" ]; do sleep 2; done

# Nur formatieren wenn noch kein Filesystem drauf ist (erster Start)
if ! blkid "$VOLUME" | grep -q "TYPE"; then
  echo "Neues Volume – formatiere mit ext4..."
  mkfs.ext4 "$VOLUME"
fi

mkdir -p "$MOUNT"
mount "$VOLUME" "$MOUNT"
resize2fs "$VOLUME"
chown -R ollama:ollama /usr/share/ollama/.ollama/

# Automatisch mounten nach Reboot
echo "$VOLUME $MOUNT ext4 defaults 0 2" >> /etc/fstab

# 4. Ollama konfigurieren
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<CONF
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_KEEP_ALIVE=2h"
CONF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# 5. Warten bis Ollama API antwortet
echo "Warte auf Ollama API..."
until curl -sf http://localhost:11434/ > /dev/null 2>&1; do
  sleep 5
done

# 6. Modell nur laden wenn noch nicht auf dem Volume
for MODEL in qwen2.5-coder:32b qwen2.5-coder:14b; do
  if sudo -u ollama HOME=/usr/share/ollama /usr/local/bin/ollama list | grep -q "$MODEL"; then
    echo "$MODEL bereits auf Volume – kein Download nötig."
  else
    echo "Lade $MODEL herunter..."
    sudo -u ollama HOME=/usr/share/ollama /usr/local/bin/ollama pull "$MODEL"
    echo "$MODEL abgeschlossen."
  fi
done
EOF
}

# --- 4. MODELL-VOLUME AN SERVER ANHÄNGEN ---
resource "opentelekomcloud_compute_volume_attach_v2" "models_attach" {
  instance_id = opentelekomcloud_compute_instance_v2.ai_server.id
  volume_id   = opentelekomcloud_blockstorage_volume_v2.ollama_models.id
}

# --- 5. VERKNÜPFUNG VON IP UND SERVER ---
resource "opentelekomcloud_compute_floatingip_associate_v2" "fip_1" {
  floating_ip = opentelekomcloud_vpc_eip_v1.ai_eip.publicip[0].ip_address
  instance_id = opentelekomcloud_compute_instance_v2.ai_server.id
}

# --- 6. DIE AUSGABE ---
output "gpu_server_ip" {
  value = opentelekomcloud_vpc_eip_v1.ai_eip.publicip[0].ip_address
}
